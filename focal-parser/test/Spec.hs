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
  , ParseState(..)
  , ReparseReport(..)
  , Residual
  , Selection(..)
  , Sym(..)
  , focusAt
  , focusForest
  , nodeAlt
  , parse
  , parseAll
  , parseOne
  , plugForest
  , reparseReport
  , residualSel
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
      , testProperty "the multi-derivation case enumerates both alternatives" prop_ps_ambiguity_multi
      , testProperty "a nullable derivation is dropped, not looped" prop_ps_nullable_divergence
      , testProperty "the plugged tree re-hits the residual's coordinate" prop_ps_rehit
      ]
  , testGroup "Derivation progress"
      [ testProperty "a cyclic grammar terminates with no derivation" prop_ps_cycle_terminates
      , testProperty "a productive right-recursive grammar still parses" prop_ps_recursive_grammar
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
--   replaced node's LOCAL structural admission (its kind must declare
--   the production its provenance names, with symbols matching the
--   children) plus the grammar's other alternatives for that kind
--   (listed, never resolved), and nothing for an unknown kind.
prop_ps_reparse_report :: Property
prop_ps_reparse_report = conjoin
  [ reparseReport [("p", [("pair", []), ("solo", [])])] (Forest "p" (Alt "pair") [])
      === ReparseReport "p" (Alt "pair") True ["solo"]
  , reparseReport gP fP === ReparseReport "p" (Alt "pair") True []
  , reparseReport gP (Forest "n" (Alt "lit") [])
      === ReparseReport "n" (Alt "lit") False []
  , reparseReport gP (Forest "q" (Alt "lit") [])
      === ReparseReport "q" (Alt "lit") False []
  ]

-- | The multi-derivation case is REAL, not merely reported statically:
--   a kind whose two alternatives match the SAME input has BOTH
--   derivations enumerated by 'parseAll' (in grammar order), while the
--   deterministic 'parse' takes the first alternative; the reparse
--   report of such a node admits it and lists the competing
--   alternative — enumerated and reported, never silently resolved.
prop_ps_ambiguity_multi :: Property
prop_ps_ambiguity_multi = conjoin
  [ length fsA === 2
  , map nodeAlt fsA === [Alt "a", Alt "b"]
  , fmap (nodeAlt . fst) (parse gA ["x"] "e") === Just (Alt "a")
  , reparseReport gA (Forest "e" (Alt "a") [Forest "x" (Alt "x") []])
      === ReparseReport "e" (Alt "a") True ["b"]
  , reparseReport gA (Forest "e" (Alt "b") [Forest "x" (Alt "x") []])
      === ReparseReport "e" (Alt "b") True ["a"]
  ]
  where
    -- The ambiguous grammar: two alternatives, both consuming "x".
    gA :: Grammar
    gA = [("e", [("a", [Term "x"]), ("b", [Term "x"])])]
    -- Every completed derivation of "e" over the input ["x"].
    fsA :: [Forest]
    fsA = parseAll gA ["x"] "e"

-- | The documented precondition, witnessed explicitly: 'ge' has a
--   nullable nonterminal ("e" derives the empty sequence), so the
--   zero-consumption prune drops that derivation — 'parse' admits the
--   input through it, while 'parseAll' returns no result at all.  This
--   is exactly the divergence the 'parseAll' haddock states.
prop_ps_nullable_divergence :: Property
prop_ps_nullable_divergence = conjoin
  [ fmap fst (parse ge ["x"] "q")
      === Just (Forest "q" (Alt "two")
                  [Forest "e" (Alt "empty") [], Forest "x" (Alt "x") []])
  , parseAll ge ["x"] "q" === []
  ]
  where
    -- The nullable grammar: "e" derives nothing; "q" is "e" then "x".
    ge :: Grammar
    ge = [("e", [("empty", [])]), ("q", [("two", [NonTerm "e", Term "x"])])]

