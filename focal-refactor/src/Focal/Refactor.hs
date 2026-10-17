{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

-- | The refactoring layer over the de Bruijn core.
--
--   A top-down one-hole stack ('RCtx') is the carrier for
--   position-addressed edits; 'TyCtx' + 'rmRepOf' recover sort facts at
--   any node; scope snapshots collect a subterm's free variables; the
--   flat renderer assigns every node a text 'Span' keyed by its path.
--   In a de Bruijn encoding alpha-renaming is positional (indices name
--   binders), so the load-bearing replacement operations are
--   capture-avoiding substitution ('substitute') and scope-preserving
--   transport ('weakenFin' / 'weakenRm').
--
--   >>> :set -XDataKinds -XTypeOperators
--   >>> import Focal.Redex
--   >>> import Focal.Syntax
--   >>> (plugRCtx (RAppL RUnit RHole) (RLam TyRepU (RVar FZ)) :: Rm '[] U)
--   RApp (RLam TyRepU (RVar FZ)) RUnit
--   >>> rmRepOf TxCNil (RApp (RLam TyRepU (RVar FZ)) RUnit)
--   TyRepU
--   >>> putStrLn (prettyRm (RApp (RLam TyRepU (RVar FZ)) RUnit :: Rm '[] U))
--   ((\. v0) unit)
--   >>> occurs (FZ :: Fin '[U, U] U) (RVar (FS FZ) :: Rm '[U, U] U)
--   False
--   >>> occurs (FS FZ :: Fin '[U, U] U) (RVar (FS FZ) :: Rm '[U, U] U)
--   True
--   >>> usedFins (RVar FZ :: Rm '[U] U)
--   [SomeFin FZ]
--   >>> usedFins (RLam TyRepU (RVar FZ) :: Rm '[] (U :-> U))
--   []
--   >>> renderSpans (RUnit :: Rm '[] U)
--   ("unit",[Spanned RHole (Span 0 4)])
--   >>> snapRep (snapshot TxCNil RHole (RLam TyRepU (RVar FZ)))
--   TyRepArr TyRepU TyRepU
--   >>> substitute (FZ :: Fin '[U, U] U) (RVar (FS FZ)) (RVar FZ :: Rm '[U, U] U)
--   RVar (FS FZ)
--   >>> substitute (FZ :: Fin '[U, U] U) (RVar (FS FZ)) (RLam TyRepU (RApp (RLam TyRepU (RVar FZ)) (RVar (FS FZ))) :: Rm '[U, U] (U :-> U))
--   RLam TyRepU (RApp (RLam TyRepU (RVar FZ)) (RVar (FS (FS FZ))))
--   >>> weakenRm (RLamC TyRepU RHole :: RCtx '[U] '[U, U] U (U :-> U)) (RVar FZ :: Rm '[U] U)
--   RVar (FS FZ)
module Focal.Refactor
  ( RCtx(..)
  , plugRCtx
  , TyCtx(..)
  , ctxAt
  , rmRepOf
  , SomeFin(..)
  , occurs
  , occursAt
  , usedFins
  , Span(..)
  , prettyRm
  , Spanned(..)
  , renderSpans
  , ScopeSnapshot(..)
  , snapshot
  , substitute
  , eqFinRefl
  , weakenFin
  , weakenRm
  , frameOccurs
  , rename
  , abstract
  , inlineAt
  , etaExpand
  ) where

import Data.Maybe (mapMaybe)
import Data.Type.Equality ((:~:)(Refl))

import Focal.Redex (Fin(..), Redex(..), Rm(..), contract, lift1)
import Focal.Syntax (Ty(..), TyRep(..))

-- | The refactor syntax stack: the path from the root to a hole.  @g@ is
--   the root context, @h@ the hole's ambient context (extended by every
--   binder crossed on the way down), @s@ the hole's sort, @t@ the root
--   sort.  Descending constructs the stack top-down; 'plugRCtx' rebuilds.
data RCtx (g :: [Ty]) (h :: [Ty]) (s :: Ty) (t :: Ty) where
  RHole :: RCtx g g s s
  RAppL :: Rm h v -> RCtx g h u t -> RCtx g h (v :-> u) t
  RAppR :: Rm h (v :-> u) -> RCtx g h u t -> RCtx g h v t
  RLamC :: TyRep v -> RCtx g h (v :-> u) t -> RCtx g (v ': h) u t

-- | Atoms print bare; composite constructors take precedence 11
--   arguments.
instance Show (RCtx g h s t) where
  showsPrec _ RHole        = showString "RHole"
  showsPrec d (RAppL x k)  =
    showParen (d > 10)
      (showString "RAppL " . showsPrec 11 x . showChar ' ' . showsPrec 11 k)
  showsPrec d (RAppR f k)  =
    showParen (d > 10)
      (showString "RAppR " . showsPrec 11 f . showChar ' ' . showsPrec 11 k)
  showsPrec d (RLamC rv k) =
    showParen (d > 10)
      (showString "RLamC " . showsPrec 11 rv . showChar ' ' . showsPrec 11 k)

-- | Fill the hole of the refactor stack: rebuilding the term at the
--   path's root from the replacement at the hole.
plugRCtx :: RCtx g h s t -> Rm h s -> Rm g t
plugRCtx RHole t        = t
plugRCtx (RAppL x k) f  = plugRCtx k (RApp f x)
plugRCtx (RAppR f k) x  = plugRCtx k (RApp f x)
plugRCtx (RLamC rv k) b = plugRCtx k (RLam rv b)

-- | Runtime witness of a de Bruijn context: the reps of every variable
--   in scope, outermost first.
data TyCtx (g :: [Ty]) where
  TxCNil  :: TyCtx '[]
  TxCCons :: TyRep v -> TyCtx g -> TyCtx (v ': g)

-- | 'TxCNil' prints bare; 'TxCCons' takes precedence 11 arguments.
instance Show (TyCtx g) where
  showsPrec _ TxCNil        = showString "TxCNil"
  showsPrec d (TxCCons r g) =
    showParen (d > 10)
      (showString "TxCCons " . showsPrec 11 r . showChar ' ' . showsPrec 11 g)

-- | The representative of a variable in the witnessed context.
ctxAt :: TyCtx g -> Fin g t -> TyRep t
ctxAt (TxCCons r _) FZ     = r
ctxAt (TxCCons _ g) (FS i) = ctxAt g i
ctxAt TxCNil i             = case i of {}

-- | Type facts: the sort representative of any subterm, total by
--   construction ('RVar' resolves through the context witness).
rmRepOf :: TyCtx g -> Rm g t -> TyRep t
rmRepOf _ RUnit      = TyRepU
rmRepOf g (RVar i)   = ctxAt g i
rmRepOf g (RLam r b) = TyRepArr r (rmRepOf (TxCCons r g) b)
rmRepOf g (RApp f _) = case rmRepOf g f of
  TyRepArr _ ru -> ru

-- | An existentially sorted variable occurrence.
data SomeFin (g :: [Ty]) = forall x. SomeFin (Fin g x)

-- | 'SomeFin' takes one precedence 11 argument.
instance Show (SomeFin g) where
  showsPrec d (SomeFin i) =
    showParen (d > 10) (showString "SomeFin " . showsPrec 11 i)

-- | Positional equality of variable occurrences: the same position in
--   the same context is the same variable.  Structural on the 'Fin'
--   spine, polymorphic in the compared contexts and sorts.
eqFinPos :: Fin g1 t1 -> Fin g2 t2 -> Bool
eqFinPos FZ     FZ     = True
eqFinPos (FS i) (FS j) = eqFinPos i j
eqFinPos _     _      = False

-- | Does the variable occur in the term?  The index is compared
--   positionally: under a binder the queried variable's distance grows.
occurs :: Fin (v ': g) t -> Rm (v ': g) u -> Bool
occurs _ RUnit              = False
occurs FZ (RVar FZ)         = True
occurs _ (RVar FZ)          = False
occurs FZ (RVar (FS _))     = False
occurs (FS i) (RVar (FS j)) = eqFinPos i j
occurs i (RLam _ b)         = occurs (FS i) b
occurs i (RApp f x)         = occurs i f || occurs i x

-- | Same-context variant of 'occurs': the variable and the term live in
--   one arbitrary context (no cons shape is assumed), so the comparison
--   is purely positional ('eqFinPos') and a binder deepens the index.
occursAt :: Fin g s -> Rm g t -> Bool
occursAt _ RUnit          = False
occursAt i (RVar j)       = eqFinPos i j
occursAt i (RLam _ b)     = occursAt (FS i) b
occursAt i (RApp f x)     = occursAt i f || occursAt i x

-- | Drop a binder's own variable: 'FZ' (the binder's variable) maps to
--   'Nothing', every deeper variable shifts down by one.
dropTop :: SomeFin (v ': g) -> Maybe (SomeFin g)
dropTop (SomeFin FZ)     = Nothing
dropTop (SomeFin (FS i)) = Just (SomeFin i)

-- | Every variable occurrence in the term (one entry per use, no
--   deduplication).  Under a binder the binder's own variable is
--   dropped: the result lists the variables of the AMBIENT context.
usedFins :: Rm g t -> [SomeFin g]
usedFins RUnit        = []
usedFins (RVar i)     = [SomeFin i]
usedFins (RLam _ b)   = mapMaybe dropTop (usedFins b)
usedFins (RApp f x)   = usedFins f ++ usedFins x

-- | A half-open text span in the flat rendering.
data Span = Span { spanFrom :: Int, spanTo :: Int }
  deriving Eq

-- | Hand-written so a span prints as @Span 0 4@, not as a record.
instance Show Span where
  showsPrec d (Span a b) =
    showParen (d > 10)
      (showString "Span " . showsPrec 11 a . showChar ' ' . showsPrec 11 b)

-- | Flat layout rendering: @unit@, @v\<k\>@ (de Bruijn depth),
--   @(\. body)@, @(f x)@.
prettyRm :: Rm g t -> String
prettyRm RUnit      = "unit"
prettyRm (RVar i)   = varName i
prettyRm (RLam _ b) = "(\\. " ++ prettyRm b ++ ")"
prettyRm (RApp f x) = "(" ++ prettyRm f ++ " " ++ prettyRm x ++ ")"

-- | The rendered name of a variable: @v\<depth\>@.
varName :: Fin g t -> String
varName i = "v" ++ show (varDepth i)

-- | The de Bruijn depth of a variable in its context.
varDepth :: Fin g t -> Int
varDepth FZ     = 0
varDepth (FS i) = 1 + varDepth i

-- | A rendered node: its path from the root and its span in the
--   rendered text.
data Spanned (g :: [Ty]) (t :: Ty) = forall h s. Spanned (RCtx g h s t) Span

-- | 'Spanned' takes two precedence 11 arguments: the path and the span.
instance Show (Spanned g t) where
  showsPrec d (Spanned k sp) =
    showParen (d > 10)
      (showString "Spanned " . showsPrec 11 k . showChar ' ' . showsPrec 11 sp)

-- | Render the term and report every node's path and text span.
renderSpans :: forall g t. Rm g t -> (String, [Spanned g t])
renderSpans = go RHole
  where
    go :: forall h s. RCtx g h s t -> Rm h s -> (String, [Spanned g t])
    go k RUnit = ("unit", [Spanned k (Span 0 4)])
    go k (RVar i) =
      let str = varName i
      in  (str, [Spanned k (Span 0 (length str))])
    go k (RLam r b) =
      let (bs, xs) = go (RLamC r k) b
          whole    = "(\\. " ++ bs ++ ")"
      in  ( whole
          , Spanned k (Span 0 (length whole)) : xs )
    go k (RApp f x) =
      let (fs, xs)  = go (RAppL x k) f
          (xs', ys) = go (RAppR f k) x
          whole     = "(" ++ fs ++ " " ++ xs' ++ ")"
      in  ( whole
          , Spanned k (Span 0 (length whole)) : xs ++ ys )

-- | Scope snapshot: a focused subterm with its path, its free
--   variables, and its sort fact.
data ScopeSnapshot (g :: [Ty]) (h :: [Ty]) (s :: Ty) (t :: Ty) = ScopeSnapshot
  { snapPath :: RCtx g h s t
  , snapTerm :: Rm h s
  , snapUsed :: [SomeFin h]
  , snapRep  :: TyRep s
  }

-- | Flat one-line form for doctest stability.
instance Show (ScopeSnapshot g h s t) where
  showsPrec d (ScopeSnapshot p tm used rep) =
    showParen (d > 10)
      ( showString "ScopeSnapshot "
          . showsPrec 11 p . showChar ' '
          . showsPrec 11 tm . showChar ' '
          . showsPrec 11 used . showChar ' '
          . showsPrec 11 rep )

-- | Extend the root's context witness along the path to the hole.
pathCtx :: RCtx g h s t -> TyCtx g -> TyCtx h
pathCtx RHole gC        = gC
pathCtx (RAppL _ k) gC  = pathCtx k gC
pathCtx (RAppR _ k) gC  = pathCtx k gC
pathCtx (RLamC rv k) gC = TxCCons rv (pathCtx k gC)

snapshot :: TyCtx g -> RCtx g h s t -> Rm h s -> ScopeSnapshot g h s t
snapshot gC k tm = ScopeSnapshot k tm (usedFins tm) (rmRepOf (pathCtx k gC) tm)

--------------------------------------------------------------------
-- Binder-aware replacement
--------------------------------------------------------------------

-- | Sort-refining positional equality of variables in one context: two
--   variables at the same de Bruijn position name the same sort.
eqFinRefl :: Fin g s -> Fin g t -> Maybe (s :~: t)
eqFinRefl FZ     FZ     = Just Refl
eqFinRefl (FS i) (FS j) = eqFinRefl i j
eqFinRefl _       _      = Nothing

-- | Substitute every occurrence of a variable by a term.  Under each
--   binder the index deepens and the replacement weakens ('lift1'), so
--   no binder can capture the replacement's variables (capture
--   avoidance).
substitute :: Fin g s -> Rm g s -> Rm g t -> Rm g t
substitute _ _ RUnit      = RUnit
substitute i a (RVar j)   = case eqFinRefl i j of
  Just Refl -> a
  Nothing   -> RVar j
substitute i a (RLam r b) = RLam r (substitute (FS i) (lift1 a) b)
substitute i a (RApp f x) = RApp (substitute i a f) (substitute i a x)

-- | Transport a root variable along a refactor path: every binder
--   crossed deepens the index by one.
weakenFin :: RCtx g h s t -> Fin g s' -> Fin h s'
weakenFin RHole i        = i
weakenFin (RAppL _ k) i  = weakenFin k i
weakenFin (RAppR _ k) i  = weakenFin k i
weakenFin (RLamC _ k) i  = FS (weakenFin k i)

-- | Transport a root-context term along a refactor path.
weakenRm :: RCtx g h s t -> Rm g s' -> Rm h s'
weakenRm RHole u        = u
weakenRm (RAppL _ k) u  = weakenRm k u
weakenRm (RAppR _ k) u  = weakenRm k u
weakenRm (RLamC _ k) u  = lift1 (weakenRm k u)

-- | Does a hole-context variable occur in the path's frame terms (the
--   @Rm@s carried by 'RAppL'/'RAppR' frames)?  'RHole' has no frames;
--   a binder's own variable is not in the frames' scope.
frameOccurs :: RCtx g h s t -> Fin h s' -> Bool
frameOccurs RHole _            = False
frameOccurs (RAppL x k) i      = occursAt i x || frameOccurs k i
frameOccurs (RAppR f k) i      = occursAt i f || frameOccurs k i
frameOccurs (RLamC _ _) FZ     = False
frameOccurs (RLamC _ k) (FS i) = frameOccurs k i

--------------------------------------------------------------------
-- Basic refactoring operations
--------------------------------------------------------------------

-- | Alpha-rename by transposition: swap the roles of two variable
--   positions.  An involution — renaming twice with the same pair is
--   the identity, which the round-trip property witnesses.
--
--   In a de Bruijn encoding this IS alpha-renaming: indices name
--   binders, so moving an index is the whole operation.  The operation
--   is total on any pair of positions; a target position the term does
--   not otherwise use is simply a fresh name.
--
--   >>> rename (FS FZ :: Fin '[U, U] U) FZ (RApp (RLam TyRepU (RVar FZ)) (RVar (FS FZ)) :: Rm '[U, U] U)
--   RApp (RLam TyRepU (RVar FZ)) (RVar FZ)
--   >>> rename (FZ :: Fin '[U, U] U) (FS FZ) (rename (FZ :: Fin '[U, U] U) (FS FZ) (RApp (RLam TyRepU (RVar FZ)) (RVar (FS FZ)) :: Rm '[U, U] U))
--   RApp (RLam TyRepU (RVar FZ)) (RVar (FS FZ))
rename :: Fin g s -> Fin g s -> Rm g t -> Rm g t
rename _ _ RUnit      = RUnit
rename i j (RVar k)   = case eqFinRefl i k of
  Just Refl -> RVar j
  Nothing   -> case eqFinRefl j k of
    Just Refl -> RVar i
    Nothing   -> RVar k
rename i j (RLam r b) = RLam r (rename (FS i) (FS j) b)
rename i j (RApp f x) = RApp (rename i j f) (rename i j x)

-- | Abstract a variable into a lambda: occurrences of the variable
--   become the bound variable.  The dual of 'substitute' — composing
--   the two (apply the abstraction to a term of the variable's sort)
--   reproduces plain substitution, which the round-trip property
--   witnesses through 'inlineAt'.
--
--   >>> abstract TyRepU FZ (RVar FZ :: Rm '[U] U)
--   RLam TyRepU (RVar FZ)
abstract :: TyRep s -> Fin g s -> Rm g t -> Rm g (s :-> t)
abstract r i t = RLam r (substitute (FS i) (RVar FZ) (lift1 t))

-- | Contract the beta-redex at the root of an application whose
--   function is already a lambda.  'Nothing' when the term is not such
--   an application — there is no contraction site at the root — so the
--   operation stays total in its domain without any 'error' escape.
--
--   >>> inlineAt (RApp (RLam TyRepU (RVar FZ)) RUnit :: Rm '[] U)
--   Just RUnit
--   >>> inlineAt (RUnit :: Rm '[] U)
--   Nothing
--   >>> inlineAt (RLam TyRepU RUnit :: Rm '[] (U :-> U))
--   Nothing
inlineAt :: Rm g t -> Maybe (Rm g t)
inlineAt (RApp (RLam r b) x) = Just (contract (Beta r b x))
inlineAt _                   = Nothing

-- | Eta-expand a function term: wrap it in a lambda that immediately
--   applies it.  The grammar's case-analogue — the simply-typed lambda
--   calculus over 'U' has no sum or case constructs, so the only
--   constructor-splitting operation the grammar affords is this
--   lambda-introduction at a function-sorted term.  Always inlinable
--   back: the bound variable never occurs in the lifted term, so
--   @'inlineAt' ('RApp' ('etaExpand' r f) a)@ returns @'Just' ('RApp' f a)@.
--
--   >>> etaExpand TyRepU (RLam TyRepU (RVar FZ) :: Rm '[] (U :-> U))
--   RLam TyRepU (RApp (RLam TyRepU (RVar FZ)) (RVar FZ))
etaExpand :: TyRep s -> Rm g (s :-> t) -> Rm g (s :-> t)
etaExpand r f = RLam r (RApp (lift1 f) (RVar FZ))
