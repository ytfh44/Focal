{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyCase #-}
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
--   evaluation context, indexed by the sorts of its hole and of its root:
--   the function position of 'EAppR' holds a 'Value', so the call-by-value
--   invariant is carried by the type.  'contract' performs the beta
--   contraction by single-variable substitution, 'decompose' (with 'step'
--   on top of it) realizes the canonical leftmost-outermost decomposition,
--   as in 'Focal.Syntax.Stack', and 'plugEval' fills an evaluation context
--   ('Decomp' is 'decompose''s result).
--   'plugEval' and 'contract' carry no strategy: the law-bearing
--   direction is the context fill @plug (E, r) = t@, and a plug that
--   contracted would break **L-GP**.
--
--   >>> :set -XDataKinds -XTypeOperators
--   >>> import Focal.Syntax
--   >>> (RLam TyRepU (RVar FZ) :: Rm '[] (U :-> U))
--   RLam TyRepU (RVar FZ)
--   >>> (contract (Beta TyRepU (RVar FZ) RUnit) :: Rm '[] U)
--   RUnit
--   >>> (subst1 RUnit (RLam TyRepU (RVar (FS FZ))) :: Rm '[] (U :-> U))
--   RLam TyRepU RUnit
--   >>> (decompose (RApp (RLam TyRepU (RVar FZ)) RUnit) :: Decomp '[] U)
--   IsRedex (Beta TyRepU (RVar FZ) RUnit) EHole
--   >>> step (RApp (RLam TyRepU (RVar FZ)) RUnit)
--   Just RUnit
--   >>> (plugEval (EAppL EHole RUnit) (RLam TyRepU (RVar FZ)) :: Rm '[] U)
--   RApp (RLam TyRepU (RVar FZ)) RUnit
module Focal.Redex
  ( Rm(..)
  , Fin(..)
  , Value(..)
  , valueTerm
  , Redex(..)
  , redexTerm
  , EvalCtx(..)
  , Decomp(..)
  , contract
  , decompose
  , plugEval
  , step
  , redexF
  , lift1
  , subst1
  ) where

import Focal.Optional (FocusingO(..))
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

-- | Call-by-value evaluation contexts: a hole of sort @s@ inside a term
--   of sort @t@.
--
--   'EHole' is the empty context (hole and root coincide); 'EAppL' and
--   'EAppR' descend into the function and the argument position of an
--   application.  'EAppR' holds a 'Value' in its function position: an
--   argument is evaluated only once the function position is a value, so
--   the call-by-value invariant is carried by the type.  The hole sort
--   must be an index, not a reconstruction: 'plugEval' descends into a
--   sub-context whose hole sort is the same while its root sort changes.
data EvalCtx (g :: [Ty]) (s :: Ty) (t :: Ty) where
  EHole :: EvalCtx g t t
  EAppL :: EvalCtx g s (t :-> u) -> Rm g t -> EvalCtx g s u
  EAppR :: Value g (t :-> u) -> EvalCtx g s t -> EvalCtx g s u

-- | The result of the canonical decomposition: either the term is a
--   value, or it is the redex found by 'decompose' together with the
--   evaluation context around it.
--
--   The redex sort is existentially quantified: the canonical
--   leftmost-outermost redex need not have the sort of the whole term
--   (an application whose function position is a redex -- @((\x.\y.y)
--   unit) unit@ -- contracts at the function's sort, not at the sort of
--   the application).
data Decomp (g :: [Ty]) (t :: Ty) where
  IsValue :: Value g t -> Decomp g t
  IsRedex :: Redex g s -> EvalCtx g s t -> Decomp g t

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

-- | Canonical call-by-value decomposition of a closed term: either the term
--   is a value, or the leftmost-outermost redex together with the
--   evaluation context around it.  Closedness ('[]) supplies the
--   empty-index case for 'RVar'; this canonical default is the
--   leftmost-outermost strategy, which 'plugEval' does not carry.
decompose :: Rm '[] t -> Decomp '[] t
decompose RUnit      = IsValue VUnit
decompose (RVar i)   = case i of {}
decompose (RLam r b) = IsValue (VLam r b)
decompose (RApp f x) =
  case decompose f of
    IsValue vf ->
      case vf of
        VLam r b ->
          case decompose x of
            IsValue vx    -> IsRedex (Beta r b (valueTerm vx)) EHole
            IsRedex rx ex -> IsRedex rx (EAppR (VLam r b) ex)
    IsRedex rf ef -> IsRedex rf (EAppL ef x)

-- | Fill the hole of an evaluation context (the law-bearing direction:
--   plugging a term back at its split position rebuilds the term).
plugEval :: EvalCtx g s t -> Rm g s -> Rm g t
plugEval EHole t       = t
plugEval (EAppL e x) t = RApp (plugEval e t) x
plugEval (EAppR v e) t = RApp (valueTerm v) (plugEval e t)

-- | One canonical call-by-value step: decompose, then contract and plug.
--   'Nothing' when the term is already a value.
step :: Rm '[] t -> Maybe (Rm '[] t)
step t =
  case decompose t of
    IsValue _     -> Nothing
    IsRedex r e   -> Just (plugEval e (contract r))

-- | The redex focus as an instance of the optional rung: a hit is a term
--   that is itself a call-by-value redex (a lambda applied to a value),
--   which is the case 'FocusingO' can express -- its focus sort is
--   fixed, while 'decompose' reports the redex sort existentially and so
--   also reaches redexes below the root.  On the hit domain this
--   satisfies L-GP in the plug-after-decompose direction:
--   @plugO redexF e r = plugEval e (redexTerm r)@, and a miss -- a
--   value, or a term whose canonical redex lies deeper -- passes
--   through unchanged.
redexF :: FocusingO (EvalCtx '[] t t) (Rm '[] t) (Rm '[] t) (Redex '[] t) (Redex '[] t)
redexF = FocusingO
  { splitO = \t ->
      case t of
        RApp (RLam r b) a ->
          case decompose a of
            IsValue va    -> Just (Beta r b (valueTerm va), EHole)
            IsRedex _ _   -> Nothing
        _ -> Nothing
  , plugO = \e r -> plugEval e (redexTerm r)
  }

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
eqEvalCtx :: EvalCtx g1 s1 t1 -> EvalCtx g2 s2 t2 -> Bool
eqEvalCtx EHole         EHole         = True
eqEvalCtx (EAppL e1 x1) (EAppL e2 x2) = eqEvalCtx e1 e2 && eqRm x1 x2
eqEvalCtx (EAppR v1 e1) (EAppR v2 e2) = eqValue v1 v2 && eqEvalCtx e1 e2
eqEvalCtx _ _                         = False

instance Eq (EvalCtx g s t) where
  (==) = eqEvalCtx

-- | Atoms print bare; 'EAppL' and 'EAppR' take precedence 11 arguments.
instance Show (EvalCtx g s t) where
  showsPrec _ EHole       = showString "EHole"
  showsPrec d (EAppL e x) =
    showParen (d > 10) (showString "EAppL " . showsPrec 11 e . showChar ' ' . showsPrec 11 x)
  showsPrec d (EAppR v e) =
    showParen (d > 10) (showString "EAppR " . showsPrec 11 v . showChar ' ' . showsPrec 11 e)

-- | Structural equality of decompositions: the redex sort is existentially
--   quantified on both sides, so the comparison goes through the
--   sort-polymorphic 'eqRedex' and 'eqEvalCtx'.
eqDecomp :: Decomp g1 t1 -> Decomp g2 t2 -> Bool
eqDecomp (IsValue v1) (IsValue v2)       = eqValue v1 v2
eqDecomp (IsRedex r1 e1) (IsRedex r2 e2) = eqRedex r1 r2 && eqEvalCtx e1 e2
eqDecomp _ _                             = False

instance Eq (Decomp g t) where
  (==) = eqDecomp

-- | 'IsValue' and 'IsRedex' take precedence 11 arguments.
instance Show (Decomp g t) where
  showsPrec d (IsValue v) =
    showParen (d > 10) (showString "IsValue " . showsPrec 11 v)
  showsPrec d (IsRedex r e) =
    showParen (d > 10) (showString "IsRedex " . showsPrec 11 r . showChar ' ' . showsPrec 11 e)
