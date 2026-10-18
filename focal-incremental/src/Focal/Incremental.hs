{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeOperators #-}

-- | The incremental layer over the patch layer.
--
--   A memo cell caches a computed term together with the patch that last
--   produced it (the invalidation key); a dependency trace records which
--   variables the cached term actually reads ('traceDeps' — the
--   free-variable set, deduplicated and in order of first occurrence).
--   Invalidation walks the trace against a patch's claimed variables
--   ('Focal.Delta.claimed'): a memo is stale when the patch would change
--   a variable the cached term reads ('invalidatedBy', with 'memoRead' /
--   'memoWrite' as the read-through / write-through pair).  The v1 model
--   is single-cell — one memo, one trace; multi-cell scheduling is out
--   of scope.  The invalidation graph makes the reachability explicit:
--   one edge per claimed variable, marking which claims reach the memo
--   ('InvalEdge', 'invalGraph').  The incremental plug closes the loop
--   ('incrementalPlug'): a patch that invalidates the memo forces
--   recomputation — v1 recomputes by applying the patch to the cached
--   term ('recomputePatch', the computation seam; real consumers
--   substitute their own function) — and a clean patch reads through.
--   The output ('OutputDelta') carries its provenance, 'memoUpdate'
--   re-keys the cache to the patch that produced the recomputed term,
--   and 'firedEdges' reports which claimed variables reached the memo
--   (the edges that fired).  No complexity claims are made: any
--   cost statement would bind to a concrete persistent-tree
--   representation, which is outside the v1 scope.
--
--   >>> :set -XDataKinds -XTypeOperators
--   >>> import Focal.Delta
--   >>> import Focal.Redex
--   >>> import Focal.Refactor
--   >>> import Focal.Syntax
--   >>> traceDeps (RVar FZ :: Rm '[U] U)
--   [SomeFin FZ]
--   >>> traceDeps (RUnit :: Rm '[] U)
--   []
--   >>> traceDeps (RApp (RLam TyRepU (RVar (FS FZ))) (RVar (FS FZ)) :: Rm '[U, U] U)
--   [SomeFin FZ,SomeFin (FS FZ)]
--   >>> memoReads (Memo PNil (RVar FZ :: Rm '[U] U)) (SomeFin (FZ :: Fin '[U] U))
--   True
--   >>> invalidatedBy (Memo PNil (RVar FZ :: Rm '[U] U)) (PCons (SomeEdit (Edit (FZ :: Fin '[U] U) RUnit)) PNil)
--   True
--   >>> invalidatedBy (Memo PNil (RVar FZ :: Rm '[U] U)) PNil
--   False
--   >>> invalGraph (Memo PNil (RVar FZ :: Rm '[U] U)) (PCons (SomeEdit (Edit (FZ :: Fin '[U] U) RUnit)) PNil)
--   [Edge (SomeFin FZ) True]
--   >>> memoRead (Memo PNil (RVar FZ :: Rm '[U] U)) PNil
--   Just (RVar FZ)
--   >>> memoRead (Memo PNil (RVar FZ :: Rm '[U] U)) (PCons (SomeEdit (Edit (FZ :: Fin '[U] U) RUnit)) PNil)
--   Nothing
--   >>> incrementalPlug recomputePatch (Memo PNil (RVar FZ :: Rm '[U] U)) (PCons (SomeEdit (Edit (FZ :: Fin '[U] U) RUnit)) PNil)
--   Recomputed RUnit (PCons (SomeEdit (Edit FZ RUnit)) PNil)
--   >>> incrementalPlug recomputePatch (Memo PNil (RUnit :: Rm '[] U)) PNil
--   Clean RUnit
--   >>> memoUpdate (Memo PNil (RVar FZ :: Rm '[U] U)) (incrementalPlug recomputePatch (Memo PNil (RVar FZ :: Rm '[U] U)) (PCons (SomeEdit (Edit (FZ :: Fin '[U] U) RUnit)) PNil))
--   Memo (PCons (SomeEdit (Edit FZ RUnit)) PNil) RUnit
--   >>> firedEdges (Memo PNil (RVar FZ :: Rm '[U, U] U)) (PCons (SomeEdit (Edit (FZ :: Fin '[U, U] U) RUnit)) (PCons (SomeEdit (Edit (FS FZ :: Fin '[U, U] U) RUnit)) PNil))
--   [SomeFin FZ]
module Focal.Incremental
  ( traceDeps
  , Memo(..)
  , memoDeps
  , memoReads
  , invalidatedBy
  , memoWrite
  , memoRead
  , InvalEdge(..)
  , invalGraph
  , OutputDelta(..)
  , incrementalPlug
  , recomputePatch
  , memoUpdate
  , firedEdges
  , sameSomeFin
  ) where

import Data.Maybe (mapMaybe)

import Focal.Delta (Patch(..), applyPatch, claimed)
import Focal.Redex (Fin(..), Rm(..))
import Focal.Refactor (SomeFin(..))
import Focal.Syntax (Ty(..))

--------------------------------------------------------------------
-- Positional comparison
--------------------------------------------------------------------

-- | Positional equality of two variables: the same spine position in
--   the same context is the same variable.  Structural on the 'Fin'
--   spine, polymorphic in the compared contexts and sorts.
samePos :: Fin g1 s1 -> Fin g2 s2 -> Bool
samePos FZ     FZ     = True
samePos (FS i) (FS j) = samePos i j
samePos _      _      = False

-- | Positional equality of two existentially sorted variables.
sameSomeFin :: SomeFin g -> SomeFin g -> Bool
sameSomeFin (SomeFin i) (SomeFin j) = samePos i j

--------------------------------------------------------------------
-- Dependency trace
--------------------------------------------------------------------

-- | Remove later duplicates (positional equality), keeping the first
--   occurrence of each variable.
dedupe :: [SomeFin g] -> [SomeFin g]
dedupe = go []
  where
    go _ []     = []
    go seen (s : rest)
      | any (sameSomeFin s) seen = go seen rest
      | otherwise                = s : go (s : seen) rest

-- | Drop a binder's own variable: 'FZ' maps to 'Nothing', deeper
--   variables shift down by one.
dropTop :: SomeFin (v ': g) -> Maybe (SomeFin g)
dropTop (SomeFin FZ)     = Nothing
dropTop (SomeFin (FS i)) = Just (SomeFin i)

-- | The variables a term reads: its free-variable set, deduplicated and
--   in order of first occurrence (the dependency trace).
traceDeps :: Rm g t -> [SomeFin g]
traceDeps RUnit      = []
traceDeps (RVar i)   = [SomeFin i]
traceDeps (RLam _ b) = mapMaybe dropTop (traceDeps b)
traceDeps (RApp f x) = dedupe (traceDeps f ++ traceDeps x)

--------------------------------------------------------------------
-- Memo cell
--------------------------------------------------------------------

-- | A memo cell: the cached term plus the patch that produced it (the
--   invalidation key).  The v1 model is single-cell — one memo, one
--   trace.
data Memo (g :: [Ty]) (t :: Ty) where
  Memo :: Patch g -> Rm g t -> Memo g t

-- | The memo's dependency trace: what the cached term reads.
memoDeps :: Memo g t -> [SomeFin g]
memoDeps (Memo _ t) = traceDeps t

--------------------------------------------------------------------
-- Invalidation
--------------------------------------------------------------------

-- | Positional comparison of a variable against an existentially
--   sorted one.
samePosIfFin :: Fin g s -> SomeFin g -> Bool
samePosIfFin i (SomeFin j) = samePos i j

-- | Does any read variable match any claimed variable?
anyClaimed :: [SomeFin g] -> [SomeFin g] -> Bool
anyClaimed [] _ = False
anyClaimed (SomeFin i : is) cs = any (samePosIfFin i) cs || anyClaimed is cs

-- | Does the memo read this variable?  Positional over the trace.
memoReads :: Memo g t -> SomeFin g -> Bool
memoReads (Memo _ t) s = any (sameSomeFin s) (traceDeps t)

-- | Invalidation: a memo is stale when a patch claims a variable the
--   cached term reads (the patch would change a dependency).  The v1
--   check is positional over the claimed variables.
invalidatedBy :: Memo g t -> Patch g -> Bool
invalidatedBy m p = anyClaimed (memoDeps m) (claimed p)

-- | Write-through: record a term in the cell together with the patch
--   that produced it.  Fresh computation is outside the layer — the
--   caller computes; the cell records the new key and term.
memoWrite :: Patch g -> Rm g t -> Memo g t
memoWrite = Memo

-- | Read-through when clean: the cached term is returned only when the
--   invalidating patch does not touch the memo's dependencies.  A stale
--   read reports 'Nothing'; recomputation is the caller's, via
--   'memoWrite'.
memoRead :: Memo g t -> Patch g -> Maybe (Rm g t)
memoRead m@(Memo _ t) p
  | invalidatedBy m p = Nothing
  | otherwise         = Just t

--------------------------------------------------------------------
-- Invalidation graph
--------------------------------------------------------------------

-- | One invalidation-graph edge: a claimed variable and whether it
--   reaches the memo (whether the memo reads it).  The v1 graph is a
--   star: one memo, one edge per claimed variable.
data InvalEdge (g :: [Ty]) where
  Edge :: SomeFin g -> Bool -> InvalEdge g

-- | 'Edge' takes two precedence 11 arguments.
instance Show (InvalEdge g) where
  showsPrec d (Edge c r) =
    showParen (d > 10)
      (showString "Edge " . showsPrec 11 c . showChar ' ' . showsPrec 11 r)

-- | 'Memo' takes two precedence 11 arguments.
instance Show (Memo g t) where
  showsPrec d (Memo p t) =
    showParen (d > 10)
      (showString "Memo " . showsPrec 11 p . showChar ' ' . showsPrec 11 t)

-- | The invalidation graph of a memo under a patch: one edge per
--   claimed variable, marking which claims reach the memo.
invalGraph :: Memo g t -> Patch g -> [InvalEdge g]
invalGraph m p = map (\c -> Edge c (memoReads m c)) (claimed p)

--------------------------------------------------------------------
-- Incremental plug
--------------------------------------------------------------------

-- | What the incremental layer outputs: the (possibly cached) result
--   with its provenance.  'Clean' is served from the memo; 'Recomputed'
--   carries the recomputed term together with the patch that forced it.
data OutputDelta (g :: [Ty]) (t :: Ty)
  = Clean (Rm g t)
  | Recomputed (Rm g t) (Patch g)

-- | 'Clean' takes one precedence 11 argument; 'Recomputed' takes two.
instance Show (OutputDelta g t) where
  showsPrec d (Clean t) =
    showParen (d > 10)
      (showString "Clean " . showsPrec 11 t)
  showsPrec d (Recomputed t p) =
    showParen (d > 10)
      (showString "Recomputed " . showsPrec 11 t . showChar ' ' . showsPrec 11 p)

-- | The v1 recomputation: apply the patch to the cached term (the
--   computation seam — the caller's \"computation\" in v1 IS the patched
--   term; real consumers substitute their own patch-to-term function
--   for 'incrementalPlug''s first argument).
recomputePatch :: Patch g -> Rm g t -> Rm g t
recomputePatch p t = applyPatch p t

-- | The incremental plug: run a patch against a memo.  A patch that
--   invalidates the memo (it claims a variable the cached term reads)
--   forces recomputation via the seam function (v1: 'recomputePatch');
--   a clean patch reads through the cache.
incrementalPlug :: (Patch g -> Rm g t -> Rm g t) -> Memo g t -> Patch g -> OutputDelta g t
incrementalPlug recompute m@(Memo _ t) p
  | invalidatedBy m p = Recomputed (recompute p t) p
  | otherwise         = Clean t

-- | Chain an output into a new memo: the recomputed term becomes the
--   cache, keyed by the patch that produced it; a clean output leaves
--   the memo untouched.
memoUpdate :: Memo g t -> OutputDelta g t -> Memo g t
memoUpdate _ (Recomputed t' p) = Memo p t'
memoUpdate m (Clean _)         = m

-- | The invalidation summary the layer reports: which claimed variables
--   reached the memo (the edges that fired).
firedEdges :: Memo g t -> Patch g -> [SomeFin g]
firedEdges m p = filter (memoReads m) (claimed p)
