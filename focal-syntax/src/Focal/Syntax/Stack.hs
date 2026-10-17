{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeOperators #-}

-- | Sort-indexed one-hole contexts for the example language.
--
--   @Stack i j@ is a context with a hole of sort @i@ and a root of sort
--   @j@; 'plugStack' fills the hole (the sort check is carried by the
--   types, so a wrong-sort replacement does not type-check), and
--   'splitStack' finds the canonical (leftmost-outermost) occurrence of the
--   requested sort, returning the focus and the context around it.
--
--   >>> import Focal.Syntax
--   >>> plugStack (AppL Hole TUnit) exConst
--   TApp (TLam TyRepU TUnit) TUnit
--   >>> fmap fst (splitStack (TyRepArr TyRepU TyRepU) exApp)
--   Just (TLam TyRepU TUnit)
module Focal.Syntax.Stack
  ( Stack(..)
  , plugStack
  , tyEq
  , splitStack
  , stackO
  ) where

import Data.Type.Equality ((:~:)(Refl))

import Focal.Optional (FocusingO(..))
import Focal.Syntax

-- | A context with a hole of sort @i@ and a root of sort @j@.
--
--   'LamS' carries the binder's domain representative, which is required to
--   rebuild the lambda during 'plugStack'.
data Stack (i :: Ty) (j :: Ty) where
  Hole :: Stack t t
  LamS :: TyRep v -> Stack i u -> Stack i (v :-> u)
  AppL :: Stack i (v :-> u) -> Tm v -> Stack i u
  AppR :: Tm (v :-> u) -> Stack i v -> Stack i u

-- | Fill the hole: total, and sort-checked by construction.
plugStack :: Stack i j -> Tm i -> Tm j
plugStack Hole t        = t
plugStack (LamS rv s) t = TLam rv (plugStack s t)
plugStack (AppL s x) t  = TApp (plugStack s t) x
plugStack (AppR f s) t  = TApp f (plugStack s t)

-- | Decidable sort equality on representatives.
tyEq :: TyRep a -> TyRep b -> Maybe (a :~: b)
tyEq TyRepU TyRepU = Just Refl
tyEq (TyRepArr a b) (TyRepArr c d) = do
  Refl <- tyEq a c
  Refl <- tyEq b d
  pure Refl
tyEq _ _ = Nothing

-- | Find the leftmost-outermost occurrence of the requested sort: test the
--   node first, then descend — function position before argument position.
splitStack :: TyRep i -> Tm j -> Maybe (Tm i, Stack i j)
splitStack ri t =
  case tyEq ri (tyRepOf t) of
    Just Refl -> Just (t, Hole)
    Nothing -> case t of
      TUnit -> Nothing
      TLam rv b -> fmap (\(a, c) -> (a, LamS rv c)) (splitStack ri b)
      TApp f x -> case splitStack ri f of
        Just (a, c) -> Just (a, AppL c x)
        Nothing     -> fmap (\(a, c) -> (a, AppR f c)) (splitStack ri x)

-- | The sort-indexed optional-focus rung: decomposition finds the canonical
--   occurrence or reports absence (no failure channel needed).
stackO :: TyRep i -> FocusingO (Stack i j) (Tm j) (Tm j) (Tm i) (Tm i)
stackO ri = FocusingO { splitO = splitStack ri, plugO = plugStack }

-- | Structural equality of contexts, polymorphic in both compared sorts
--   (equal contexts imply equal sorts; 'Hole' is the identity context and
--   carries no sort information).
eqStack :: Stack i j -> Stack i' j' -> Bool
eqStack Hole Hole                     = True
eqStack (LamS r1 s1) (LamS r2 s2)     = eqRep r1 r2 && eqStack s1 s2
eqStack (AppL s1 x1) (AppL s2 x2)     = eqStack s1 s2 && eqTm x1 x2
eqStack (AppR f1 s1) (AppR f2 s2)     = eqTm f1 f2 && eqStack s1 s2
eqStack _ _                           = False

instance Eq (Stack i j) where
  (==) = eqStack

instance Show (Stack i j) where
  showsPrec _ Hole = showString "Hole"
  showsPrec d (LamS r s) =
    showParen (d > 10) (showString "LamS " . showsPrec 11 r . showChar ' ' . showsPrec 11 s)
  showsPrec d (AppL s x) =
    showParen (d > 10) (showString "AppL " . showsPrec 11 s . showChar ' ' . showsPrec 11 x)
  showsPrec d (AppR f s) =
    showParen (d > 10) (showString "AppR " . showsPrec 11 f . showChar ' ' . showsPrec 11 s)
