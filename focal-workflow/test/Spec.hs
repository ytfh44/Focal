module Main (main) where

import Test.QuickCheck (Property, conjoin)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.QuickCheck (testProperty, (===))

import Focal.Workflow
  ( GateVerdict(..)
  , InvalidTransition(..)
  , Run(..)
  , Transition(..)
  , TransitionContext(..)
  , Workflow(..)
  , plugRun
  , validateGate
  , workflowPlug
  )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "focal-workflow — workflow plug"
  [ testGroup "Transition validation"
      [ testProperty "a declared replacement is accepted" prop_wf_accept
      , testProperty "an undeclared replacement reports its step" prop_wf_reject
      , testProperty "the gate reports the first offending step" prop_wf_first_bad
      , testProperty "a rejected replacement leaves the context untouched" prop_wf_untouched
      , testProperty "consecutive transitions must chain" prop_wf_continuity
      ]
  ]

--------------------------------------------------------------------
-- Properties — the workflow plug (finite, hand-checked)
--------------------------------------------------------------------

-- | The submit/approve workflow the properties plug into.
wf0 :: Workflow
wf0 = Workflow ["draft", "review", "done"]
  [ Transition "submit" "draft" "review"
  , Transition "approve" "review" "done"
  ]

-- | The focus on 'submit' with the approval still planned.
ctx0 :: TransitionContext
ctx0 = TransitionContext [] (Transition "submit" "draft" "review") [Transition "approve" "review" "done"]

-- | A valid replacement is accepted: the new run is the context with
--   the replacement plugged in.
prop_wf_accept :: Property
prop_wf_accept =
  workflowPlug wf0 ctx0 (Transition "submit" "draft" "review")
    === Right (Run [Transition "submit" "draft" "review", Transition "approve" "review" "done"])

-- | An invalid replacement is rejected with the offending step and the
--   transition standing there.
prop_wf_reject :: Property
prop_wf_reject =
  workflowPlug wf0 ctx0 (Transition "rework" "review" "draft")
    === Left (InvalidTransition 0 (Transition "rework" "review" "draft"))

-- | The gate reports the FIRST offending step (a valid prefix is not
--   enough).
prop_wf_first_bad :: Property
prop_wf_first_bad =
  workflowPlug wf0 (TransitionContext [Transition "submit" "draft" "review"] (Transition "approve" "review" "done") [])
    (Transition "rework" "review" "draft")
    === Left (InvalidTransition 1 (Transition "rework" "review" "draft"))

-- | A rejected replacement leaves the context untouched: plugging the
--   ORIGINAL focus still validates.
prop_wf_untouched :: Property
prop_wf_untouched =
  conjoin
    [ validateGate wf0 (plugRun ctx0 (Transition "rework" "review" "draft"))
        === GateRejected 0 (Transition "rework" "review" "draft")
    , validateGate wf0 (plugRun ctx0 (ctxFocus ctx0)) === GateOk
    ]

-- | Continuity: the reversed pair chains nowhere (the first step's
--   target \'done\' is not the second step's source \'draft\'), so the
--   gate rejects the run at the second step even though both
--   transitions are declared.
prop_wf_continuity :: Property
prop_wf_continuity =
  validateGate wf0
    (Run [ Transition "approve" "review" "done"
         , Transition "submit" "draft" "review"
         ])
    === GateRejected 1 (Transition "submit" "draft" "review")
