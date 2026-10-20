{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeOperators #-}

module Main (main) where

import Test.QuickCheck (Gen, Property, conjoin, forAll, oneof, property, sized)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.QuickCheck (testProperty, (===))

import Focal.Optional (FocusingO(..))
import Focal.Syntax (Ty(..), TyRep(..))
import Focal.Redex
  ( CBVRedex(..), Decomp(..), EvalCtx(..), Fin(..), Redex(..), Rm(..), Value(..)
  , decompose, plugEval, redexF, redexTerm, step, subst1, valueTerm
  )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "focal-redex — canonical decomposition"
  [ testGroup "Concrete examples (regression)"
      [ testProperty "decompose tHead = redex at the root" prop_rd_decompose_head
      , testProperty "decompose tArg = head redex under EAppR" prop_rd_decompose_arg
      , testProperty "decompose tFun = inner redex under EAppL" prop_rd_decompose_fun
      , testProperty "plug-after-decompose: head" prop_rd_plug_head
      , testProperty "plug-after-decompose: argument slot" prop_rd_plug_arg
      , testProperty "plug-after-decompose: function slot" prop_rd_plug_fun
      , testProperty "step: head redex contracts to RUnit" prop_rd_step_head
      , testProperty "step: redex in argument slot" prop_rd_step_arg
      , testProperty "step: redex in function slot" prop_rd_step_fun
      , testProperty "step: value does not step" prop_rd_step_value
      , testProperty "step chains: tArg -> tHead -> RUnit" prop_rd_step_chain
      , testProperty "redexF split finds the head CBV redex" prop_rd_redexF_split
      , testProperty "redexF miss on a lambda" prop_rd_redexF_miss
      ]
  , testGroup "Redex laws"
      [ testProperty "plug-after-decompose over generated closed terms" prop_rd_plug
      , testProperty "redexF: plug rebuilds the term from the split's focus"
          prop_rd_redexF_plug
      , testProperty "step is defined exactly off the values" prop_rd_progress
      , testProperty "normalization reaches a value" prop_rd_norm
      , testProperty "head step = beta substitution" prop_rd_head
      , testProperty "redexF: re-split after plug recovers the CBV redex" prop_rd_redexF_pg
      , testProperty "redexF: the put-put equation holds over the plug domain"
          prop_rd_redexF_pp
      ]
  ]

-- | @(\\x.x) unit@
tHead :: Rm '[] U
tHead = RApp (RLam TyRepU (RVar FZ)) RUnit

-- | @(\\x.x) ((\\y.y) unit)@ — the redex sits in the argument slot.
tArg :: Rm '[] U
tArg = RApp (RLam TyRepU (RVar FZ)) (RApp (RLam TyRepU (RVar FZ)) RUnit)

-- | @((\\x.\\y.y) unit) unit@ — the redex sits in the function slot.
tFun :: Rm '[] U
tFun = RApp (RApp (RLam TyRepU (RLam TyRepU (RVar FZ))) RUnit) RUnit

prop_rd_decompose_head :: Property
prop_rd_decompose_head =
  decompose tHead === IsRedex (Beta TyRepU (RVar FZ) RUnit) EHole

prop_rd_decompose_arg :: Property
prop_rd_decompose_arg =
  decompose tArg === IsRedex (Beta TyRepU (RVar FZ) RUnit) (EAppR (VLam TyRepU (RVar FZ)) EHole)

prop_rd_decompose_fun :: Property
prop_rd_decompose_fun =
  decompose tFun === IsRedex (Beta TyRepU (RLam TyRepU (RVar FZ)) RUnit) (EAppL EHole RUnit)

prop_rd_plug_head :: Property
prop_rd_plug_head = case decompose tHead of
  IsValue _       -> property False
  IsRedex r e     -> plugEval e (redexTerm r) === tHead

prop_rd_plug_arg :: Property
prop_rd_plug_arg = case decompose tArg of
  IsValue _       -> property False
  IsRedex r e     -> plugEval e (redexTerm r) === tArg

prop_rd_plug_fun :: Property
prop_rd_plug_fun = case decompose tFun of
  IsValue _       -> property False
  IsRedex r e     -> plugEval e (redexTerm r) === tFun

prop_rd_step_head :: Property
prop_rd_step_head = step tHead === Just RUnit

prop_rd_step_arg :: Property
prop_rd_step_arg = step tArg === Just tHead

prop_rd_step_fun :: Property
prop_rd_step_fun = step tFun === Just tHead

prop_rd_step_value :: Property
prop_rd_step_value = step (RLam TyRepU (RVar FZ) :: Rm '[] (U :-> U)) === Nothing

prop_rd_step_chain :: Property
prop_rd_step_chain = (step tArg >>= step) === Just RUnit

prop_rd_redexF_split :: Property
prop_rd_redexF_split = splitO redexF tHead === Just (CBVBeta TyRepU (RVar FZ) VUnit, ())

-- | L-GP for the redex rung: on the hit domain, plugging the focus
--   back through the split's own residual rebuilds the term.
--
--   The witness covers the whole plug domain rather than one
--   hand-picked term: the split ranges over generated closed terms at
--   both focus sorts, @U@ and @U :-> U@, so the arrow-sorted focus
--   ('CBVRedex' at @U :-> U@) is exercised as well.  A miss
--   contributes nothing -- there is no focus to plug back, so the
--   clause has no content there.
--
--   It can fail if the split reports a focus whose rebuild differs
--   from the term it came from -- a sort error in the focus, or a
--   redex body that the plug does not reproduce.
prop_rd_redexF_plug :: Property
prop_rd_redexF_plug = conjoin
  [ forAll genU  gpAt
  , forAll genArr gpAt
  ]
  where
    gpAt t = case splitO redexF t of
      Nothing     -> property True
      Just (r, c) -> plugO redexF c r === t

prop_rd_redexF_miss :: Property
prop_rd_redexF_miss =
  splitO redexF (RLam TyRepU (RVar FZ) :: Rm '[] (U :-> U)) === Nothing

-- | L-PG for the redex rung: the residual is the unit, so the premise
--   @c ∈ R(redexF)@ is vacuous and the law is total.
--
--   The re-hit clause is witnessed over the whole plug domain: the
--   split ranges over generated closed terms at both focus sorts,
--   @U@ and @U :-> U@, so the arrow-sorted focus is re-hit as well and
--   not only the unit-sorted one.  A miss contributes nothing -- there
--   is no plug to re-split.
--
--   It can fail if the plug of a focus is not a term the split
--   recognises: the re-split would then miss, or report a different
--   focus than the one plugged.
prop_rd_redexF_pg :: Property
prop_rd_redexF_pg = conjoin
  [ forAll genU  pgAt
  , forAll genArr pgAt
  ]
  where
    pgAt t = case splitO redexF t of
      Nothing      -> property True
      Just (r, ()) -> splitO redexF (plugO redexF () r) === Just (r, ())

-- | A fresh replacement for the L-PP plug: a call-by-value redex
--   whose body is the unit (the identity body @RVar FZ@ is the other
--   shape).
ppRepl :: CBVRedex '[] U
ppRepl = CBVBeta TyRepU RUnit VUnit

-- | L-PP for the redex rung: the put-put equation over the plug
--   domain.
--
--   The residual is the unit -- the split's own image -- so the
--   re-split residual @c'@ is the unit again and the equation
--   degenerates to @plugO redexF () b2 == plugO redexF () b2@: it is
--   satisfied by construction, not by the law's content.  What the
--   witness does pin is the re-split premise the equation rests on: a
--   plug of a fresh replacement is re-split to that replacement,
--   together with the unit residual.
prop_rd_redexF_pp :: Property
prop_rd_redexF_pp = forAll genU $ \t ->
  case splitO redexF t of
    Nothing     -> property True
    Just (r, c) ->
      case splitO redexF (plugO redexF c ppRepl) of
        Nothing       -> property False
        Just (r', c') -> conjoin
          [ r' === ppRepl
          , plugO redexF c' r === plugO redexF c r
          ]

--------------------------------------------------------------------
-- Generators — closed terms at two sorts, plus one- and two-variable
-- bodies under binders
--------------------------------------------------------------------

genU :: Gen (Rm '[] U)
genU = sized genUN

genUN :: Int -> Gen (Rm '[] U)
genUN 0 = pure RUnit
genUN n = oneof
  [ pure RUnit
  , RApp <$> genArrN (n `div` 2) <*> genUN (n `div` 2)
  ]

genArr :: Gen (Rm '[] (U :-> U))
genArr = sized genArrN

genArrN :: Int -> Gen (Rm '[] (U :-> U))
genArrN 0 = oneof
  [ pure (RLam TyRepU (RVar FZ))
  , pure (RLam TyRepU RUnit)
  ]
genArrN n = oneof
  [ pure (RLam TyRepU (RVar FZ))
  , RLam TyRepU <$> genBody1N (n `div` 2)
  , RApp <$> genArrArrN (n `div` 2) <*> genUN (n `div` 2)
  ]

genArrArrN :: Int -> Gen (Rm '[] (U :-> (U :-> U)))
genArrArrN n = oneof
  [ pure (RLam TyRepU (RLam TyRepU (RVar FZ)))
  , pure (RLam TyRepU (RLam TyRepU (RVar (FS FZ))))
  , pure (RLam TyRepU (RLam TyRepU RUnit))
  , RLam TyRepU <$> genArrBody1N (n `div` 2)
  ]

-- | Bodies under one binder: context @'[U]@.
genBody1N :: Int -> Gen (Rm '[U] U)
genBody1N n = oneof
  [ pure RUnit
  , pure (RVar FZ)
  , RApp <$> genArrBody1N (n `div` 2) <*> pure (RVar FZ)
  , RApp (RLam TyRepU (RVar FZ)) <$> genBody1N (n `div` 2)
  ]

-- | Function-sorted bodies over context @'[U]@.
genArrBody1N :: Int -> Gen (Rm '[U] (U :-> U))
genArrBody1N n = oneof
  [ pure (RLam TyRepU (RVar FZ))
  , pure (RLam TyRepU (RVar (FS FZ)))
  , RLam TyRepU <$> genBody2N (n `div` 2)
  ]

-- | Bodies under two binders: context @'[U, U]@.
genBody2N :: Int -> Gen (Rm '[U, U] U)
genBody2N _ = oneof
  [ pure RUnit
  , pure (RVar FZ)
  , pure (RVar (FS FZ))
  , RApp <$> pure (RLam TyRepU (RVar FZ)) <*> pure RUnit
  ]

-- | Bodies over context @'[U :-> U]@: the arrow-sorted variable applied,
--   with a binder under which the variable occurs (that binder is what
--   forces the replacement's weakening path during substitution).
genBodyArrDomN :: Int -> Gen (Rm '[U :-> U] U)
genBodyArrDomN 0 = pure RUnit
genBodyArrDomN n = oneof
  [ pure RUnit
  , RApp (RVar FZ) <$> genBodyArrDomN (n `div` 2)
  , RApp (RLam TyRepU (RApp (RVar (FS FZ)) (RVar FZ))) <$> genBodyArrDomN (n `div` 2)
  ]

--------------------------------------------------------------------
-- Laws — canonical decomposition
--------------------------------------------------------------------

-- | Plug-after-decompose: plugging the focus back through its context
--   rebuilds the term; on the value side the embedding rebuilds it too.
prop_rd_plug :: Property
prop_rd_plug = conjoin
  [ forAll genU plugAt
  , forAll genArr plugAt
  ]
  where
    plugAt t = case decompose t of
      IsValue v   -> valueTerm v === t
      IsRedex r e -> plugEval e (redexTerm r) === t

-- | Progress: 'step' is defined exactly off the values.
prop_rd_progress :: Property
prop_rd_progress = conjoin
  [ forAll genU progressAt
  , forAll genArr progressAt
  ]
  where
    progressAt t = stepIsNothing (step t) === isValueRm t

-- | Normalization: iterated steps reach a value (type-preserving).
prop_rd_norm :: Property
prop_rd_norm = conjoin
  [ forAll genU (\t -> isValueRm (nf t) === True)
  , forAll genArr (\t -> isValueRm (nf t) === True)
  ]

-- | The canonical head step is beta substitution, stated without
--   'decompose'/'plugEval'.  The first two legs apply the redex at the
--   root with a unit argument (the only closed value of sort @U@), so
--   substitution runs into @U@- and function-sorted bodies; the third
--   binds an arrow-sorted variable and substitutes a lambda value, the
--   only shape that weakens a replacement ('lift1') under a binder.
prop_rd_head :: Property
prop_rd_head = conjoin
  [ forAll (sized genBody1N) $ \b ->
      step (RApp (RLam TyRepU b) RUnit) === Just (subst1 RUnit b)
  , forAll (sized genArrBody1N) $ \b ->
      step (RApp (RLam TyRepU b) RUnit) === Just (subst1 RUnit b)
  , forAll ((,) <$> sized genBodyArrDomN <*> genRepl) $ \(bArr, repl) ->
      step (RApp (RLam (TyRepArr TyRepU TyRepU) bArr) repl) === Just (subst1 repl bArr)
  ]
  where
    genRepl :: Gen (Rm '[] (U :-> U))
    genRepl = oneof [pure (RLam TyRepU RUnit), pure (RLam TyRepU (RVar FZ))]

-- | The closed terms that do not contract ('RVar' cannot occur in a
--   closed term).
isValueRm :: Rm '[] t -> Bool
isValueRm RUnit      = True
isValueRm (RLam _ _) = True
isValueRm _          = False

stepIsNothing :: Maybe a -> Bool
stepIsNothing Nothing  = True
stepIsNothing (Just _) = False

-- | Iterated canonical step; the generated terms are strongly
--   normalizing, so the recursion terminates.
nf :: Rm '[] t -> Rm '[] t
nf t = case step t of
  Nothing  -> t
  Just t'  -> nf t'
