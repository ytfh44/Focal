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
--   conflict is the zero-candidate case: two candidate blocks for one
--   variable, with no evidence to prefer either ('Conflict' / 'conflict'
--   — equal blocks would be one edit, so a real clash carries both).
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
  ) where

import Focal.Redex (Fin(..), Rm(..))
import Focal.Refactor
  ( RCtx(..)
  , SomeFin(..)
  , occursAt
  , substitute
  , weakenFin
  , weakenRm
  )
import Focal.Syntax (Ty)

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

-- | Sequential composition of two edits at the same variable: the
--   second block is transformed by the first.  The composition law
--   (applying the composite equals applying first one then the other)
--   holds when the second block does not mention the variable.
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
--   is the no-conflict invariant).
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
--   one variable, no evidence to prefer either).
addEdit :: Edit g s -> Patch g -> Maybe (Patch g)
addEdit e@(Edit i _) p
  | patchDistinct i p = Just (PCons (SomeEdit e) p)
  | otherwise         = Nothing

-- | Apply a patch: edits apply head-first, each at its own variable.
applyPatch :: Patch g -> Rm g t -> Rm g t
applyPatch PNil                      = id
applyPatch (PCons (SomeEdit e) rest) = applyPatch rest . applyEdit e

-- | The variables a patch claims, in order.
claimed :: Patch g -> [SomeFin g]
claimed PNil                               = []
claimed (PCons (SomeEdit (Edit i _)) rest) = SomeFin i : claimed rest

-- | Which edits survive in a term: those whose variable still occurs at
--   the moment the edit applies (a patch's own edits can consume each
--   other's targets).
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

-- | The conflict: two candidate blocks for one variable.  Equal blocks
--   would be one edit, so the constructor carries both.
data Conflict (g :: [Ty]) where
  Clash :: Fin g s -> Rm g s -> Rm g s -> Conflict g

-- | 'Clash' takes three precedence 11 arguments.
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

-- | Two edits conflict when they target the same variable with
--   different blocks; identical edits are one edit, not a conflict.
conflict :: Edit g s -> Edit g s -> Maybe (Conflict g)
conflict (Edit i a) (Edit j b)
  | samePos i j, a /= b = Just (Clash i a b)
  | otherwise           = Nothing
