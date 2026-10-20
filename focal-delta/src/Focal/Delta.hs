{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeOperators #-}

-- | The patch layer over the de Bruijn core.
--
--   An edit is evidence-carrying: it carries the variable it applies to
--   ('Fin') and the block ('Rm') that replaces each occurrence of that
--   variable.  A patch is a set of edits at distinct variables —
--   distinctness is the no-conflict invariant, witnessed positionally by
--   'samePos' and enforced by 'addEdit'.  Applying an edit is
--   substitution, so a patch always applies; the interesting questions
--   are which edits still matter ('survives' / 'survivingPatch' — a
--   patch's own edits can consume each other's targets) and how edits
--   move ('reindexEdit' / 'reindexPatch' along a refactor path).  A
--   conflict is two candidate blocks for one variable ('Clash' — equal
--   blocks would be one edit, so a real clash carries both) or the
--   zero-candidate case, a variable that no longer occurs ('NoSite').
--   The patch focus turns a local replacement into a global delta when
--   its variable occurs and reports the zero-candidate conflict
--   otherwise ('patchFocus' — the 'Either' is the patch layer's failure
--   channel).
--
--   The refactoring bridge reports the operations of "Focal.Refactor"
--   as evidence-carrying edits: a rename is a one-point edit — exactly
--   the operation when the target position is fresh ('renameEdit' /
--   'renamePatchFocus') — and an inlining is the innermost-variable
--   substitution ('inlineEdit' / 'inlineApply').  The transposition
--   side of a rename to an occupied target, and the deletion of the
--   inlined application, are structural and stay outside the edit
--   layer.
--
--   >>> :set -XDataKinds -XTypeOperators
--   >>> import Focal.Redex
--   >>> import Focal.Refactor
--   >>> import Focal.Syntax
--   >>> applyEdit (Edit (FZ :: Fin '[U] U) RUnit) (RVar FZ :: Rm '[U] U)
--   RUnit
--   >>> survives (Edit (FZ :: Fin '[U] U) RUnit) (RVar FZ :: Rm '[U] U)
--   True
--   >>> survives (Edit (FZ :: Fin '[U] U) RUnit) (RUnit :: Rm '[U] U)
--   False
--   >>> reindexEdit (RLamC TyRepU RHole :: RCtx '[U] '[U, U] U (U :-> U)) (Edit (FZ :: Fin '[U] U) (RVar FZ))
--   Edit (FS FZ) (RVar (FS FZ))
--   >>> applyPatch (PCons (SomeEdit (Edit (FZ :: Fin '[U] U) RUnit)) PNil) (RVar FZ :: Rm '[U] U)
--   RUnit
--   >>> conflict (Edit (FZ :: Fin '[U] U) RUnit) (Edit (FZ :: Fin '[U] U) (RVar FZ))
--   Just (Clash FZ RUnit (RVar FZ))
--   >>> conflict (Edit (FZ :: Fin '[U] U) RUnit) (Edit (FZ :: Fin '[U] U) RUnit)
--   Nothing
--   >>> patchFocus (Edit (FZ :: Fin '[U] U) RUnit) (RVar FZ :: Rm '[U] U)
--   Right (Delta (Edit FZ RUnit) RUnit)
--   >>> patchFocus (Edit (FZ :: Fin '[U] U) RUnit) (RUnit :: Rm '[U] U)
--   Left (NoSite FZ)
--   >>> patchFocus (Edit (FS FZ :: Fin '[U, U] U) RUnit) (RApp (RLam TyRepU (RVar FZ)) (RVar (FS FZ)) :: Rm '[U, U] U)
--   Right (Delta (Edit (FS FZ) RUnit) (RApp (RLam TyRepU (RVar FZ)) RUnit))
--   >>> reindexDelta (RLamC TyRepU RHole :: RCtx '[U] '[U, U] U (U :-> U)) (Delta (Edit (FZ :: Fin '[U] U) RUnit) (RVar FZ :: Rm '[U] U))
--   Delta (Edit (FS FZ) RUnit) (RVar (FS FZ))
--   >>> countOccurrences (FZ :: Fin '[U, U] U) (RApp (RLam TyRepU (RVar (FS FZ))) (RVar FZ) :: Rm '[U, U] U)
--   2
module Focal.Delta
  ( samePos
  , Edit(..)
  , applyEdit
  , survives
  , reindexEdit
  , composeEdit
  , SomeEdit(..)
  , Patch(..)
  , patchDistinct
  , addEdit
  , applyPatch
  , claimed
  , survivingPatch
  , reindexPatch
  , Conflict(..)
  , conflict
  , Delta(..)
  , patchFocus
  , countOccurrences
  , reindexDelta
  , deltaOn
  , renameEdit
  , renamePatchFocus
  , inlineEdit
  , inlineApply
  ) where

import Focal.Redex (Fin(..), Rm(..), lift1)
import Focal.Refactor
  ( RCtx(..)
  , SomeFin(..)
  , occursAt
  , substitute
  , weakenFin
  , weakenRm
  )
import Focal.Syntax (Ty, eqRep)

--------------------------------------------------------------------
-- Edits
--------------------------------------------------------------------

-- | Positional equality of two variables (the same de Bruijn position
--   in the same-length contexts).
samePos :: Fin g1 s1 -> Fin g2 s2 -> Bool
samePos FZ     FZ     = True
samePos (FS i) (FS j) = samePos i j
samePos _      _      = False

-- | What one edit says: the variable it applies to, and the block that
--   replaces each occurrence.
data Edit (g :: [Ty]) (s :: Ty) where
  Edit :: Fin g s -> Rm g s -> Edit g s

-- | 'Edit' takes two precedence 11 arguments.
instance Show (Edit g s) where
  showsPrec d (Edit i a) =
    showParen (d > 10)
      (showString "Edit " . showsPrec 11 i . showChar ' ' . showsPrec 11 a)

-- | A one-point patch: replace every occurrence of the edit's variable
--   by its block.  Application is substitution; a patch always applies.
applyEdit :: Edit g s -> Rm g t -> Rm g t
applyEdit (Edit i a) = substitute i a

-- | An edit survives in a term when its variable still occurs: the
--   survival witness.
survives :: Edit g s -> Rm g t -> Bool
survives (Edit i _) = occursAt i

-- | Reindex an edit along a refactor path: transport the variable and
--   the block to the hole's context (the block weakens per crossed
--   binder; the variable deepens).  Total: transport is a structural
--   embedding.
reindexEdit :: RCtx g h u v -> Edit g s -> Edit h s
reindexEdit k (Edit i a) = Edit (weakenFin k i) (weakenRm k a)

-- | Evidence transport for two edits at the same variable: the second
--   block is transformed by the first (@applyEdit e1 a'@), so the
--   composite's block is stated in the pre-@e1@ world.
--
--   This is NOT the sequential-application law in general: when the
--   first edit removes the variable's occurrences, the sequential
--   application makes the second edit a no-op while the composite still
--   fires — the divergence is pinned by 'prop_dl_compose_divergence'.
composeEdit :: Edit g s -> Edit g s -> Edit g s
composeEdit e1 (Edit i a') = Edit i (applyEdit e1 a')

-- | An edit whose variable's sort is hidden.
data SomeEdit (g :: [Ty]) = forall s. SomeEdit (Edit g s)

-- | 'SomeEdit' takes one precedence 11 argument.
instance Show (SomeEdit g) where
  showsPrec d (SomeEdit e) =
    showParen (d > 10) (showString "SomeEdit " . showsPrec 11 e)

--------------------------------------------------------------------
-- Patches
--------------------------------------------------------------------

-- | A patch: an ordered set of edits at distinct variables (distinctness
--   is the no-conflict invariant).  'PCons' is the unchecked
--   constructor; 'addEdit' is the checked form and refuses an edit at an
--   already-claimed variable.  Every claim phrased "per claimed
--   variable" is about patches that satisfy this distinctness invariant.
data Patch (g :: [Ty]) where
  PNil  :: Patch g
  PCons :: SomeEdit g -> Patch g -> Patch g

-- | 'PNil' prints bare; 'PCons' takes two precedence 11 arguments.
instance Show (Patch g) where
  showsPrec _ PNil            = showString "PNil"
  showsPrec d (PCons e rest) =
    showParen (d > 10)
      (showString "PCons " . showsPrec 11 e . showChar ' ' . showsPrec 11 rest)

-- | Is the variable absent from the patch (no claimed position matches)?
patchDistinct :: Fin g s -> Patch g -> Bool
patchDistinct _ PNil = True
patchDistinct i (PCons (SomeEdit (Edit j _)) rest) =
  not (samePos i j) && patchDistinct i rest

-- | Extend a patch with an edit at a fresh variable; 'Nothing' when the
--   variable is already claimed (the conflict: two candidate blocks for
--   one variable, no evidence to prefer either).  This is the checked
--   form; 'PCons' is the unchecked constructor.
addEdit :: Edit g s -> Patch g -> Maybe (Patch g)
addEdit e@(Edit i _) p
  | patchDistinct i p = Just (PCons (SomeEdit e) p)
  | otherwise         = Nothing

-- | Apply a patch: edits apply head-first, each at its own variable.
--   The distinct-variable invariant is a precondition of this
--   semantics.
applyPatch :: Patch g -> Rm g t -> Rm g t
applyPatch PNil                      = id
applyPatch (PCons (SomeEdit e) rest) = applyPatch rest . applyEdit e

-- | The variables a patch claims, in order.  For a patch that satisfies
--   the distinct-variable invariant the claims are pairwise distinct.
claimed :: Patch g -> [SomeFin g]
claimed PNil                               = []
claimed (PCons (SomeEdit (Edit i _)) rest) = SomeFin i : claimed rest

-- | Which edits survive in a term: those whose variable still occurs at
--   the moment the edit applies (a patch's own edits can consume each
--   other's targets).  The distinct-variable invariant is a
--   precondition.
survivingPatch :: Patch g -> Rm g t -> [SomeFin g]
survivingPatch PNil _ = []
survivingPatch (PCons (SomeEdit e@(Edit i _)) rest) t
  | survives e t  = SomeFin i : survivingPatch rest (applyEdit e t)
  | otherwise     = survivingPatch rest t

-- | Reindex a whole patch along a path (editwise).
reindexPatch :: RCtx g h u v -> Patch g -> Patch h
reindexPatch _ PNil                            = PNil
reindexPatch k (PCons (SomeEdit e) rest) =
  PCons (SomeEdit (reindexEdit k e)) (reindexPatch k rest)

--------------------------------------------------------------------
-- Conflicts
--------------------------------------------------------------------

-- | The conflict: two candidate blocks for one variable, or the
--   zero-candidate case — a replacement whose variable no longer occurs
--   (nothing to replace).  Equal blocks would be one edit, so a real
--   clash carries both.
data Conflict (g :: [Ty]) where
  Clash  :: Fin g s -> Rm g s -> Rm g s -> Conflict g
  NoSite :: Fin g s -> Conflict g

-- | 'Clash' takes three precedence 11 arguments; 'NoSite' takes one.
instance Show (Conflict g) where
  showsPrec d (Clash i a b) =
    showParen (d > 10)
      (  showString "Clash "
      .  showsPrec 11 i
      .  showChar ' '
      .  showsPrec 11 a
      .  showChar ' '
      .  showsPrec 11 b
      )
  showsPrec d (NoSite i) =
    showParen (d > 10) (showString "NoSite " . showsPrec 11 i)

-- | Positional equality of conflicts, polymorphic in the compared
--   block sorts (the existential of 'Clash' is independent on each
--   side, so the comparison goes through 'samePos' / 'eqBlock').
instance Eq (Conflict g) where
  Clash i a b == Clash j c d = samePos i j && eqBlock a c && eqBlock b d
  NoSite i    == NoSite j    = samePos i j
  _           == _           = False

-- | Two edits conflict when they target the same variable with
--   different blocks; identical edits are one edit, not a conflict.
conflict :: Edit g s -> Edit g s -> Maybe (Conflict g)
conflict (Edit i a) (Edit j b)
  | samePos i j, a /= b = Just (Clash i a b)
  | otherwise           = Nothing

--------------------------------------------------------------------
-- Structural patch focus
--------------------------------------------------------------------

-- | Sort-polymorphic block equality: 'Clash' and 'Edit' carry their
--   block sort existentially, so two blocks compare positionally
--   ('samePos' on variables, 'eqRep' on the lambda's sort witnesses).
eqBlock :: Rm g1 t1 -> Rm g2 t2 -> Bool
eqBlock RUnit        RUnit        = True
eqBlock (RVar i)     (RVar j)     = samePos i j
eqBlock (RLam r1 b1) (RLam r2 b2) = eqRep r1 r2 && eqBlock b1 b2
eqBlock (RApp f1 x1) (RApp f2 x2) = eqBlock f1 f2 && eqBlock x1 x2
eqBlock _            _            = False

-- | A structural delta: what the local replacement changed (the edit)
--   plus what the term became (the global result).  The residual — the
--   unchanged remainder — is implicit in the result term.  The stored
--   term is provenance (rebuilt, not the identity of the delta), and
--   the constructor is unchecked.
data Delta (g :: [Ty]) (t :: Ty) where
  Delta :: Edit g s -> Rm g t -> Delta g t

-- | 'Delta' takes two precedence 11 arguments.
instance Show (Delta g t) where
  showsPrec d (Delta e t') =
    showParen (d > 10)
      (showString "Delta " . showsPrec 11 e . showChar ' ' . showsPrec 11 t')

-- | Positional equality of deltas: the edit's sort is existentially
--   quantified on each side, so the edits compare via the conflicts'
--   positional discipline ('samePos' / 'eqBlock' / 'eqRep'); the two
--   result terms share the instance's sort and compare structurally.
instance Eq (Delta g t) where
  Delta e1 r1 == Delta e2 r2 = eqEdit e1 e2 && r1 == r2

-- | Sort-polymorphic edit equality (see 'eqBlock').
eqEdit :: Edit g1 s1 -> Edit g2 s2 -> Bool
eqEdit (Edit i a) (Edit j b) = samePos i j && eqBlock a b

-- | Apply a local replacement as a structural edit: when the edit's
--   variable still occurs, the substitution becomes a global delta; the
--   zero-candidate case (the variable no longer occurs — nothing to
--   replace) is the conflict.  The 'Either' is the patch layer's
--   failure channel: every downstream consumer takes the conflict
--   branch explicitly rather than silently dropping the edit.
patchFocus :: Edit g s -> Rm g t -> Either (Conflict g) (Delta g t)
patchFocus e@(Edit i _) t
  | survives e t = Right (Delta e (applyEdit e t))
  | otherwise    = Left (NoSite i)

-- | Number of occurrences of a variable in a term: positional, with
--   the queried position deepening by one under each binder (mirroring
--   'occursAt''s under-binder clause).
countOccurrences :: Fin g s -> Rm g t -> Int
countOccurrences _ RUnit      = 0
countOccurrences i (RVar j)   = if samePos i j then 1 else 0
countOccurrences i (RLam _ b) = countOccurrences (FS i) b
countOccurrences i (RApp f x) = countOccurrences i f + countOccurrences i x

-- | Reindex a delta along a refactor path: the edit transports
--   editwise ('reindexEdit') and the result term transports with the
--   same embedding ('weakenRm', polymorphic in the term sort).
reindexDelta :: RCtx g h u v -> Delta g t -> Delta h t
reindexDelta k (Delta e t) = Delta (reindexEdit k e) (weakenRm k t)

-- | Apply a delta's edit to another term: the evidence travels.  The
--   target term decides again whether the variable occurs — the same
--   zero-candidate conflict can arise at the new site.
deltaOn :: Delta g t -> Rm g t' -> Either (Conflict g) (Delta g t')
deltaOn (Delta e _) = patchFocus e

--------------------------------------------------------------------
-- Refactoring bridge
--------------------------------------------------------------------

-- | The edit a rename performs: occurrences of @i@ become @j@.  A
--   rename is a transposition (@i@ and @j@ swap roles), so this one-point
--   edit is exactly the operation only when @j@ does not occur in the
--   renamed term — otherwise the transposition side, which a one-point
--   edit cannot express, is structural and stays outside the edit layer.
renameEdit :: Fin g s -> Fin g s -> Edit g s
renameEdit i j = Edit i (RVar j)

-- | Rename through the patch focus: the global delta of the renaming
--   when the renamed variable occurs, the zero-candidate conflict
--   otherwise.  The delta's result term equals 'rename' @i j@ exactly
--   when the renamed variable @i@ occurs in the term and the new name
--   @j@ is fresh (does not occur in the renamed term): with @j@ fresh
--   the one-point edit is the transposition, while without an
--   occurrence of @i@ there is no site at all — the result is the
--   conflict, although 'rename' would still rewrite the term.  (The
--   edit-layer transposition is witnessed by @prop_dl_rename_swap@.)
--
--   >>> :set -XDataKinds -XTypeOperators
--   >>> import Focal.Redex
--   >>> import Focal.Syntax
--   >>> renamePatchFocus (FZ :: Fin '[U, U] U) (FS FZ) (RVar FZ :: Rm '[U, U] U)
--   Right (Delta (Edit FZ (RVar (FS FZ))) (RVar (FS FZ)))
--   >>> renamePatchFocus (FZ :: Fin '[U] U) FZ (RUnit :: Rm '[U] U)
--   Left (NoSite FZ)
renamePatchFocus :: Fin g s -> Fin g s -> Rm g t -> Either (Conflict g) (Delta g t)
renamePatchFocus i j = patchFocus (renameEdit i j)

-- | The substitution an inlining performs: the bound variable of the
--   redex body's context (the innermost position) replaced by the
--   argument, weakened past the binder's own slot.  Deleting the
--   application is structural and stays outside the edit.
inlineEdit :: Rm g s -> Edit (s ': g) s
inlineEdit a = Edit FZ (lift1 a)

-- | Apply an inline edit to a redex body: the argument (weakened)
--   replaces the bound variable; the binder's context slot is kept, so
--   the result still lives in the extended context with a vacuous head
--   slot.  Beta contraction proper — the slot dropped, as in
--   "Focal.Redex"'s @subst1@ — is one 'lift1' away and outside the edit
--   layer, whose application ('applyEdit', i.e. substitution) never
--   drops context.
--
--   >>> :set -XDataKinds -XTypeOperators
--   >>> import Focal.Redex
--   >>> import Focal.Syntax
--   >>> inlineApply (RUnit :: Rm '[U] U) (RVar FZ :: Rm '[U, U] U)
--   RUnit
--   >>> inlineEdit (RUnit :: Rm '[U] U)
--   Edit FZ RUnit
inlineApply :: Rm g s -> Rm (s ': g) t -> Rm (s ': g) t
inlineApply a body = applyEdit (inlineEdit a) body
