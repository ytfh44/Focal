module Main (main) where

import Test.QuickCheck (Property, property)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.QuickCheck (testProperty, (===))

import Focal.Query
  ( Candidate(..)
  , JoinWitness(..)
  , Projection(..)
  , RelDelta(..)
  , Table(..)
  , View(..)
  , ViewRow(..)
  , fixedPolicy
  , project
  , relPutback
  , writeBack
  )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "focal-query — relational putback"
  [ testGroup "Policy-ordered putback"
      [ testProperty "one candidate becomes the delta at the row's provenance" prop_rq_ok
      , testProperty "several candidates report the ordered ambiguity" prop_rq_ambiguous
      , testProperty "zero candidates report the empty ambiguity" prop_rq_none
      , testProperty "provenance drives the delta" prop_rq_provenance
      ]
  ]

--------------------------------------------------------------------
-- Properties — the relational putback (finite, hand-checked)
--------------------------------------------------------------------

-- | The two-row table the properties put back into.
t1 :: Table
t1 = Table ["id", "name"] [[("id", "1"), ("name", "a")], [("id", "2"), ("name", "b")]]

-- | The first view row of 't1' projected to its name column.
vr0 :: ViewRow
vr0 = case project (Projection ["name"]) t1 of
  View (r : _) -> r
  View []      -> ViewRow [] 0 (JoinWitness 0 Nothing)

-- | One candidate applies: the relation-level delta carries the row's
--   provenance and the candidate's column/value.
prop_rq_ok :: Property
prop_rq_ok =
  relPutback writeBack t1 vr0 "name" "z" === Right (RelDelta (viewSource vr0) "name" "z")

-- | Several candidates report the ordered ambiguity, never a choice.
prop_rq_ambiguous :: Property
prop_rq_ambiguous =
  relPutback (fixedPolicy [Candidate "name" "z", Candidate "id" "9"]) t1 vr0 "name" "z"
    === Left [Candidate "name" "z", Candidate "id" "9"]

-- | Zero candidates report the empty ambiguity.
prop_rq_none :: Property
prop_rq_none =
  relPutback (fixedPolicy []) t1 vr0 "name" "z" === Left []

-- | Provenance drives the delta: editing the SECOND view row targets its
--   source row.
prop_rq_provenance :: Property
prop_rq_provenance =
  case project (Projection ["name"]) t1 of
    View [_, r2] -> relPutback writeBack t1 r2 "name" "y" === Right (RelDelta 1 "name" "y")
    _            -> property False
