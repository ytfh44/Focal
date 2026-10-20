module Main (main) where

import Test.QuickCheck (Property, conjoin, property)
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
  , splitRun
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
      , testProperty "the PG-analogue needs the focused name" prop_wf_pg_name
      , testProperty "a replacement must carry the focused name" prop_wf_plug_name_premise
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
--   transition standing there.  The replacement carries the focused
--   name, so the name premise holds and the GATE is what rejects: the
--   workflow declares 'submit' only from 'draft' to 'review', so this
--   step is not a declared transition and the gate reports it.
prop_wf_reject :: Property
prop_wf_reject =
  workflowPlug wf0 ctx0 (Transition "submit" "review" "done")
    === Left (InvalidTransition 0 (Transition "submit" "review" "done"))

-- | The gate reports the FIRST offending step (a valid prefix is not
--   enough).  The replacement carries the focused name, so the name
--   premise holds; the first step still validates and the second is not
--   a declared transition, so the gate reports index 1.
prop_wf_first_bad :: Property
prop_wf_first_bad =
  workflowPlug wf0 (TransitionContext [Transition "submit" "draft" "review"] (Transition "approve" "review" "done") [])
    (Transition "approve" "draft" "done")
    === Left (InvalidTransition 1 (Transition "approve" "draft" "done"))

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

-- | The PG-analogue needs the focused name.  A name-preserving plug
--   re-splits to exactly the replacement, so the re-split recovers it;
--   a name-changing plug is a legitimate value but outside that premise
--   — the run it builds no longer contains a transition the split
--   addresses, so the re-split is the zero-candidate case.  Both halves
--   are asserted, so the premise cannot be silently dropped.
--
--   The first half plugs a transition that shares the focused name but
--   not its target, so it discriminates a plug that DROPS the
--   replacement (the original focus would be recovered instead).
prop_wf_pg_name :: Property
prop_wf_pg_name =
  let run0 = Run
        [ Transition "submit" "draft" "review"
        , Transition "approve" "review" "done"
        ]
  in  case splitRun "approve" run0 of
        Nothing   -> property False
        Just ctx  -> conjoin
          [ fmap ctxFocus
              (splitRun "approve"
                (plugRun ctx (Transition "approve" "review" "rejected")))
              == Just (Transition "approve" "review" "rejected")
          , splitRun "approve" (plugRun ctx (Transition "bogus" "x" "y"))
              == Nothing
          ]

-- | A workflow declaring two transitions with the SAME source and
--   target but different names, plus a second declaration of the
--   focused name with another target: the name premise is the only
--   thing that can reject the replacement.
wf1 :: Workflow
wf1 = Workflow ["draft", "review", "done"]
  [ Transition "submit" "draft" "review"
  , Transition "resubmit" "draft" "review"
  , Transition "submit" "draft" "done"
  ]

-- | The focus on 'submit' with nothing taken yet and nothing planned.
ctx1 :: TransitionContext
ctx1 = TransitionContext [] (Transition "submit" "draft" "review") []

-- | The name premise: a replacement under another name is rejected at
--   the focus's index with the offered transition — even though the
--   gate would accept that run ('resubmit' is declared and chains) —
--   because the re-split of that run would find nothing named
--   'submit'.  A replacement carrying the focused name is accepted
--   when the gate accepts it.
prop_wf_plug_name_premise :: Property
prop_wf_plug_name_premise =
  conjoin
    [ workflowPlug wf1 ctx1 (Transition "resubmit" "draft" "review")
        === Left (InvalidTransition 0 (Transition "resubmit" "draft" "review"))
    , workflowPlug wf1 ctx1 (Transition "submit" "draft" "done")
        === Right (Run [Transition "submit" "draft" "done"])
    ]
