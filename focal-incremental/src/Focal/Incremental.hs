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
--   ('InvalEdge', 'invalGraph').  No complexity claims are made: any
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
  ) where

import Data.Maybe (mapMaybe)

import Focal.Delta (Patch(..), claimed)
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

-- | The invalidation graph of a memo under a patch: one edge per
--   claimed variable, marking which claims reach the memo.
invalGraph :: Memo g t -> Patch g -> [InvalEdge g]
invalGraph m p = map (\c -> Edge c (memoReads m c)) (claimed p)
