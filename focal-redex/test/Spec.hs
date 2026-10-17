{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeOperators #-}

module Main (main) where

import Test.QuickCheck (Property, property)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.QuickCheck (testProperty, (===))

import Focal.Optional (FocusingO(..))
import Focal.Syntax (Ty(..), TyRep(..))
import Focal.Redex
  ( Decomp(..), EvalCtx(..), Fin(..), Redex(..), Rm(..), Value(..)
  , decompose, plugEval, redexF, redexTerm, step
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
      , testProperty "redexF split finds the head redex" prop_rd_redexF_split
      , testProperty "redexF plug rebuilds the term" prop_rd_redexF_plug
      , testProperty "redexF miss on a value" prop_rd_redexF_miss
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
prop_rd_redexF_split = splitO redexF tHead === Just (Beta TyRepU (RVar FZ) RUnit, EHole)

prop_rd_redexF_plug :: Property
prop_rd_redexF_plug = plugO redexF EHole (Beta TyRepU (RVar FZ) RUnit) === tHead

prop_rd_redexF_miss :: Property
prop_rd_redexF_miss =
  splitO redexF (RLam TyRepU (RVar FZ) :: Rm '[] (U :-> U)) === Nothing
