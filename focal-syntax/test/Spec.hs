{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

module Main (main) where

import Test.QuickCheck (Gen, Property, conjoin, forAll, oneof, property, sized)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.QuickCheck (testProperty, (===))

import Focal.Syntax (Ty(..), Tm(..), TyRep(..), exApp, exConst)
import Focal.Syntax.Stack (Stack(..), plugStack, splitStack)

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "focal-syntax — sort-indexed contexts"
  [ testGroup "Concrete examples (regression)"
      [ testProperty "plugStack (AppL Hole TUnit) exConst = exApp" prop_stack_appL
      , testProperty "plugStack (AppR exConst Hole) TUnit = exApp" prop_stack_appR
      , testProperty "plugStack (LamS TyRepU Hole) TUnit = exConst" prop_stack_lamS
      ]
  , testGroup "Typed syntax — sort-indexed laws"
      [ testProperty "hit => plugStack c a = t" prop_tm_gp
      , testProperty "splitStack ri (plugStack c b) = Just (b, c)" prop_tm_path
      , testProperty "plugStack c' b2 = plugStack c b2 on the residual image" prop_tm_pp
      ]
  ]

--------------------------------------------------------------------
-- Concrete examples (regression)
--------------------------------------------------------------------

prop_stack_appL :: Bool
prop_stack_appL = plugStack (AppL Hole TUnit) exConst == exApp

prop_stack_appR :: Bool
prop_stack_appR = plugStack (AppR exConst Hole) TUnit == exApp

prop_stack_lamS :: Bool
prop_stack_lamS = plugStack (LamS TyRepU Hole) TUnit == exConst

--------------------------------------------------------------------
-- Generators — closed terms at the two fixed sorts
--------------------------------------------------------------------

-- | Size-bounded closed terms at sort @U@.
genTmU :: Gen (Tm U)
genTmU = sized genU

-- | Size-bounded closed terms at sort @U :-> U@.
genTmArr :: Gen (Tm (U :-> U))
genTmArr = sized genArr

genU :: Int -> Gen (Tm U)
genU 0 = pure TUnit
genU n = oneof
  [ pure TUnit
  , TApp <$> genArr (n - 1) <*> genU (n - 1)
  ]

genArr :: Int -> Gen (Tm (U :-> U))
genArr 0 = pure exConst
genArr n = oneof
  [ pure exConst
  , TLam TyRepU <$> genU (n - 1)
  , (\g x -> TApp (TLam TyRepU g) x) <$> genArr (n - 1) <*> genU (n - 1)
  ]

--------------------------------------------------------------------
-- Laws — sort-indexed contexts
--------------------------------------------------------------------

-- | Well-sorted round-trip, plug side: whenever the canonical split finds
--   an occurrence, plugging the focus back through the context rebuilds
--   the term.
prop_tm_gp :: Property
prop_tm_gp = conjoin
  [ forAll genTmU (gpAt TyRepU)
  , forAll genTmU (gpAt tyArr)
  , forAll genTmArr (gpAt TyRepU)
  , forAll genTmArr (gpAt tyArr)
  ]
  where
    tyArr = TyRepArr TyRepU TyRepU
    gpAt :: TyRep i -> Tm j -> Bool
    gpAt ri t = case splitStack ri t of
      Nothing     -> True
      Just (a, c) -> plugStack c a == t

-- | Path preservation on the residual image: a focus plugged at the split
--   path re-splits to the same focus and context.
prop_tm_path :: Property
prop_tm_path = conjoin
  [ forAll genTmU (pathAt TyRepU genTmU)
  , forAll genTmU (pathAt tyArr genTmArr)
  , forAll genTmArr (pathAt TyRepU genTmU)
  , forAll genTmArr (pathAt tyArr genTmArr)
  ]
  where
    tyArr = TyRepArr TyRepU TyRepU
    pathAt :: TyRep i -> Gen (Tm i) -> Tm j -> Property
    pathAt ri g t = case splitStack ri t of
      Nothing     -> property True
      Just (_, c) -> forAll g $ \b -> splitStack ri (plugStack c b) === Just (b, c)

-- | Residual-overwrite stability on the residual image: re-splitting after
--   a write recovers the same context, so a later write behaves identically.
prop_tm_pp :: Property
prop_tm_pp = conjoin
  [ forAll genTmU (ppAt TyRepU genTmU)
  , forAll genTmU (ppAt tyArr genTmArr)
  , forAll genTmArr (ppAt TyRepU genTmU)
  , forAll genTmArr (ppAt tyArr genTmArr)
  ]
  where
    tyArr = TyRepArr TyRepU TyRepU
    ppAt :: TyRep i -> Gen (Tm i) -> Tm j -> Property
    ppAt ri g t = case splitStack ri t of
      Nothing     -> property True
      Just (_, c) -> forAll g $ \b1 -> forAll g $ \b2 ->
        case splitStack ri (plugStack c b1) of
          Just (_, c') -> plugStack c' b2 === plugStack c b2
          Nothing      -> property False
