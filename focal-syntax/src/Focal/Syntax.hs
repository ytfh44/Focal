{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeOperators #-}

-- | Sort-indexed example syntax: a closed core language over unit and
--   function sorts, used as the reference language for the typed-syntax
--   rung of Focal.
--
--   Sorts ('Ty') form a data kind; terms ('Tm') are a GADT indexed by their
--   sort; 'TyRep' makes a sort recoverable from a term, and 'tyRepOf' is the
--   recovery function that the sort-indexed context machinery
--   ('Focal.Syntax.Stack') relies on.
--
--   >>> exApp
--   TApp (TLam TyRepU TUnit) TUnit
--   >>> tyRepOf exApp
--   TyRepU
module Focal.Syntax
  ( Ty(..)
  , TyRep(..)
  , Tm(..)
  , tyRepOf
  , eqRep
  , eqTm
  , exUnit
  , exConst
  , exApp
  , exChain
  ) where

infixr 4 :->

-- | Sorts of the example language: unit and functions.
data Ty = U | Ty :-> Ty
  deriving (Eq, Show)

-- | First-class sort witnesses.
data TyRep (t :: Ty) where
  TyRepU   :: TyRep U
  TyRepArr :: TyRep a -> TyRep b -> TyRep (a :-> b)

-- | Sort-polymorphic representative comparison (the compared sorts may
--   differ; equal representatives imply equal sorts).
eqRep :: TyRep a -> TyRep b -> Bool
eqRep TyRepU TyRepU                     = True
eqRep (TyRepArr a1 b1) (TyRepArr a2 b2) = eqRep a1 a2 && eqRep b1 b2
eqRep _ _                               = False

instance Eq (TyRep t) where
  (==) = eqRep

instance Show (TyRep t) where
  showsPrec _ TyRepU = showString "TyRepU"
  showsPrec d (TyRepArr a b) =
    showParen (d > 10) (showString "TyRepArr " . showsPrec 11 a . showChar ' ' . showsPrec 11 b)

-- | Well-sorted terms, indexed by their sort.
--
--   The binder carries its domain representative: without it, a term's sort
--   could not be recovered from the term, and no sort-directed search over
--   terms would be expressible.
data Tm (t :: Ty) where
  TUnit :: Tm U
  TLam  :: TyRep t -> Tm u -> Tm (t :-> u)
  TApp  :: Tm (t :-> u) -> Tm t -> Tm u

-- | Structural equality, sort-aware: two terms of any two sorts compare
--   equal only if they have the same sort and the same structure. Stock
--   deriving cannot produce this instance for 'TApp', whose function-sort is
--   not determined by the result sort; this recursion is well-typed because
--   it is polymorphic in both compared sorts.
eqTm :: Tm a -> Tm b -> Bool
eqTm TUnit TUnit               = True
eqTm (TLam r1 b1) (TLam r2 b2) = eqRep r1 r2 && eqTm b1 b2
eqTm (TApp f1 x1) (TApp f2 x2) = eqTm f1 f2 && eqTm x1 x2
eqTm _ _                       = False

instance Eq (Tm t) where
  (==) = eqTm

-- | Show with composite arguments parenthesized ('TApp' and 'TLam' take
--   precedence 11 arguments; atoms print bare).
instance Show (Tm t) where
  showsPrec _ TUnit = showString "TUnit"
  showsPrec d (TLam r b) =
    showParen (d > 10) (showString "TLam " . showsPrec 11 r . showChar ' ' . showsPrec 11 b)
  showsPrec d (TApp f x) =
    showParen (d > 10) (showString "TApp " . showsPrec 11 f . showChar ' ' . showsPrec 11 x)

-- | Recover the sort representative of a term.
tyRepOf :: Tm t -> TyRep t
tyRepOf TUnit       = TyRepU
tyRepOf (TLam rt b) = TyRepArr rt (tyRepOf b)
tyRepOf (TApp f _)  = case tyRepOf f of TyRepArr _ ru -> ru

-- | The unit value.
exUnit :: Tm U
exUnit = TUnit

-- | The constant unit function.
exConst :: Tm (U :-> U)
exConst = TLam TyRepU TUnit

-- | The constant unit function applied to unit.
exApp :: Tm U
exApp = TApp exConst TUnit

-- | A two-argument constant function applied to two units.
exChain :: Tm U
exChain = TApp (TApp (TLam TyRepU (TLam TyRepU TUnit)) TUnit) TUnit
