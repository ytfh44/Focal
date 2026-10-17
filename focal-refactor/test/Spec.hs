{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module Main (main) where

import Test.QuickCheck (Gen, Property, conjoin, forAll, oneof, property, sized, (==>))
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.QuickCheck (testProperty, (===))

import Focal.Syntax (Ty(..), TyRep(..))
import Focal.Redex (Fin(..), Rm(..))
import Focal.Refactor
  ( RCtx(..), abstract, etaExpand, frameOccurs, inlineAt, plugRCtx, rename, substitute
  , weakenFin, weakenRm
  )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "focal-refactor — binder-aware replacement"
  [ testGroup "Capture avoidance"
      [ testProperty "self-substitution is the identity" prop_rf_substitute_id
      , testProperty "occurrence and non-occurrence equations" prop_rf_substitute_hits
      , testProperty "no capture under a fresh binder" prop_rf_no_capture
      , testProperty "substitution commutes with the path" prop_rf_commute
      ]
  , testGroup "Refactoring operations"
      [ testProperty "rename is an involution" prop_rf_rename_involution
      , testProperty "abstract then apply is substitution (unit argument)"
          prop_rf_abstract_unit
      , testProperty "abstract then apply is substitution (variable argument)"
          prop_rf_abstract_var
      , testProperty "eta expansion inlines back" prop_rf_eta_roundtrip
      , testProperty "inlineAt contracts a root redex" prop_rf_inline_hits
      ]
  ]

prop_rf_substitute_id :: Property
prop_rf_substitute_id = conjoin
  [ forAll genBodyU1 (\t -> substitute (FZ :: Fin '[U] U) (RVar FZ) t === t)
  , forAll genArrU1 (\t -> substitute (FZ :: Fin '[U] U) (RVar FZ) t === t)
  ]

prop_rf_substitute_hits :: Property
prop_rf_substitute_hits = conjoin
  [ substitute (FZ :: Fin '[U, U] U) (RVar (FS FZ)) (RVar FZ :: Rm '[U, U] U) === RVar (FS FZ)
  , substitute (FZ :: Fin '[U, U] U) (RVar (FS FZ)) (RVar (FS FZ) :: Rm '[U, U] U) === RVar (FS FZ)
  ]

prop_rf_no_capture :: Property
prop_rf_no_capture = property $
  substitute (FZ :: Fin '[U, U] U) (RVar (FS FZ))
      (RLam TyRepU (RApp (RLam TyRepU (RVar FZ)) (RVar (FS FZ))) :: Rm '[U, U] (U :-> U))
    === RLam TyRepU (RApp (RLam TyRepU (RVar FZ)) (RVar (FS (FS FZ))))

prop_rf_commute :: Property
prop_rf_commute = conjoin
  [ forAll genBodyU1 (commuteAt (RHole :: RCtx '[U] '[U] U U))
  , forAll genArrU1 (commuteAt (RAppL RUnit RHole :: RCtx '[U] '[U] (U :-> U) U))
  , forAll genBodyU2 (commuteAt (RLamC TyRepU RHole :: RCtx '[U] '[U, U] U (U :-> U)))
  ]
  where
    commuteAt :: forall h s t. RCtx '[U] h s t -> Rm h s -> Property
    commuteAt k u =
      let i  = FZ :: Fin '[U] U
          a  = RApp (RLam TyRepU (RVar FZ)) (RVar FZ) :: Rm '[U] U
      in  not (frameOccurs k (weakenFin k i))
            ==> substitute i a (plugRCtx k u)
                  === plugRCtx k (substitute (weakenFin k i) (weakenRm k a) u)

--------------------------------------------------------------------
-- Refactoring operations
--------------------------------------------------------------------

-- 'rename' is a transposition of two variable positions, so applying it
-- twice restores every occurrence: an involution.  The context '[U, U]
-- supplies the two positions; 'genBodyU2' generates terms at that
-- context.
prop_rf_rename_involution :: Property
prop_rf_rename_involution = forAll genBodyU2 $ \t ->
  rename (FS FZ :: Fin '[U, U] U) FZ (rename (FZ :: Fin '[U, U] U) (FS FZ) t) === t

-- Applying 'abstract' at a variable and applying the abstraction to a
-- term of that variable's sort reproduces 'substitute' — the beta
-- round trip, with a real (unit) argument.
prop_rf_abstract_unit :: Property
prop_rf_abstract_unit = forAll genBodyU1 $ \x ->
  inlineAt (RApp (abstract TyRepU (FZ :: Fin '[U] U) x) (RUnit :: Rm '[U] U))
    === Just (substitute (FZ :: Fin '[U] U) (RUnit :: Rm '[U] U) x)

-- Same round trip with the variable itself as the argument: the
-- abstraction re-absorbs its own bound variable.
prop_rf_abstract_var :: Property
prop_rf_abstract_var = forAll genBodyU1 $ \x ->
  inlineAt (RApp (abstract TyRepU (FZ :: Fin '[U] U) x) (RVar FZ :: Rm '[U] U))
    === Just (substitute (FZ :: Fin '[U] U) (RVar FZ) x)

-- 'etaExpand' wraps a function in a lambda that immediately applies it;
-- the bound variable never occurs in the lifted function, so
-- contracting the application restores the original application of the
-- unexpanded function.
prop_rf_eta_roundtrip :: Property
prop_rf_eta_roundtrip = forAll genArrU1 $ \f ->
  inlineAt (RApp (etaExpand TyRepU f) (RUnit :: Rm '[U] U)) === Just (RApp f RUnit)

-- 'inlineAt' contracts exactly a root application of a lambda and
-- refuses every other shape (no error, a 'Nothing' witness instead).
prop_rf_inline_hits :: Property
prop_rf_inline_hits = conjoin
  [ inlineAt (RApp (RLam TyRepU (RVar FZ)) RUnit :: Rm '[] U) === Just RUnit
  , inlineAt (RUnit :: Rm '[] U) === Nothing
  , inlineAt (RLam TyRepU RUnit :: Rm '[] (U :-> U)) === Nothing
  ]

--------------------------------------------------------------------
-- Generators
--------------------------------------------------------------------

-- Terms over context '[U] at sort U.
genBodyU1 :: Gen (Rm '[U] U)
genBodyU1 = sized genBodyU1N
genBodyU1N :: Int -> Gen (Rm '[U] U)
genBodyU1N n = oneof
  [ pure RUnit
  , pure (RVar FZ)
  , RApp (RLam TyRepU (RVar FZ)) <$> genBodyU1N (n `div` 2)
  , RApp <$> genArrBodyU1 (n `div` 2) <*> pure (RVar FZ)
  ]
  where
    genArrBodyU1 m = oneof
      [ pure (RLam TyRepU (RVar FZ))
      , pure (RLam TyRepU (RVar (FS FZ)))
      , RLam TyRepU <$> genBodyU12 (m `div` 2)
      ]
    genBodyU12 m = oneof
      [ pure RUnit
      , pure (RVar FZ)
      , pure (RVar (FS FZ))
      , RApp (RLam TyRepU (RVar FZ)) <$> genBodyU12 (m `div` 2)
      ]

-- Function-sorted terms over context '[U] (lambda bodies at the hole).
genArrU1 :: Gen (Rm '[U] (U :-> U))
genArrU1 = sized genArrU1N
genArrU1N :: Int -> Gen (Rm '[U] (U :-> U))
genArrU1N n = oneof
  [ pure (RLam TyRepU (RVar FZ))
  , RLam TyRepU <$> genBodyU2N (n `div` 2)
  , RApp (RLam TyRepU (RLam TyRepU (RVar FZ))) <$> genBodyU1N (n `div` 2)
  ]

-- Terms over context '[U, U] at sort U (under one refactor binder).
genBodyU2 :: Gen (Rm '[U, U] U)
genBodyU2 = sized genBodyU2N
genBodyU2N :: Int -> Gen (Rm '[U, U] U)
genBodyU2N n = oneof
  [ pure RUnit
  , pure (RVar FZ)
  , pure (RVar (FS FZ))
  , RApp (RLam TyRepU (RVar FZ)) <$> genBodyU2N (n `div` 2)
  ]
