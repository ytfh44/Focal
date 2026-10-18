module Main (main) where

import Test.QuickCheck (Property, conjoin, property)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.QuickCheck (testProperty, (===))

import Focal.Parser
  ( Alt(..)
  , Forest(..)
  , ForestFocus(..)
  , Grammar
  , NodeFocus(..)
  , ReparseReport(..)
  , Residual(..)
  , Selection(..)
  , Sym(..)
  , focusAt
  , focusForest
  , nodeAlt
  , plugForest
  , reparseReport
  , select
  )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "focal-parser — grammar focus"
  [ testGroup "Forest focus"
      [ testProperty "focus-then-plug with the same node rebuilds the forest" prop_ps_focus_roundtrip
      , testProperty "the residual's selection re-selects the replaced node" prop_ps_selection_preserved
      , testProperty "ancestor provenance survives replacement" prop_ps_provenance_preserved
      , testProperty "the reparse report lists the kind's other alternatives" prop_ps_reparse_report
      ]
  ]

--------------------------------------------------------------------
-- Properties — the demo grammar and forest (finite, hand-checked)
--------------------------------------------------------------------

-- | The demo grammar: a single-alternative literal kind and a pair kind
--   over two children.
gP :: Grammar
gP = [("n", [("lit", [Term "x"])]), ("p", [("pair", [NonTerm "n", NonTerm "n"])])]

-- | A two-child forest of 'gP''s pair shape.
fP :: Forest
fP = Forest "p" (Alt "pair")
  [ Forest "n" (Alt "lit") [Forest "x" (Alt "x") []]
  , Forest "n" (Alt "lit") [Forest "x" (Alt "x") []]
  ]

-- | Focus-then-plug with the SAME node rebuilds the forest (the focus
--   round trip), for every in-range selection: the residual's frames
--   carry the siblings and provenance the rebuild needs, and the
--   coordinate the focus was taken at is the one that comes back.
prop_ps_focus_roundtrip :: Property
prop_ps_focus_roundtrip = conjoin
  [ roundtrip (Selection [])     fP
  , roundtrip (Selection [1])    fP
  , roundtrip (Selection [0, 0]) fP
  ]
  where
    roundtrip :: Selection -> Forest -> Property
    roundtrip sel f = case focusForest sel f of
      Nothing  -> property False
      Just ff  -> plugForest (focusResidual ff) (focused ff) === f

-- | The residual's selection coordinate re-selects the replaced node —
--   the replacement laws are stated relative to the coordinate the
--   focus was taken at, at every depth.
prop_ps_selection_preserved :: Property
prop_ps_selection_preserved = conjoin
  [ selcheck (Selection [1])    fP (Forest "z" (Alt "zz") [])
  , selcheck (Selection [0, 0]) fP (Forest "z" (Alt "zz") [])
  ]
  where
    selcheck :: Selection -> Forest -> Forest -> Property
    selcheck sel f new = case focusForest sel f of
      Nothing -> property False
      Just ff -> case select (residualSel (focusResidual ff))
                             (plugForest (focusResidual ff) new) of
        Nothing  -> property False
        Just got -> got === new

-- | Ancestor provenance survives replacement: after replacing at a
--   selection, the refreshed focus chains the ancestors' alternatives
--   (root first) with the NEW node's own — the choice records above the
--   hole travel in the frames, and the replaced node's provenance is
--   the new node's.
prop_ps_provenance_preserved :: Property
prop_ps_provenance_preserved =
  case focusForest (Selection [1]) fP of
    Nothing -> property False
    Just ff ->
      let replaced = plugForest (focusResidual ff) (Forest "z" (Alt "zz") [])
      in  case focusAt (Selection [1]) replaced of
            Nothing -> property False
            Just nf -> conjoin
              [ focusProv nf === [Alt "pair", Alt "zz"]
              , nodeAlt (focusNode nf) === Alt "zz"
              ]

-- | The reparse report computes the induced parse-set change: the
--   grammar's alternatives for the replaced node's kind minus the one
--   its provenance claims (listed, never resolved), and nothing for an
--   unknown kind.
prop_ps_reparse_report :: Property
prop_ps_reparse_report = conjoin
  [ reparseReport [("p", [("pair", []), ("solo", [])])] (Forest "p" (Alt "pair") [])
      === ReparseReport "p" (Alt "pair") ["solo"]
  , reparseReport gP fP === ReparseReport "p" (Alt "pair") []
  , reparseReport gP (Forest "q" (Alt "lit") [])
      === ReparseReport "q" (Alt "lit") []
  ]
