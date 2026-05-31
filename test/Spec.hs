{-# OPTIONS_GHC -Wno-orphans #-}

module Main (main) where

import Test.Tasty
import Test.Tasty.QuickCheck

import Focal.Core
import Focal.Tuple
import Focal.List
import Focal.Zipper

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Focal Laws"
  [ testGroup "Core — Reconstruction"
      [ testProperty "idF reconstruction"                prop_idF_reconstruction
      , testProperty "overF idF id == id"                prop_overF_id
      , testProperty "overF fstF id == id"               prop_overF_id_fst
      , testProperty "overF sndF id == id"               prop_overF_id_snd
      , testProperty "composition plug law"              prop_composeF_plug
      , testProperty "store roundtrip (idF)"             prop_store_roundtrip
      ]
  , testGroup "Core — Composition Identity"
      [ testProperty "idF >>> f  ≈  f  (behavioural)"   prop_comp_identity_left
      , testProperty "f >>> idF  ≈  f  (behavioural)"   prop_comp_identity_right
      ]
  , testGroup "Core — Composition Associativity"
      [ testProperty "(f >>> g) >>> h  ≈  f >>> (g >>> h)" prop_compose_assoc
      ]
  , testGroup "Tuple"
      [ testProperty "fstF update preserves snd"         prop_fstF_update
      , testProperty "sndF update preserves fst"         prop_sndF_update
      ]
  , testGroup "List"
      [ testProperty "elementF negative = Nothing"       prop_listElement_negative
      , testProperty "unsafeElementF update (first)"     prop_listElement_update
      , testProperty "unsafeElementF update (random)"    prop_listElement_update_random
      ]
  , testGroup "Zipper — Descend/Ascend"
      [ testProperty "Rose descend/ascend roundtrip"      prop_rose_roundtrip
      , testProperty "BinTree descend/ascend roundtrip"   prop_bintree_roundtrip
      ]
  , testGroup "Zipper — Up/Down"
      [ testProperty "Rose up/down preserves current"     prop_rose_updown
      , testProperty "fromZip store roundtrip"            prop_fromZip_roundtrip
      ]
  , testGroup "Zipper — safeFocusAt"
      [ testProperty "valid path returns focus"           prop_safeFocusAt_valid
      , testProperty "invalid path returns Nothing"       prop_safeFocusAt_invalid
      ]
  , testGroup "Concrete Examples"
      [ testProperty "overF fstF show (42, \"hello\")"    prop_concrete_tuple
      , testProperty "overF (unsafeElementF 1) (*10) [1,2,3]" prop_concrete_list
      ]
  ]

-- ---------------------------------------------------------------------------
-- Core — Reconstruction
-- ---------------------------------------------------------------------------

-- | Putting the original focus back with the original residual
--   should restore the original whole.
prop_idF_reconstruction :: Int -> Bool
prop_idF_reconstruction s =
  let (focus, ctx) = splitF idF s
  in plugF idF ctx focus == s

-- | Applying the identity function through overF should be a no-op.
prop_overF_id :: Int -> Bool
prop_overF_id s = overF idF id s == s

-- | No-op update with fstF: replacing the focus with itself preserves the pair.
prop_overF_id_fst :: (Int, Int) -> Bool
prop_overF_id_fst p = overF fstF id p == p

-- | No-op update for sndF should be identity.
prop_overF_id_snd :: (Int, String) -> Bool
prop_overF_id_snd s = overF sndF id s == s

-- | The plug law for composition:
--   plugF (composeF f g) (c1, c2) y  ==  plugF f c1 (plugF g c2 y)
prop_composeF_plug :: (Int, Int) -> Int -> Bool
prop_composeF_plug pair y =
  let f   = fstF
      g   = idF
      (_, (c1, c2)) = splitF (composeF f g) pair
  in plugF (composeF f g) (c1, c2) y == plugF f c1 (plugF g c2 y)

-- | toStoreLike should produce a view/set pair that matches splitF/plugF.
prop_store_roundtrip :: Int -> Bool
prop_store_roundtrip s =
  let (a, set) = toStoreLike idF s
  in set a == s

-- ---------------------------------------------------------------------------
-- Core — Composition Identity
-- ---------------------------------------------------------------------------

-- | idF >>> f should behave the same as f.
--   We test this for the homogenous specialisation of fstF (where a=b=x=Int)
--   because (>>>) requires the inner types to align.
prop_comp_identity_left :: (Int, Int) -> Bool
prop_comp_identity_left pair =
  let f = fstF
  in overF (idF >>> f) id pair == overF f id pair

-- | f >>> idF should behave the same as f (same homogenous constraint).
prop_comp_identity_right :: (Int, Int) -> Bool
prop_comp_identity_right pair =
  let f = fstF
  in overF (f >>> idF) id pair == overF f id pair

-- | Composition associativity: (f >>> g) >>> h ≃ f >>> (g >>> h)
prop_compose_assoc :: Int -> Bool
prop_compose_assoc s =
  let f = idF
      g = idF
      h = idF
      left  = (f >>> g) >>> h
      right = f >>> (g >>> h)
  in overF left id s == overF right id s

-- ---------------------------------------------------------------------------
-- Tuple
-- ---------------------------------------------------------------------------

prop_fstF_update :: (Int, String) -> Property
prop_fstF_update (x, s) =
  overF fstF show (x, s) === (show x, s)

prop_sndF_update :: (String, Int) -> Property
prop_sndF_update (s, x) =
  overF sndF show (s, x) === (s, show x)

-- ---------------------------------------------------------------------------
-- List
-- ---------------------------------------------------------------------------

-- | Negative indices always return Nothing.
prop_listElement_negative :: [Int] -> Bool
prop_listElement_negative _ = case elementF (-1 :: Int) of Nothing -> True; _ -> False

-- | Updating the first element via unsafeElementF 0.
prop_listElement_update :: [Int] -> Property
prop_listElement_update xs =
  not (null xs) ==> do
    let f = unsafeElementF 0
    overF f (+1) xs === (head xs + 1) : tail xs

-- | Updating a random valid element via unsafeElementF.
prop_listElement_update_random :: [Int] -> NonNegative Int -> Property
prop_listElement_update_random xs (NonNegative n) =
  not (null xs) ==> do
    let i = n `mod` length xs
        f = unsafeElementF i
    overF f (+1) xs === take i xs ++ [xs !! i + 1] ++ drop (i + 1) xs

-- ---------------------------------------------------------------------------
-- Zipper — Descend/Ascend
-- ---------------------------------------------------------------------------

-- | For a Rose tree: descend to a child, then ascend with the frame
--   should return the original parent.
prop_rose_roundtrip :: Rose Int -> Property
prop_rose_roundtrip t@(Rose _ kids) =
  not (null kids) ==> do
    let Just (child, frame) = descend (0 :: Int) t
    ascend frame child === t

-- | For a BinTree: descend to left child, then ascend should return original.
--   Leaves trivially pass (they have no children to descend into).
prop_bintree_roundtrip :: BinTree Int -> Property
prop_bintree_roundtrip t@(Node _ _) =
  let Just (child, frame) = descend GoLeft t
  in ascend frame child === t
prop_bintree_roundtrip Leaf{} = property True

-- ---------------------------------------------------------------------------
-- Zipper — Up/Down
-- ---------------------------------------------------------------------------

-- | Down then up should return a zipper whose current focus is unchanged.
prop_rose_updown :: Rose Int -> Property
prop_rose_updown t@(Rose _ kids) =
  not (null kids) ==> do
    let z       = rootZip t
        Just z' = down (0 :: Int) z
        Just z'' = up z'
    current z'' === current z

-- | Converting a zipper to a Focusing and round-tripping through splitF/plugF
--   should rebuild the original tree.
prop_fromZip_roundtrip :: Rose Int -> Property
prop_fromZip_roundtrip t@(Rose _ kids) =
  not (null kids) ==> do
    let Just z        = down (0 :: Int) (rootZip t)
        f             = fromZip z
        (focus, ctx)  = splitF f t
    plugF f ctx focus === t

-- ---------------------------------------------------------------------------
-- Zipper — safeFocusAt
-- ---------------------------------------------------------------------------

-- | safeFocusAt on a valid path should produce a Focusing whose splitF
--   extracts the correct child.
prop_safeFocusAt_valid :: Rose Int -> Property
prop_safeFocusAt_valid t@(Rose _ kids) =
  not (null kids) ==> do
    case safeFocusAt [0 :: Int] t of
      Nothing -> property False
      Just f  ->
        let (focus, _) = splitF f t
        in focus === head kids

-- | safeFocusAt on an invalid (negative) path should return Nothing.
prop_safeFocusAt_invalid :: Rose Int -> Bool
prop_safeFocusAt_invalid t =
  case safeFocusAt [(-1 :: Int)] t of Nothing -> True; _ -> False

-- ---------------------------------------------------------------------------
-- Concrete Examples
-- ---------------------------------------------------------------------------

prop_concrete_tuple :: Property
prop_concrete_tuple =
  overF fstF show (42 :: Int, "hello") === ("42", "hello")

prop_concrete_list :: Property
prop_concrete_list =
  overF (unsafeElementF 1) (*10) ([1, 2, 3] :: [Int]) === [1, 20, 3]

-- ---------------------------------------------------------------------------
-- QuickCheck instances for custom types defined in Focal.Zipper
-- ---------------------------------------------------------------------------

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
