{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeOperators #-}

-- | Call-by-value core of the example language over the sorts of
--   'Focal.Syntax'.
--
--   'Rm' is the term language, indexed by its de Bruijn context ('Fin' are
--   variables; 'RLam' extends the ambient context by its domain and keeps
--   the domain representative needed to rebuild the binder).  'Value' is
--   the value GADT, 'Redex' the beta-redex, and 'EvalCtx' a call-by-value
--   evaluation context: the function position of 'EAppR' holds a 'Value',
--   so the call-by-value invariant is carried by the type.  'contract'
--   performs the beta contraction by single-variable substitution; the
--   evaluation strategy lives outside this module (the canonical
--   decomposition policy is leftmost-outermost, as in
--   'Focal.Syntax.Stack').
--
--   >>> :set -XDataKinds -XTypeOperators
--   >>> import Focal.Syntax
--   >>> (RLam TyRepU (RVar FZ) :: Rm '[] (U :-> U))
--   RLam TyRepU (RVar FZ)
--   >>> (contract (Beta TyRepU (RVar FZ) RUnit) :: Rm '[] U)
--   RUnit
--   >>> (subst1 RUnit (RLam TyRepU (RVar (FS FZ))) :: Rm '[] (U :-> U))
--   RLam TyRepU RUnit
module Focal.Redex
  ( Rm(..)
  , Fin(..)
  , Value(..)
  , valueTerm
  , Redex(..)
  , redexTerm
  , EvalCtx(..)
  , contract
  , lift1
  , subst1
  ) where

import Focal.Syntax (Ty(..), TyRep(..), eqRep)

-- | De Bruijn variables: 'FZ' is the innermost variable in scope, 'FS'
--   walks outward.
data Fin (g :: [Ty]) (t :: Ty) where
  FZ :: Fin (t ': g) t
  FS :: Fin g t -> Fin (s ': g) t

-- | Terms indexed by their de Bruijn context.
--
--   'RLam' extends the ambient context by its domain; it carries the
--   domain representative, which rebuilding the binder during substitution
--   requires.
data Rm (g :: [Ty]) (t :: Ty) where
  RUnit :: Rm g U
  RVar  :: Fin g t -> Rm g t
  RLam  :: TyRep t -> Rm (t ': g) u -> Rm g (t :-> u)
  RApp  :: Rm g (t :-> u) -> Rm g t -> Rm g u

-- | Values: the terms that do not contract.
data Value (g :: [Ty]) (t :: Ty) where
  VUnit :: Value g U
  VLam  :: TyRep t -> Rm (t ': g) u -> Value g (t :-> u)

-- | Embed a value as a term.
valueTerm :: Value g t -> Rm g t
valueTerm VUnit     = RUnit
valueTerm (VLam r b) = RLam r b

-- | The beta-redex: a lambda applied to an argument.
data Redex (g :: [Ty]) (t :: Ty) where
  Beta :: TyRep t -> Rm (t ': g) u -> Rm g t -> Redex g u

-- | The redex as a term (the surrounding evaluation context is supplied
--   separately).
redexTerm :: Redex g t -> Rm g t
redexTerm (Beta r b a) = RApp (RLam r b) a

-- | Call-by-value evaluation contexts, with the hole at the redex position.
--
--   'EAppR' holds a 'Value' in its function position: an argument is
--   evaluated only once the function position is a value, so the
--   call-by-value invariant is carried by the type.
data EvalCtx (g :: [Ty]) (t :: Ty) where
  EHole :: EvalCtx g t
  EAppL :: EvalCtx g (t :-> u) -> Rm g t -> EvalCtx g u
  EAppR :: Value g (t :-> u) -> EvalCtx g t -> EvalCtx g u

-- | Weaken a term: insert a fresh variable of sort @s@ at the front of the
--   context, shifting every variable already in scope up by one.
--
--   The structural under-binder equation @lift1 (RLam r b) = RLam r
--   (lift1 b)@ does not type-check: the insertion point has to move past
--   the binder's own domain, so it is tracked by a renaming map
--   (@renRm@/@liftRename@).  The raw insertion is the renaming 'FS'.
lift1 :: Rm g t -> Rm (s ': g) t
lift1 RUnit      = RUnit
lift1 (RVar i)   = RVar (FS i)
lift1 (RLam r b) = RLam r (renRm (liftRename FS) b)
lift1 (RApp f x) = RApp (lift1 f) (lift1 x)

-- | Substitute the innermost variable ('FZ' of the ambient context) by a
--   term, recursively under binders.
--
--   The replacement is weakened ('lift1') as it is pushed under binders:
--   the substituted variable sits one binder deeper in the body.  The
--   structural under-binder equation fails to type-check for the same
--   reason as 'lift1', so that case runs the substitution map
--   (@substRm@/@liftSubst@) built from the replacement (@topSubst@).
subst1 :: Rm g s -> Rm (s ': g) t -> Rm g t
subst1 a (RVar FZ)     = a
subst1 _ (RVar (FS i)) = RVar i
subst1 a (RLam r b)    = RLam r (substRm (liftSubst (topSubst a)) b)
subst1 a (RApp f x)    = RApp (subst1 a f) (subst1 a x)
subst1 _ RUnit         = RUnit

-- | Beta contraction: substitute the argument for the variable bound by
--   the lambda.  The evaluation strategy is not part of this function.
contract :: Redex g t -> Rm g t
contract (Beta _ b a) = subst1 a b

-- | Apply a variable renaming to a term.
renRm :: (forall t. Fin g t -> Fin g' t) -> Rm g a -> Rm g' a
renRm _ RUnit      = RUnit
renRm f (RVar i)   = RVar (f i)
renRm f (RLam r b) = RLam r (renRm (liftRename f) b)
renRm f (RApp m n) = RApp (renRm f m) (renRm f n)

-- | Extend a renaming under a binder: the binder's own variable is left
--   alone, the variables behind it are renamed by the supplied map.
liftRename
  :: (forall t. Fin g t -> Fin g' t)
  -> (forall t. Fin (v ': g) t -> Fin (v ': g') t)
liftRename _ FZ     = FZ
liftRename f (FS i) = FS (f i)

-- | Apply a term substitution to a term.
substRm :: (forall t. Fin g t -> Rm g' t) -> Rm g a -> Rm g' a
substRm _ RUnit      = RUnit
substRm s (RVar i)   = s i
substRm s (RLam r b) = RLam r (substRm (liftSubst s) b)
substRm s (RApp m n) = RApp (substRm s m) (substRm s n)

-- | Extend a substitution under a binder: the binder's own variable maps
--   to itself, and the images of the other variables are weakened past
--   the binder.
liftSubst
  :: (forall t. Fin g t -> Rm g' t)
  -> (forall t. Fin (v ': g) t -> Rm (v ': g') t)
liftSubst _ FZ     = RVar FZ
liftSubst s (FS i) = lift1 (s i)

-- | The substitution that replaces the first variable by a term and keeps
--   the remaining variables.
topSubst :: Rm g s -> (forall t. Fin (s ': g) t -> Rm g t)
topSubst a FZ     = a
topSubst _ (FS i) = RVar i

-- | Structural equality of variables, polymorphic in both compared
--   contexts and sorts.
eqFin :: Fin g1 t1 -> Fin g2 t2 -> Bool
eqFin FZ FZ         = True
eqFin (FS i) (FS j) = eqFin i j
eqFin _ _           = False

instance Eq (Fin g t) where
  (==) = eqFin

-- | Atoms print bare; 'FS' takes a precedence 11 argument.
instance Show (Fin g t) where
  showsPrec _ FZ     = showString "FZ"
  showsPrec d (FS i) = showParen (d > 10) (showString "FS " . showsPrec 11 i)

-- | Structural equality of terms, polymorphic in both compared contexts
--   and sorts.
eqRm :: Rm g1 t1 -> Rm g2 t2 -> Bool
eqRm RUnit        RUnit        = True
eqRm (RVar i)     (RVar j)     = eqFin i j
eqRm (RLam r1 b1) (RLam r2 b2) = eqRep r1 r2 && eqRm b1 b2
eqRm (RApp f1 x1) (RApp f2 x2) = eqRm f1 f2 && eqRm x1 x2
eqRm _ _                       = False

instance Eq (Rm g t) where
  (==) = eqRm

-- | Show with composite arguments parenthesized ('RLam' and 'RApp' take
--   precedence 11 arguments; atoms print bare).
instance Show (Rm g t) where
  showsPrec _ RUnit      = showString "RUnit"
  showsPrec d (RVar i)   = showParen (d > 10) (showString "RVar " . showsPrec 11 i)
  showsPrec d (RLam r b) =
    showParen (d > 10) (showString "RLam " . showsPrec 11 r . showChar ' ' . showsPrec 11 b)
  showsPrec d (RApp f x) =
    showParen (d > 10) (showString "RApp " . showsPrec 11 f . showChar ' ' . showsPrec 11 x)

-- | Structural equality of values, polymorphic in both compared contexts
--   and sorts.
eqValue :: Value g1 t1 -> Value g2 t2 -> Bool
eqValue VUnit        VUnit        = True
eqValue (VLam r1 b1) (VLam r2 b2) = eqRep r1 r2 && eqRm b1 b2
eqValue _ _                       = False

instance Eq (Value g t) where
  (==) = eqValue

-- | Atoms print bare; 'VLam' takes precedence 11 arguments.
instance Show (Value g t) where
  showsPrec _ VUnit      = showString "VUnit"
  showsPrec d (VLam r b) =
    showParen (d > 10) (showString "VLam " . showsPrec 11 r . showChar ' ' . showsPrec 11 b)

-- | Structural equality of redexes, polymorphic in both compared contexts
--   and sorts.
eqRedex :: Redex g1 t1 -> Redex g2 t2 -> Bool
eqRedex (Beta r1 b1 a1) (Beta r2 b2 a2) = eqRep r1 r2 && eqRm b1 b2 && eqRm a1 a2

instance Eq (Redex g t) where
  (==) = eqRedex

-- | 'Beta' takes three precedence 11 arguments.
instance Show (Redex g t) where
  showsPrec d (Beta r b a) =
    showParen (d > 10) $
      showString "Beta " . showsPrec 11 r . showChar ' ' . showsPrec 11 b . showChar ' ' . showsPrec 11 a

-- | Structural equality of evaluation contexts, polymorphic in both
--   compared contexts and sorts.
eqEvalCtx :: EvalCtx g1 t1 -> EvalCtx g2 t2 -> Bool
eqEvalCtx EHole         EHole         = True
eqEvalCtx (EAppL e1 x1) (EAppL e2 x2) = eqEvalCtx e1 e2 && eqRm x1 x2
eqEvalCtx (EAppR v1 e1) (EAppR v2 e2) = eqValue v1 v2 && eqEvalCtx e1 e2
eqEvalCtx _ _                         = False

instance Eq (EvalCtx g t) where
  (==) = eqEvalCtx

-- | Atoms print bare; 'EAppL' and 'EAppR' take precedence 11 arguments.
instance Show (EvalCtx g t) where
  showsPrec _ EHole       = showString "EHole"
  showsPrec d (EAppL e x) =
    showParen (d > 10) (showString "EAppL " . showsPrec 11 e . showChar ' ' . showsPrec 11 x)
  showsPrec d (EAppR v e) =
    showParen (d > 10) (showString "EAppR " . showsPrec 11 v . showChar ' ' . showsPrec 11 e)
