module Main (main) where

import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.QuickCheck (testProperty)

import Focal.Syntax (Tm(..), TyRep(..), exApp, exConst)
import Focal.Syntax.Stack (Stack(..), plugStack)

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "focal-syntax — sort-indexed contexts"
  [ testGroup "Concrete examples (regression)"
      [ testProperty "plugStack (AppL Hole TUnit) exConst = exApp" prop_stack_appL
      , testProperty "plugStack (AppR exConst Hole) TUnit = exApp" prop_stack_appR
      , testProperty "plugStack (LamS TyRepU Hole) TUnit = exConst" prop_stack_lamS
      ]
  ]

prop_stack_appL :: Bool
prop_stack_appL = plugStack (AppL Hole TUnit) exConst == exApp

prop_stack_appR :: Bool
prop_stack_appR = plugStack (AppR exConst Hole) TUnit == exApp

prop_stack_lamS :: Bool
prop_stack_lamS = plugStack (LamS TyRepU Hole) TUnit == exConst