-- | The re-hit clause for the forest focus, over the whole plug
--   domain: a focus taken at a coordinate re-hits that coordinate in
--   the plugged tree — selecting the residual's coordinate in the
--   plugged tree recovers the plugged node — and the plug
--   CONTINUATION is stable: the residual re-taken at the re-hit
--   coordinate plugs a second node to the tree the first residual
--   plugs it to.  The residual can only come from 'focusForest', so its
--   frames are consistent with its coordinate by construction.
prop_ps_rehit :: Property
prop_ps_rehit = conjoin
  [ rehit (Selection [])     fP
  , rehit (Selection [1])    fP
  , rehit (Selection [0, 0]) fP
  ]
  where
    -- The fresh node: a subtree, so the plug domain is not leaves only.
    fresh :: Forest
    fresh = Forest "z" (Alt "zz") [Forest "z1" (Alt "zz1") []]
    -- The continuation's node: a second, different fresh node.
    fresh2 :: Forest
    fresh2 = Forest "y" (Alt "yy") []
    rehit :: Selection -> Forest -> Property
    rehit sel f = case focusForest sel f of
      Nothing -> property False
      Just ff ->
        let res = focusResidual ff
            t   = plugForest res fresh
        in  case select (residualSel res) t of
              Nothing -> property False
              Just got ->
                conjoin
                  [ got === fresh
                  , case refocused res t of
                      Nothing   -> property False
                      Just res2 -> plugForest res2 fresh2 === plugForest res fresh2
                  ]
    -- The residual re-taken at the re-hit coordinate.
    refocused :: Residual -> Forest -> Maybe Residual
    refocused res t = fmap focusResidual (focusForest (residualSel res) t)

-- | A CYCLIC grammar terminates: the derivation re-enters a nonterminal
--   at the SAME input position, so it makes no progress and fails — the
--   deterministic parser reports absence and the enumerating parser
--   reports no derivation.  Without the progress criterion this
--   derivation never ends.
prop_ps_cycle_terminates :: Property
prop_ps_cycle_terminates = conjoin
  [ parse gC ["x"] "a" === Nothing
  , parseAll gC ["x"] "a" === []
  , parseOne gC (ParseState [] ["x"]) "a" === Nothing
  , parse gC ["x"] "b" === Nothing
  , parseAll gC ["x"] "b" === []
  ]
  where
    -- The cyclic grammar: "a" derives "b" and "b" derives "a", so every
    -- derivation revisits a nonterminal at the position it started from.
    gC :: Grammar
    gC = [("a", [("toB", [NonTerm "b"])]), ("b", [("toA", [NonTerm "a"])])]

-- | A PRODUCTIVE right-recursive grammar still parses: every cycle
--   consumes a token, so the nonterminal is re-entered at a LATER
--   position and the progress criterion never fires.  The SIBLING case
--   is legal too: the same nonterminal twice in one production is a
--   sibling expansion, not an ancestor, so it is not a cycle.
prop_ps_recursive_grammar :: Property
prop_ps_recursive_grammar = conjoin
  [ parse gR ["x", "x"] "a"
      === Just (Forest "a" (Alt "step")
                  [ Forest "x" (Alt "x") []
                  , Forest "a" (Alt "leaf") [Forest "x" (Alt "x") []]
                  ], ["x", "x"])
  , parseAll gR ["x", "x"] "a"
      === [ Forest "a" (Alt "step")
              [ Forest "x" (Alt "x") []
              , Forest "a" (Alt "leaf") [Forest "x" (Alt "x") []]
              ] ]
  , parse gS [] "p"
      === Just (Forest "p" (Alt "pair")
                  [ Forest "n" (Alt "nil") []
                  , Forest "n" (Alt "nil") []
                  ], [])
  ]
  where
    -- The right-recursive grammar: "a" is a token followed by "a" (the
    -- cycle consumes a token each time), or a bare token.
    gR :: Grammar
    gR = [("a", [("step", [Term "x", NonTerm "a"]), ("leaf", [Term "x"])])]
    -- The sibling grammar: "p" holds two "n"s (a nullable nonterminal),
    -- so the second "n" is expanded at the same position as the first.
    gS :: Grammar
    gS = [("n", [("nil", [])]), ("p", [("pair", [NonTerm "n", NonTerm "n"])])]
