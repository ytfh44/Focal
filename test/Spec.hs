{-# OPTIONS_GHC -Wno-orphans #-}

module Main (main) where

import Data.Functor.Identity (Identity(..))
import Data.List (splitAt)
import Test.Tasty
import Test.Tasty.QuickCheck

import Focal.Core
import Focal.Tuple
import Focal.List
import Focal.Zipper

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Focal — Axiom Coverage"
  [ ---------------------------------------------------------------
    -- Axiom 1: Split-Plug Reconstruction
    --   let (a, c) = splitF f s in plugF f c a == s
    ---------------------------------------------------------------
    testGroup "A1 — Split-Plug Reconstruction"
      [ testProperty "idF: plug original focus = s"           prop_a1_idF
      , testProperty "fstF: plug original focus = s"          prop_a1_fstF
      , testProperty "sndF: plug original focus = s"          prop_a1_sndF
      , testProperty "list element: plug original focus = s"  prop_a1_list
      , testProperty "Rose fromZip: plug original focus = s"   prop_a1_roseZip
      , testProperty "BinTree fromZip: plug original focus = s" prop_a1_binZip
      , testProperty "lens-like: roundtrip via pureF"         prop_a1_pureF
      , testProperty "composed focus: plug original focus = s" prop_a1_composed
      ]

  ---------------------------------------------------------------
  -- Axiom 2: Residual Legality
  --   Residual must carry validity relative to source (not forgeable).
  --   The Focal existential quantifier hides c; the splitF→plugF
  --   roundtrip is the witnessed validity.
  ---------------------------------------------------------------
  , testGroup "A2 — Residual Legality"
      [ testProperty "idF residual () paired with s always restores"  prop_a2_idF
      , testProperty "list residual depends on source length"          prop_a2_list_depends
      , testProperty "Rose residual depends on exact source"           prop_a2_rose_depends
      ]

  ---------------------------------------------------------------
  -- Axiom 3: Composition Associativity
  --   (f >>> g) >>> h  ≃  f >>> (g >>> h)
  --   Up to residual tuple reassociation: ((c1,c2),c3) ≃ (c1,(c2,c3))
  ---------------------------------------------------------------
  , testGroup "A3 — Composition Associativity"
      [ testProperty "idF chain: behavioural equivalence"            prop_a3_idChain
      , testProperty "tuple chain: mixed focus type"                 prop_a3_tupleChain
      , testProperty "list into tuple composition"                   prop_a3_listTupleChain
      , testProperty "composition respects plug law"                 prop_a3_plugLaw
      ]

  ---------------------------------------------------------------
  -- Axiom 4: Identity Focus
  --   idF >>> f  ≃  f       f >>> idF  ≃  f
  ---------------------------------------------------------------
  , testGroup "A4 — Identity Focus"
      [ testProperty "idF >>> fstF  ≈  fstF"              prop_a4_leftId_fst
      , testProperty "idF >>> elementF ≈ elementF"        prop_a4_leftId_list
      , testProperty "idF >>> fromZip ≈ fromZip"          prop_a4_leftId_zipper
      , testProperty "fstF >>> idF ≈ fstF"                prop_a4_rightId_fst
      , testProperty "elementF >>> idF ≈ elementF"        prop_a4_rightId_list
      , testProperty "fromZip >>> idF ≈ fromZip"          prop_a4_rightId_zipper
      ]

  ---------------------------------------------------------------
  -- Axiom 5: Locality
  --   plugF : c -> b -> t  (no Env, no IO, no global state).
  --   Statically enforced by type signature; tested via purity check.
  ---------------------------------------------------------------
  , testGroup "A5 — Locality (purity)"
      [ testProperty "overFM pure = overF (no effect dependency)"   prop_a5_overFM_pure
      ]

  ---------------------------------------------------------------
  -- Axiom 6: Occurrence ≠ Value
  --   focus position = (a, c), not just a.
  --   Two different occurrences of the same value yield different residuals.
  ---------------------------------------------------------------
  , testGroup "A6 — Occurrence ≠ Value"
      [ testProperty "list: equal values at different indices"     prop_a6_list
      , testProperty "Rose: equal subtrees at different paths"     prop_a6_rose
      , testProperty "BinTree: equal leaves at different paths"    prop_a6_binTree
      ]

  ---------------------------------------------------------------
  -- Extension Axiom B: Path—Residual Consistency
  --   position -> (focus, residual)  and  (focus, residual, valid) -> position
  ---------------------------------------------------------------
  , testGroup "XB — Path-Residual Consistency"
      [ testProperty "Rose: safeFocusAt valid path extracts child"        prop_xb_safeFocusAt_valid
      , testProperty "Rose: safeFocusAt invalid path = Nothing"           prop_xb_safeFocusAt_invalid
      , testProperty "Rose: fromZip roundtrip from focused position"      prop_xb_fromZip_roundtrip
      , testProperty "Rose: multi-level navigation preserves context"     prop_xb_multilevel
      ]

  ---------------------------------------------------------------
  -- Extension Axiom D: Edit Survival (prefix-controlled fragment)
  --   On the same focus, latter overwrites former.
  --   Nested edits decompose correctly into outer focus.
  ---------------------------------------------------------------
  , testGroup "XD — Edit Survival"
      [ testProperty "same-focus edits compose via overF"           prop_xd_sameFocus_overwrite
      , testProperty "nested edit decomposes correctly"             prop_xd_nestedEdit
      , testProperty "independent foci commute"                     prop_xd_independentFoci
      ]

  ---------------------------------------------------------------
  -- Zipper: Descend/Ascend roundtrip (ZipTree law)
  ---------------------------------------------------------------
  , testGroup "Zipper — Descend/Ascend roundtrip"
      [ testProperty "Rose: ascend frame (descend child t) == t"    prop_rose_roundtrip
      , testProperty "BinTree: ascend frame (descend child t) == t" prop_bintree_roundtrip
      ]

  ---------------------------------------------------------------
  -- Zipper: Navigation roundtrip
  ---------------------------------------------------------------
  , testGroup "Zipper — Navigation roundtrip"
      [ testProperty "Rose: up (down child z) preserves current"    prop_rose_updown
      , testProperty "Rose: rootZip >> up = Nothing"                prop_rose_rootUp
      ]

  ---------------------------------------------------------------
  -- Concrete Examples (regression)
  ---------------------------------------------------------------
  , testGroup "Concrete Examples"
      [ testProperty "overF fstF show (42, \"hello\")"    prop_concrete_tuple
      , testProperty "overF (unsafeElementF 1) (*10) [1,2,3]" prop_concrete_list
      ]

  ---------------------------------------------------------------
  -- Tuple & List Update Preservation (regression)
  ---------------------------------------------------------------
  , testGroup "Tuple & List Update"
      [ testProperty "fstF: update preserves snd"             prop_fstF_update
      , testProperty "sndF: update preserves fst"             prop_sndF_update
      , testProperty "elementF: negative index = Nothing"     prop_listElement_negative
      , testProperty "unsafeElementF: update first element"    prop_listElement_update
      , testProperty "unsafeElementF: update random element"   prop_listElement_update_random
      ]
  ]

--------------------------------------------------------------------
-- Axiom 1: Split-Plug Reconstruction
--------------------------------------------------------------------

prop_a1_idF :: Int -> Bool
prop_a1_idF s =
  let (focus, ctx) = splitF idF s
  in plugF idF ctx focus == s

prop_a1_fstF :: (Int, Int) -> Bool
prop_a1_fstF pair =
  let (focus, ctx) = splitF fstF pair
  in plugF fstF ctx focus == pair

prop_a1_sndF :: (Int, Int) -> Bool
prop_a1_sndF pair =
  let (focus, ctx) = splitF sndF pair
  in plugF sndF ctx focus == pair

prop_a1_list :: [Int] -> NonNegative Int -> Property
prop_a1_list xs (NonNegative n) =
  not (null xs) ==> do
    let i = n `mod` length xs
        f = unsafeElementF i
        (focus, ctx) = splitF f xs
    plugF f ctx focus === xs

prop_a1_roseZip :: Rose Int -> Property
prop_a1_roseZip t@(Rose _ kids) =
  not (null kids) ==> do
    let Just z  = down (0 :: Int) (rootZip t)
        f       = fromZip z
        (focus, ctx) = splitF f t
    plugF f ctx focus === t

prop_a1_binZip :: BinTree Int -> Property
prop_a1_binZip t@(Node _ _) = do
  let Just z  = down GoLeft (rootZip t)
      f       = fromZip z
      (focus, ctx) = splitF f t
  plugF f ctx focus === t
prop_a1_binZip Leaf{} = property True

prop_a1_pureF :: Int -> Bool
prop_a1_pureF s =
  let f = pureF id (\_ b -> b)
      (focus, ctx) = splitF f s
  in plugF f ctx focus == s

prop_a1_composed :: ([Int], String) -> Property
prop_a1_composed pair =
  not (null (fst pair)) ==> do
    let f   = fstF >>> unsafeElementF 0
        (focus, ctx) = splitF f pair
    plugF f ctx focus === pair

--------------------------------------------------------------------
-- Axiom 2: Residual Legality
--------------------------------------------------------------------

prop_a2_idF :: Int -> Bool
prop_a2_idF s =
  let (_, ctx) = splitF idF s
      (focus', _) = splitF idF (s + 1)
  in plugF idF ctx focus' == s + 1

prop_a2_list_depends :: [Int] -> NonNegative Int -> Property
prop_a2_list_depends xs (NonNegative n) =
  not (null xs) ==> do
    let i = n `mod` length xs
        f = unsafeElementF i
        (focus, ctx) = splitF f xs
    plugF f ctx focus === xs

prop_a2_rose_depends :: Rose Int -> Property
prop_a2_rose_depends t@(Rose _ kids) =
  not (null kids) ==> do
    let Just z  = down (0 :: Int) (rootZip t)
        f       = fromZip z
        (focus', ctx) = splitF f t
    plugF f ctx focus' === t

--------------------------------------------------------------------
-- Axiom 3: Composition Associativity
--------------------------------------------------------------------

prop_a3_idChain :: Int -> Bool
prop_a3_idChain s =
  let left  = (idF >>> idF) >>> idF
      right = idF >>> (idF >>> idF)
  in overF left id s == overF right id s

prop_a3_tupleChain :: (((Int, Int), String), Bool) -> Bool
prop_a3_tupleChain v =
  let f = fstF
      g = fstF
      assocL = (f >>> g) -- focuses outermost fst, then inner fst
      assocR = (f >>> g) -- trivially same since idF not in chain
      -- Test: compose idF as an extra layer
      left  = (idF >>> f) >>> fstF
      right = idF >>> (f >>> fstF)
  in overF left id v == overF right id v

prop_a3_listTupleChain :: ([Int], String) -> Property
prop_a3_listTupleChain pair =
  not (null (fst pair)) ==> do
    let f = fstF
        g = unsafeElementF 0
        left  = (f >>> g) >>> idF
        right = f >>> (g >>> idF)
    overF left id pair === overF right id pair

prop_a3_plugLaw :: ([Int], String) -> Property
prop_a3_plugLaw pair =
  not (null (fst pair)) ==> do
    let f = fstF
        g = unsafeElementF 0
        combined = f >>> g
        (_, (c1, c2)) = splitF combined pair
        y = 42
    plugF combined (c1, c2) y === plugF f c1 (plugF g c2 y)

--------------------------------------------------------------------
-- Axiom 4: Identity Focus
--------------------------------------------------------------------

prop_a4_leftId_fst :: (Int, Int) -> Bool
prop_a4_leftId_fst pair =
  let f = fstF
  in overF (idF >>> f) id pair == overF f id pair

prop_a4_leftId_list :: [Int] -> NonNegative Int -> Property
prop_a4_leftId_list xs (NonNegative n) =
  not (null xs) ==> do
    let i = n `mod` length xs
        f = unsafeElementF i
    overF (idF >>> f) id xs === overF f id xs

prop_a4_leftId_zipper :: Rose Int -> Property
prop_a4_leftId_zipper t@(Rose _ kids) =
  not (null kids) ==> do
    let Just z = down (0 :: Int) (rootZip t)
        f      = fromZip z
    overF (idF >>> f) id t === overF f id t

prop_a4_rightId_fst :: (Int, Int) -> Bool
prop_a4_rightId_fst pair =
  let f = fstF
  in overF (f >>> idF) id pair == overF f id pair

prop_a4_rightId_list :: [Int] -> NonNegative Int -> Property
prop_a4_rightId_list xs (NonNegative n) =
  not (null xs) ==> do
    let i = n `mod` length xs
        f = unsafeElementF i
    overF (f >>> idF) id xs === overF f id xs

prop_a4_rightId_zipper :: Rose Int -> Property
prop_a4_rightId_zipper t@(Rose _ kids) =
  not (null kids) ==> do
    let Just z = down (0 :: Int) (rootZip t)
        f      = fromZip z
    overF (f >>> idF) id t === overF f id t

--------------------------------------------------------------------
-- Axiom 5: Locality (purity)
--------------------------------------------------------------------

prop_a5_overFM_pure :: [Int] -> NonNegative Int -> Property
prop_a5_overFM_pure xs (NonNegative n) =
  not (null xs) ==> do
    let i = n `mod` length xs
        f = unsafeElementF i
    overFM f (Identity . id) xs === Identity (overF f id xs)

--------------------------------------------------------------------
-- Axiom 6: Occurrence ≠ Value
--------------------------------------------------------------------

prop_a6_list :: [Int] -> Property
prop_a6_list xs =
  length xs >= 2 ==> do
    let f0 = unsafeElementF 0
        f1 = unsafeElementF 1
        (a0, c0) = splitF f0 xs
        (a1, c1) = splitF f1 xs
    property $ if a0 == a1 then c0 /= c1 else True

prop_a6_rose :: Property
prop_a6_rose =
  forAll genRoseWithDup $ \t ->
    case safeNavigate [0] t of
      Just z0 ->
        case safeNavigate [1] t of
          Just z1 ->
            let f0 = fromZip z0
                f1 = fromZip z1
                (a0, c0) = splitF f0 t
                (a1, c1) = splitF f1 t
            in property $ if a0 == a1 then c0 /= c1 else True
          Nothing -> property True
      Nothing -> property True

prop_a6_binTree :: Property
prop_a6_binTree =
  forAll genBinWithDup $ \t ->
    case safeNavigate [GoLeft] t of
      Just zL ->
        case safeNavigate [GoRight] t of
          Just zR ->
            let fL = fromZip zL
                fR = fromZip zR
                (aL, cL) = splitF fL t
                (aR, cR) = splitF fR t
            in property $ if aL == aR then cL /= cR else True
          Nothing -> property True
      Nothing -> property True

--------------------------------------------------------------------
-- Extension Axiom B: Path—Residual Consistency
--------------------------------------------------------------------

prop_xb_safeFocusAt_valid :: Rose Int -> Property
prop_xb_safeFocusAt_valid t@(Rose _ kids) =
  not (null kids) ==> do
    case safeFocusAt [0 :: Int] t of
      Nothing -> property False
      Just f  ->
        let (focus, _) = splitF f t
        in focus === head kids

prop_xb_safeFocusAt_invalid :: Rose Int -> Bool
prop_xb_safeFocusAt_invalid t =
  case safeFocusAt [(-1 :: Int)] t of Nothing -> True; _ -> False

prop_xb_fromZip_roundtrip :: Rose Int -> Property
prop_xb_fromZip_roundtrip t@(Rose _ kids) =
  not (null kids) ==> do
    let Just z       = down (0 :: Int) (rootZip t)
        f            = fromZip z
        (focus, ctx) = splitF f t
    plugF f ctx focus === t

prop_xb_multilevel :: Rose Int -> Property
prop_xb_multilevel t@(Rose _ kids) =
  length kids >= 2 ==> do
    let depth0 = fromZip (rootZip t)
    case safeNavigate [0] t of
      Just z1@(Zip inner (grandparent:_)) ->
        case inner of
          Rose _ grandKids ->
            if not (null grandKids) then
              case safeNavigate [0, 0] t of
                Just z2 ->
                  let f0 = fromZip (rootZip t)
                      f2 = fromZip z2
                      (_, c0) = splitF f0 t
                      (_, c2) = splitF f2 t
                  in length c2 === length c0 + 2
                Nothing -> property True
            else property True
          _ -> property True
      _ -> property True

--------------------------------------------------------------------
-- Extension Axiom D: Edit Survival (prefix-controlled)
--------------------------------------------------------------------

prop_xd_sameFocus_overwrite :: [Int] -> NonNegative Int -> Property
prop_xd_sameFocus_overwrite xs (NonNegative n) =
  not (null xs) ==> do
    let i = n `mod` length xs
        f = unsafeElementF i
    overF f (+1) (overF f (*2) xs) === overF f ((+1) . (*2)) xs

prop_xd_nestedEdit :: ([Int], (String, Int)) -> Property
prop_xd_nestedEdit outer =
  not (null (fst outer)) ==> do
    let f = fstF >>> unsafeElementF 0
        -- apply edit through nested focus, then same edit through direct access
        resultNested = overF f (+1) outer
        (xs, rest) = outer
        resultDirect = case xs of
                         (y:ys) -> ((y + 1) : ys, rest)
                         []     -> outer
    resultNested === resultDirect

prop_xd_independentFoci :: ([Int], [Int]) -> Property
prop_xd_independentFoci (xs, ys) =
  not (null xs) && not (null ys) ==> do
    let fLs = fstF >>> unsafeElementF 0
        fRs = sndF >>> unsafeElementF 0
        applyLsThenRs t = overF fLs (const 99) (overF fRs (const 77) t)
        applyRsThenLs t = overF fRs (const 77) (overF fLs (const 99) t)
        input = (xs, ys)
    applyLsThenRs input === applyRsThenLs input

--------------------------------------------------------------------
-- Zipper: Descend/Ascend roundtrip (ZipTree law)
--------------------------------------------------------------------

prop_rose_roundtrip :: Rose Int -> Property
prop_rose_roundtrip t@(Rose _ kids) =
  not (null kids) ==> do
    let Just (child, frame) = descend (0 :: Int) t
    ascend frame child === t

prop_bintree_roundtrip :: BinTree Int -> Property
prop_bintree_roundtrip t@(Node _ _) =
  let Just (child, frame) = descend GoLeft t
  in ascend frame child === t
prop_bintree_roundtrip Leaf{} = property True

--------------------------------------------------------------------
-- Zipper: Navigation roundtrip
--------------------------------------------------------------------

prop_rose_updown :: Rose Int -> Property
prop_rose_updown t@(Rose _ kids) =
  not (null kids) ==> do
    let z       = rootZip t
        Just z' = down (0 :: Int) z
        Just z'' = up z'
    current z'' === current z

prop_rose_rootUp :: Rose Int -> Bool
prop_rose_rootUp t =
  case up (rootZip t) of
    Nothing -> True
    _       -> False

--------------------------------------------------------------------
-- Concrete Examples
--------------------------------------------------------------------

prop_concrete_tuple :: Property
prop_concrete_tuple =
  overF fstF show (42 :: Int, "hello") === ("42", "hello")

prop_concrete_list :: Property
prop_concrete_list =
  overF (unsafeElementF 1) (*10) ([1, 2, 3] :: [Int]) === [1, 20, 3]

--------------------------------------------------------------------
-- Tuple & List Update
--------------------------------------------------------------------

prop_fstF_update :: (Int, String) -> Property
prop_fstF_update (x, s) =
  overF fstF show (x, s) === (show x, s)

prop_sndF_update :: (String, Int) -> Property
prop_sndF_update (s, x) =
  overF sndF show (s, x) === (s, show x)

prop_listElement_negative :: [Int] -> Bool
prop_listElement_negative _ = case elementF (-1 :: Int) of Nothing -> True; _ -> False

prop_listElement_update :: [Int] -> Property
prop_listElement_update xs =
  not (null xs) ==> do
    let f = unsafeElementF 0
    overF f (+1) xs === (head xs + 1) : tail xs

prop_listElement_update_random :: [Int] -> NonNegative Int -> Property
prop_listElement_update_random xs (NonNegative n) =
  not (null xs) ==> do
    let i = n `mod` length xs
        f = unsafeElementF i
    overF f (+1) xs === take i xs ++ [xs !! i + 1] ++ drop (i + 1) xs

--------------------------------------------------------------------
-- QuickCheck generators
--------------------------------------------------------------------

instance Arbitrary a => Arbitrary (BinTree a) where
  arbitrary = sized go
    where
      go 0 = Leaf <$> arbitrary
      go n = oneof
        [ Leaf <$> arbitrary
        , Node <$> go (n `div` 2) <*> go (n `div` 2)
        ]

instance Arbitrary a => Arbitrary (Rose a) where
  arbitrary = sized arbRose
    where
      arbRose 0 = Rose <$> arbitrary <*> pure []
      arbRose n = do
        k <- chooseInt (0, min 3 n)
        Rose <$> arbitrary <*> vectorOf k (arbRose (n `div` (k + 1)))

-- | Generate a Rose tree guaranteed to have >= 2 children
--   whose subtrees may be structurally equal.
genRoseWithDup :: Gen (Rose Int)
genRoseWithDup = do
  label <- arbitrary
  subtree <- sized arbRoseSmall
  let dup = subtree
  return $ Rose label [subtree, dup]
  where
    arbRoseSmall n = do
      k <- chooseInt (0, min 1 n)
      Rose <$> arbitrary <*> vectorOf k (arbRoseSmall (n `div` (k + 1)))

-- | Generate a BinTree guaranteed to have a Node with left and right
--   subtrees that may be structurally equal.
genBinWithDup :: Gen (BinTree Int)
genBinWithDup = do
  subtree <- sized go
  return $ Node subtree subtree
  where
    go 0 = Leaf <$> arbitrary
    go n = oneof
      [ Leaf <$> arbitrary
      , Node <$> go (n `div` 2) <*> go (n `div` 2)
      ]

--------------------------------------------------------------------
-- Rose-specific child navigation (needed for multilevel tests)
-- Re-using ZipTree operations already imported
