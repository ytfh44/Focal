{-# LANGUAGE RankNTypes #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Main (main) where

import Control.Exception (ErrorCall, evaluate, try)
import Control.Monad.State (State, get, put, runState)
import Data.List (isInfixOf)
import Data.Maybe (isNothing)
import Test.Tasty
import Test.Tasty.QuickCheck

import Focal.Core
import Focal.Tuple
import Focal.List
import Focal.Zipper
import Focal.Interop
import Focal.Partial
import Focal.Effectful

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Focal — Law & Contract Coverage (see docs/conformance.md)"
  [ testGroup "L-GP — Split-plug reconstruction"
      [ testProperty "idF: plug (splitF s) = s" prop_lgp_idF
      , testProperty "fstF: plug (splitF pair) = pair" prop_lgp_fstF
      , testProperty "sndF: plug (splitF pair) = pair" prop_lgp_sndF
      , testProperty "elementF: plug (splitF xs) = xs" prop_lgp_list
      , testProperty "Rose fromZip: plug (splitF t) = t" prop_lgp_roseZip
      , testProperty "BinTree fromZip: plug (splitF t) = t" prop_lgp_binZip
      , testProperty "pureF lawful pair: plug (splitF s) = s" prop_lgp_pureF
      , testProperty "composed: plug (splitF pair) = pair" prop_lgp_composed
      ]
  , testGroup "L-PG — Retrieve"
      [ testProperty "idF: re-split after plug recovers b" prop_lpg_idF
      , testProperty "fstF: re-split after plug recovers b" prop_lpg_fstF
      , testProperty "sndF: re-split after plug recovers b" prop_lpg_sndF
      , testProperty "userLens: re-split after plug recovers b" prop_lpg_userLens
      , testProperty "elementF: re-split after plug recovers b" prop_lpg_elementF
      , testProperty "unsafeElementF: re-split after plug recovers b" prop_lpg_unsafeElementF
      , testProperty "composed: re-split after plug recovers b" prop_lpg_composed
      ]
  , testGroup "L-PP — Overwrite stability"
      [ testProperty "idF: plug c' b2 = plug c b2" prop_lpp_idF
      , testProperty "fstF: plug c' b2 = plug c b2" prop_lpp_fstF
      , testProperty "userLens: plug c' b2 = plug c b2" prop_lpp_userLens
      , testProperty "elementF: plug c' b2 = plug c b2" prop_lpp_list
      , testProperty "fromZip: trivially stable (constant residual)" prop_lpp_fromZip
      ]
  , testGroup "L-OVF — overF homomorphism"
      [ testProperty "fstF: overF (g . h) = overF g . overF h" prop_lovf_fstF
      , testProperty "sndF: overF (g . h) = overF g . overF h" prop_lovf_sndF
      , testProperty "elementF: overF (g . h) = overF g . overF h" prop_lovf_list
      , testProperty "composed: overF (g . h) = overF g . overF h" prop_lovf_composed
      ]
  , testGroup "L-ASSOC — Composition associativity"
      [ testProperty "idF chain: behavioural equivalence" prop_lassoc_idChain
      , testProperty "tuple chain: mixed focus type" prop_lassoc_tupleChain
      , testProperty "list into tuple composition" prop_lassoc_listTupleChain
      ]
  , testGroup "L-UNIT — Identity"
      [ testProperty "idF >>> fstF = fstF" prop_lunit_left_fst
      , testProperty "idF >>> elementF = elementF" prop_lunit_left_list
      , testProperty "idF >>> fromZip = fromZip" prop_lunit_left_zipper
      , testProperty "fstF >>> idF = fstF" prop_lunit_right_fst
      , testProperty "elementF >>> idF = elementF" prop_lunit_right_list
      , testProperty "fromZip >>> idF = fromZip" prop_lunit_right_zipper
      ]
  , testGroup "Occurrence ≠ value — corollary of L-GP"
      [ testProperty "list: equal values at different indices" prop_occ_list
      , testProperty "Rose: equal subtrees at different paths" prop_occ_rose
      , testProperty "BinTree: equal leaves at different paths" prop_occ_binTree
      ]
  , testGroup "ZipTree law & navigation"
      [ testProperty "Rose: ascend frame (descend c t) = t" prop_zip_roseRoundtrip
      , testProperty "BinTree: ascend frame (descend c t) = t" prop_zip_binRoundtrip
      , testProperty "Rose: up (down c z) preserves current" prop_zip_updown
      , testProperty "Rose: up (rootZip t) = Nothing" prop_zip_rootUp
      , testProperty "Rose: multi-level navigation preserves context" prop_zip_multilevel
      ]
  , testGroup "Snapshot contracts (fromZip)"
      [ testProperty "fromZip: splitF ignores the input tree" prop_contract_zip_ignoresInput
      , testProperty "fromZip: re-split returns the captured focus" prop_contract_zip_pgCaptured
      ]
  , testGroup "Law discriminators — unlawful pureF pairs"
      [ testProperty "unlawful view: GP fails" prop_disc_pureF_gp
      , testProperty "unlawful set: PG fails" prop_disc_pureF_pg
      ]
  , testGroup "focusAt — dynamic zipper focus"
      [ testProperty "valid path extracts the child" prop_focusat_valid
      , testProperty "input-invariant: focus follows the supplied tree" prop_focusat_inputInvariant
      , testProperty "GP on the declared domain" prop_focusat_gp
      , testProperty "PG on the declared domain" prop_focusat_pg
      , testProperty "PP on the declared domain" prop_focusat_pp
      , testProperty "missing selector: Nothing" prop_focusat_missingSelector
      , testProperty "no children: Nothing" prop_focusat_noChildren
      , testProperty "path absent in a later tree: deferred error" prop_focusat_deferredError
      ]
  , testGroup "elementAt — checked list focus"
      [ testProperty "total on its domain: update at the index" prop_elementat_total
      , testProperty "out of domain: Nothing" prop_elementat_outOfDomain
      , testProperty "matches elementF" prop_elementat_matchesElementF
      ]
  , testGroup "elementE — failure-channel list focus"
      [ testProperty "negative index: Left (NegativeIndex n)" prop_elementE_negative
      , testProperty "index past the end: Left (PastEnd n)" prop_elementE_pastEnd
      , testProperty "in bounds: split returns the segments" prop_elementE_inBounds
      , testProperty "GP on the success domain" prop_elementE_lgp
      , testProperty "PG after a successful write" prop_elementE_lpg
      , testProperty "PP after a successful write" prop_elementE_lpp
      , testProperty "agrees with elementF on its domain" prop_elementE_matchesElementF
      ]
  , testGroup "L-NORM — canonical form (ROADMAP 0e)"
      [ testProperty "toVL (normalize f) = toVL f" prop_lnorm_toVL
      , testProperty "overFocal (normalize c) = overFocal c" prop_lnorm_overFocal
      ]
  , testGroup "L-TVL — toVL composition (ROADMAP 0e)"
      [ testProperty "composed list focus" prop_ltvl_composedList
      , testProperty "composed fst/fst focus" prop_ltvl_fstFst
      ]
  , testGroup "Concrete examples (regression)"
      [ testProperty "overF fstF show (42, \"hello\")" prop_concrete_tuple
      , testProperty "overF (unsafeElementF 1) (*10) [1,2,3]" prop_concrete_list
      ]
  , testGroup "elementF contract"
      [ testProperty "negative index: Nothing" prop_elementf_negative
      ]
  , testGroup "Edit independence (observation)"
      [ testProperty "independent foci commute" prop_obs_independentFoci
      ]
  , testGroup "L-GP — partial success domain (FocusingE)"
      [ testProperty "idE: plug (splitE s) = s" prop_lgpE_idE
      , testProperty "limitedE: plug (splitE s) = s on the domain" prop_lgpE_limited
      , testProperty "embedded fstF: plug (splitE pair) = pair" prop_lgpE_embedFstF
      ]
  , testGroup "L-PG — partial retrieve (FocusingE)"
      [ testProperty "limitedE: re-split after plug recovers b" prop_lpgE_limited
      , testProperty "embedded fstF: re-split after plug recovers b" prop_lpgE_embed
      ]
  , testGroup "L-PP — partial overwrite stability (FocusingE)"
      [ testProperty "limitedE: plug c' b2 = plug c b2 after a successful write" prop_lppE_limited
      , testProperty "composed limitedE: plug c' b2 = plug c b2 after a successful write" prop_lppE_composed
      ]
  , testGroup "L-OVF — partial homomorphism (FocusingE)"
      [ testProperty "limitedE: overE (g . h) = overE g . overE h on the success prefix" prop_lovfE_prefix
      ]
  , testGroup "FocusingE — failure channel (wiring)"
      [ testProperty "split failure skips the inner stage" prop_scE_splitShortCircuit
      , testProperty "plug runs inner-to-outer (outer plug skipped on inner failure)" prop_scE_plugOrder
      , testProperty "toPartial commutes with composeE" prop_embE_compose
      , testProperty "fromStoreE (toStoreE p) observes like p" prop_storeE_roundtrip
      ]
  , testGroup "Law discriminators — partial (FocusingE)"
      [ testProperty "unconditional PP needs the success premise" prop_discE_ppNeedsSuccess
      , testProperty "unconditional OVF is false" prop_discE_uncondOVF
      ]
  , testGroup "FocusingM — effectful laws (success / effect conditions)"
      [ testProperty "logM: GP (no-op update is pure)" prop_lgpM_log
      , testProperty "absM: GP" prop_lgpM_abs
      , testProperty "checkedM: GP on the domain (s >= 0)" prop_lgpM_checkedDomain
      , testProperty "restoreM: GP at every initial state" prop_lgpM_restore
      , testProperty "logM: PG (continuation form)" prop_lpgM_log
      , testProperty "absM: PG (continuation form)" prop_lpgM_abs
      , testProperty "checkedM: PG (continuation form)" prop_lpgM_checked
      , testProperty "restoreM: PG (continuation form, all states)" prop_lpgM_restore
      , testProperty "restoreM: PP (replay-prefix form)" prop_lppM_restore
      , testProperty "checkedM: PP (replay-prefix form)" prop_lppM_checked
      ]
  , testGroup "FocusingM — composition, unit, embedding, store"
      [ testProperty "GP preserved: composeM logM logM" prop_compM_gp_log
      , testProperty "GP preserved: composeM restoreM restoreM" prop_compM_gp_restore
      , testProperty "idM >>> logM observes like logM" prop_lunitM_log
      , testProperty "associativity: (logM >>> logM) >>> logM" prop_lassocM_log
      , testProperty "storeM/fromStoreM roundtrip (logM)" prop_storeM_roundtrip_log
      , testProperty "toEffectful embedding: fstF no-op rebuild" prop_embM_pure
      , testProperty "toEffectfulE agrees with overE (elementE)" prop_embME_agree
      ]
  , testGroup "Law discriminators — effectful (FocusingM)"
      [ testProperty "bare PG (effects must vanish) is false" prop_discM_barePg
      , testProperty "prefix-less PP is false with effects (logM)" prop_discM_ppLog
      , testProperty "prefix-less PP is false for partial plugs" prop_discM_ppPartial
      , testProperty "replay-prefix PP is false for logging" prop_discM_ppReplayLog
      , testProperty "replay-prefix PP is false for sign-flipping residuals" prop_discM_ppReplayAbs
      ]
  , testGroup "Residual shape — reassociation (ROADMAP 7a)"
      [ testProperty "unflatten (flatten ((a,b),c)) = ((a,b),c)" prop_flatten_inverse
      , testProperty "flatten (unflatten (a,(b,c))) = (a,(b,c))" prop_unflatten_inverse
      ]
  , testGroup "Type-changing fragment (ROADMAP 33)"
      [ testProperty "fstF: split form at s ≠ t, a ≠ b" prop_tc_fstF_split
      , testProperty "fstF: plug form" prop_tc_fstF_plug
      , testProperty "sndF: split form" prop_tc_sndF_split
      , testProperty "sndF: plug form" prop_tc_sndF_plug
      , testProperty "composed chain: overF show" prop_tc_composed
      ]
  , testGroup "focusAtE — failure-channel dynamic focus (ROADMAP 34)"
      [ testProperty "valid path extracts the child" prop_focusatE_validPath
      , testProperty "path not takeable: Left (PathError i)" prop_focusatE_offTree
      , testProperty "path absent in a later tree: Left (PathError i)" prop_focusatE_laterMissing
      , testProperty "GP on the success domain" prop_focusatE_gp
      , testProperty "plugE ctx b = Right (rebuild b ctx)" prop_focusatE_plug
      ]
  ]

--------------------------------------------------------------------
-- Shared definitions
--------------------------------------------------------------------

data User = User { userFirst :: String, userLast :: String }
  deriving (Eq, Show)

-- | Non-trivial lawful lens (record update), for the conditional-obligation tests.
userLens :: Focusing User User User String String
userLens = fromLensLike userFirst (\u v -> u { userFirst = v })

-- | Unlawful pairs (deliberate), used by the discriminator tests.
badSetLens :: Focusing User User User String String
badSetLens = fromLensLike userFirst (\u _ -> u)

badViewLens :: Focusing User User User String String
badViewLens = fromLensLike (const "") (\u v -> u { userFirst = v })

-- | Index into a non-empty list, drawn from a generated @NonNegative@.
listIndex :: [Int] -> NonNegative Int -> Int
listIndex xs (NonNegative n) = n `mod` length xs

--------------------------------------------------------------------
-- FocusingE fixtures (failure channel)
--------------------------------------------------------------------

-- | Lawful on its success domain: split and plug reject values outside
--   @0 <= _ <= cap@.
limitedE :: Int -> FocusingE String Int Int Int Int Int
limitedE cap = FocusingE
  { splitE = \s -> if s < 0 || s > cap
                    then Left "split out of range"
                    else Right (s, s)
  , plugE  = \_ b -> if b < 0 || b > cap
                      then Left "plug out of range"
                      else Right b
  }

-- | Behavioural observation of a partial focus: focus and putback outcome.
observeE :: FocusingE e c s t a b -> s -> b -> Either e (a, Either e t)
observeE p s b = fmap (\(a, k) -> (a, k b)) (toStoreE p s)

-- | Failure-wiring fixtures. The @explode*E@ legs crash if evaluated, so the
--   short-circuit tests fail loudly when the ordering is wrong.
splitFailE :: FocusingE String () Int Int Int Int
splitFailE = FocusingE
  { splitE = \_ -> Left "split-first"
  , plugE  = \() b -> Right b
  }

explodeSplitE :: FocusingE String () Int Int Int Int
explodeSplitE = FocusingE
  { splitE = \_ -> error "split must not run"
  , plugE  = \_ _ -> error "plug must not run"
  }

explodePlugE :: FocusingE String () Int Int Int Int
explodePlugE = FocusingE
  { splitE = \s -> Right (s, ())
  , plugE  = \_ _ -> error "outer plug must not run"
  }

-- | Inner leg whose plug always fails.
plugFailE :: FocusingE String () Int Int Int Int
plugFailE = FocusingE
  { splitE = \s -> Right (s, ())
  , plugE  = \() _ -> Left "plug-first"
  }

--------------------------------------------------------------------
-- FocusingM fixtures (effectful rebuild)
--------------------------------------------------------------------

type Log = (,) [String]

-- | Logging lens: the log records every actual change of the focused value
--   (a non-commutative monoid, so replay order is observable).
logM :: FocusingM Log Int Int Int Int Int
logM = FocusingM
  { splitM = \s -> ([], (s, s))
  , plugM  = \c b -> (if c /= b then ["changed " ++ show c ++ "->" ++ show b] else [], b)
  }

-- | Partial absolute-value lens (Maybe): fails on a negative replacement.
absM :: FocusingM Maybe Int Int Int Int Int
absM = FocusingM
  { splitM = \s -> Just (abs s, s)
  , plugM  = \c b -> if b < 0 then Nothing else Just (if c < 0 then negate b else b)
  }

-- | Checked lens (Either): declared domain @s >= 0@ for split and @b >= 0@
--   for plug; plug ignores the residual, so PP holds on successful writes.
checkedM :: FocusingM (Either String) Int Int Int Int Int
checkedM = FocusingM
  { splitM = \s -> if s < 0 then Left "split: negative" else Right (s, s)
  , plugM  = \_ b -> if b < 0 then Left "plug: negative" else Right b
  }

-- | Stateful restore lens: the residual snapshots the state; a successful
--   write restores the snapshot, so a replay cannot be observed.
restoreM :: FocusingM (State Bool) Bool Int Int Int Int
restoreM = FocusingM
  { splitM = \s -> do
      st <- get
      pure (s, st)
  , plugM = \c b -> do
      st <- get
      if st /= c then put c else pure ()
      pure b
  }

-- | Run a state action from both initial states and compare.
stEqM :: Eq x => State Bool x -> State Bool x -> Bool
stEqM a b = and [runState a st == runState b st | st <- [True, False]]

--------------------------------------------------------------------
-- L-GP — Split-plug reconstruction
--   let (a, c) = splitF f s in plugF f c a == s
--------------------------------------------------------------------

prop_lgp_idF :: Int -> Bool
prop_lgp_idF s =
  let (focus, ctx) = splitF idF s
  in plugF idF ctx focus == s

prop_lgp_fstF :: (Int, Int) -> Bool
prop_lgp_fstF pair =
  let (focus, ctx) = splitF fstF pair
  in plugF fstF ctx focus == pair

prop_lgp_sndF :: (Int, Int) -> Bool
prop_lgp_sndF pair =
  let (focus, ctx) = splitF sndF pair
  in plugF sndF ctx focus == pair

prop_lgp_list :: [Int] -> NonNegative Int -> Property
prop_lgp_list xs (NonNegative n) =
  not (null xs) ==> do
    let i = n `mod` length xs
        f = unsafeElementF i
        (focus, ctx) = splitF f xs
    plugF f ctx focus === xs

prop_lgp_roseZip :: Rose Int -> Property
prop_lgp_roseZip t@(Rose _ kids) =
  not (null kids) ==>
    case down (0 :: Int) (rootZip t) of
      Nothing -> property False
      Just z ->
        let f = fromZip z
            (focus, ctx) = splitF f t
        in plugF f ctx focus === t

prop_lgp_binZip :: BinTree Int -> Property
prop_lgp_binZip t@(Node _ _) =
  case down GoLeft (rootZip t) of
    Nothing -> property False
    Just z ->
      let f = fromZip z
          (focus, ctx) = splitF f t
      in plugF f ctx focus === t
prop_lgp_binZip Leaf{} = property True

prop_lgp_pureF :: Int -> Bool
prop_lgp_pureF s =
  let f = pureF id (\_ b -> b)
      (focus, ctx) = splitF f s
  in plugF f ctx focus == s

prop_lgp_composed :: ([Int], String) -> Property
prop_lgp_composed pair =
  not (null (fst pair)) ==> do
    let f = fstF >>> unsafeElementF 0
        (focus, ctx) = splitF f pair
    plugF f ctx focus === pair

--------------------------------------------------------------------
-- L-PG — Retrieve
--   let c = snd (splitF f s) in fst (splitF f (plugF f c b)) == b
--------------------------------------------------------------------

prop_lpg_idF :: Int -> Int -> Bool
prop_lpg_idF s b =
  let c = snd (splitF idF s)
  in fst (splitF idF (plugF idF c b)) == b

prop_lpg_fstF :: (Int, Int) -> Int -> Bool
prop_lpg_fstF p x =
  let c = snd (splitF fstF p)
  in fst (splitF fstF (plugF fstF c x)) == x

prop_lpg_sndF :: (Int, Int) -> Int -> Bool
prop_lpg_sndF p x =
  let c = snd (splitF sndF p)
  in fst (splitF sndF (plugF sndF c x)) == x

prop_lpg_userLens :: String -> String -> String -> Bool
prop_lpg_userLens f0 l0 b =
  let u = User f0 l0
      c = snd (splitF userLens u)
  in fst (splitF userLens (plugF userLens c b)) == b

prop_lpg_elementF :: [Int] -> NonNegative Int -> Int -> Property
prop_lpg_elementF xs nn b =
  not (null xs) ==>
    case elementF (listIndex xs nn) of
      Nothing -> property False
      Just f ->
        let c = snd (splitF f xs)
        in fst (splitF f (plugF f c b)) === b

prop_lpg_unsafeElementF :: [Int] -> NonNegative Int -> Int -> Property
prop_lpg_unsafeElementF xs nn b =
  not (null xs) ==>
    let f = unsafeElementF (listIndex xs nn)
        c = snd (splitF f xs)
    in fst (splitF f (plugF f c b)) === b

prop_lpg_composed :: ([Int], String) -> Int -> Property
prop_lpg_composed pair b =
  not (null (fst pair)) ==>
    let f = fstF >>> unsafeElementF 0
        c = snd (splitF f pair)
    in fst (splitF f (plugF f c b)) === b

--------------------------------------------------------------------
-- L-PP — Overwrite stability
--   plugF f (snd (splitF f (plugF f c b1))) b2 == plugF f c b2
--------------------------------------------------------------------

prop_lpp_idF :: Int -> Int -> Int -> Bool
prop_lpp_idF s b1 b2 =
  let c = snd (splitF idF s)
      (_, c') = splitF idF (plugF idF c b1)
  in plugF idF c' b2 == plugF idF c b2

prop_lpp_fstF :: (Int, Int) -> Int -> Int -> Bool
prop_lpp_fstF p b1 b2 =
  let c = snd (splitF fstF p)
      (_, c') = splitF fstF (plugF fstF c b1)
  in plugF fstF c' b2 == plugF fstF c b2

prop_lpp_userLens :: String -> String -> String -> String -> Bool
prop_lpp_userLens f0 l0 b1 b2 =
  let u = User f0 l0
      c = snd (splitF userLens u)
      (_, c') = splitF userLens (plugF userLens c b1)
  in plugF userLens c' b2 == plugF userLens c b2

prop_lpp_list :: [Int] -> NonNegative Int -> Int -> Int -> Property
prop_lpp_list xs nn b1 b2 =
  not (null xs) ==>
    let f = unsafeElementF (listIndex xs nn)
        c = snd (splitF f xs)
        (_, c') = splitF f (plugF f c b1)
    in plugF f c' b2 === plugF f c b2

prop_lpp_fromZip :: Rose Int -> Rose Int -> Rose Int -> Property
prop_lpp_fromZip t@(Rose _ kids) b1 b2 =
  not (null kids) ==>
    case down (0 :: Int) (rootZip t) of
      Nothing -> property False
      Just z ->
        -- Trivial here: the snapshot residual is constant, so a re-split
        -- after plugging returns the same captured context (docs/conformance.md).
        let f = fromZip z
            c = snd (splitF f t)
            (_, c') = splitF f (plugF f c b1)
        in plugF f c' b2 === plugF f c b2

--------------------------------------------------------------------
-- L-OVF — overF homomorphism
--   overF f (g . h) s == overF f g (overF f h s)
--------------------------------------------------------------------

prop_lovf_fstF :: (Int, Int) -> Fun Int Int -> Fun Int Int -> Property
prop_lovf_fstF pair g h =
  overF fstF (applyFun g . applyFun h) pair
    === overF fstF (applyFun g) (overF fstF (applyFun h) pair)

prop_lovf_sndF :: (Int, Int) -> Fun Int Int -> Fun Int Int -> Property
prop_lovf_sndF pair g h =
  overF sndF (applyFun g . applyFun h) pair
    === overF sndF (applyFun g) (overF sndF (applyFun h) pair)

prop_lovf_list :: [Int] -> NonNegative Int -> Fun Int Int -> Fun Int Int -> Property
prop_lovf_list xs nn g h =
  not (null xs) ==>
    let f = unsafeElementF (listIndex xs nn)
    in overF f (applyFun g . applyFun h) xs
         === overF f (applyFun g) (overF f (applyFun h) xs)

prop_lovf_composed :: ([Int], String) -> Fun Int Int -> Fun Int Int -> Property
prop_lovf_composed pair g h =
  not (null (fst pair)) ==>
    let f = fstF >>> unsafeElementF 0
    in overF f (applyFun g . applyFun h) pair
         === overF f (applyFun g) (overF f (applyFun h) pair)

--------------------------------------------------------------------
-- L-ASSOC — Composition associativity
--------------------------------------------------------------------

prop_lassoc_idChain :: Int -> Bool
prop_lassoc_idChain s =
  let left  = (idF >>> idF) >>> idF
      right = idF >>> (idF >>> idF)
  in overF left id s == overF right id s

prop_lassoc_tupleChain :: (((Int, Int), String), Bool) -> Bool
prop_lassoc_tupleChain v =
  let f = fstF
      left  = (idF >>> f) >>> fstF
      right = idF >>> (f >>> fstF)
  in overF left id v == overF right id v

prop_lassoc_listTupleChain :: ([Int], String) -> Property
prop_lassoc_listTupleChain pair =
  not (null (fst pair)) ==> do
    let f = fstF
        g = unsafeElementF 0
        left  = (f >>> g) >>> idF
        right = f >>> (g >>> idF)
    overF left id pair === overF right id pair

--------------------------------------------------------------------
-- L-UNIT — Identity
--------------------------------------------------------------------

prop_lunit_left_fst :: (Int, Int) -> Bool
prop_lunit_left_fst pair =
  let f = fstF
  in overF (idF >>> f) id pair == overF f id pair

prop_lunit_left_list :: [Int] -> NonNegative Int -> Property
prop_lunit_left_list xs (NonNegative n) =
  not (null xs) ==> do
    let i = n `mod` length xs
        f = unsafeElementF i
    overF (idF >>> f) id xs === overF f id xs

prop_lunit_left_zipper :: Rose Int -> Property
prop_lunit_left_zipper t@(Rose _ kids) =
  not (null kids) ==>
    case down (0 :: Int) (rootZip t) of
      Nothing -> property False
      Just z ->
        let f = fromZip z
        in overF (idF >>> f) id t === overF f id t

prop_lunit_right_fst :: (Int, Int) -> Bool
prop_lunit_right_fst pair =
  let f = fstF
  in overF (f >>> idF) id pair == overF f id pair

prop_lunit_right_list :: [Int] -> NonNegative Int -> Property
prop_lunit_right_list xs (NonNegative n) =
  not (null xs) ==> do
    let i = n `mod` length xs
        f = unsafeElementF i
    overF (f >>> idF) id xs === overF f id xs

prop_lunit_right_zipper :: Rose Int -> Property
prop_lunit_right_zipper t@(Rose _ kids) =
  not (null kids) ==>
    case down (0 :: Int) (rootZip t) of
      Nothing -> property False
      Just z ->
        let f = fromZip z
        in overF (f >>> idF) id t === overF f id t

--------------------------------------------------------------------
-- Occurrence ≠ value — corollary of L-GP
--   Two different occurrences of the same value yield different residuals.
--------------------------------------------------------------------

prop_occ_list :: [Int] -> Property
prop_occ_list xs =
  length xs >= 2 ==> do
    let f0 = unsafeElementF 0
        f1 = unsafeElementF 1
        (a0, c0) = splitF f0 xs
        (a1, c1) = splitF f1 xs
    property $ if a0 == a1 then c0 /= c1 else True

prop_occ_rose :: Property
prop_occ_rose =
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

prop_occ_binTree :: Property
prop_occ_binTree =
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
-- ZipTree law & navigation
--------------------------------------------------------------------

prop_zip_roseRoundtrip :: Rose Int -> Property
prop_zip_roseRoundtrip t@(Rose _ kids) =
  not (null kids) ==>
    case descend (0 :: Int) t of
      Nothing -> property False
      Just (child, frame) -> ascend frame child === t

prop_zip_binRoundtrip :: BinTree Int -> Property
prop_zip_binRoundtrip t@(Node _ _) =
  case descend GoLeft t of
    Nothing -> property False
    Just (child, frame) -> ascend frame child === t
prop_zip_binRoundtrip Leaf{} = property True

prop_zip_updown :: Rose Int -> Property
prop_zip_updown t@(Rose _ kids) =
  not (null kids) ==>
    case down (0 :: Int) (rootZip t) of
      Nothing -> property False
      Just z' ->
        case up z' of
          Nothing -> property False
          Just z'' -> current z'' === current (rootZip t)

prop_zip_rootUp :: Rose Int -> Bool
prop_zip_rootUp t =
  case up (rootZip t) of
    Nothing -> True
    _       -> False

prop_zip_multilevel :: Rose Int -> Property
prop_zip_multilevel t@(Rose _ kids) =
  length kids >= 2 ==>
    case safeNavigate [0] t of
      Just (Zip (Rose _ grandKids) _) ->
        if not (null grandKids)
          then
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

--------------------------------------------------------------------
-- Snapshot contracts (fromZip)
--------------------------------------------------------------------

prop_contract_zip_ignoresInput :: Rose Int -> Rose Int -> Property
prop_contract_zip_ignoresInput t@(Rose _ kids) t' =
  not (null kids) ==>
    case down (0 :: Int) (rootZip t) of
      Nothing -> property False
      Just z ->
        let f = fromZip z
        in conjoin
             [ fst (splitF f t') === current z
             , snd (splitF f t') === context z
             ]

prop_contract_zip_pgCaptured :: Rose Int -> Rose Int -> Property
prop_contract_zip_pgCaptured t@(Rose _ kids) b =
  not (null kids) ==>
    case down (0 :: Int) (rootZip t) of
      Nothing -> property False
      Just z ->
        let f = fromZip z
            a = fst (splitF f t)
            c = snd (splitF f t)
        in fst (splitF f (plugF f c b)) === a

--------------------------------------------------------------------
-- Law discriminators — unlawful pureF pairs
--------------------------------------------------------------------

prop_disc_pureF_gp :: Bool
prop_disc_pureF_gp =
  let u0 = User "alice" "smith"
      a = fst (splitF badViewLens u0)
      c = snd (splitF badViewLens u0)
  in plugF badViewLens c a /= u0

prop_disc_pureF_pg :: Bool
prop_disc_pureF_pg =
  let u0 = User "alice" "smith"
      c = snd (splitF badSetLens u0)
  in fst (splitF badSetLens (plugF badSetLens c "bob")) /= "bob"

--------------------------------------------------------------------
-- focusAt — dynamic zipper focus
--------------------------------------------------------------------

prop_focusat_valid :: Rose Int -> Property
prop_focusat_valid t@(Rose _ kids) =
  not (null kids) ==>
    case focusAt [0 :: Int] t of
      Nothing -> property False
      Just f ->
        case kids of
          (k0:_) -> fst (splitF f t) === k0
          []     -> property False

prop_focusat_inputInvariant :: Rose Int -> Rose Int -> Property
prop_focusat_inputInvariant t1@(Rose _ kids1) t2@(Rose _ kids2) =
  (not (null kids1) && not (null kids2)) ==>
    case focusAt [0 :: Int] t1 of
      Nothing -> property False
      Just f ->
        case kids2 of
          (k2:_) -> fst (splitF f t2) === k2
          []     -> property False

prop_focusat_gp :: Rose Int -> Rose Int -> Property
prop_focusat_gp t0@(Rose _ kids0) t1@(Rose _ kids1) =
  (not (null kids0) && not (null kids1)) ==>
    case focusAt [0 :: Int] t0 of
      Nothing -> property False
      Just f -> plugF f (snd (splitF f t1)) (fst (splitF f t1)) === t1

prop_focusat_pg :: Rose Int -> Rose Int -> Property
prop_focusat_pg t@(Rose _ kids) b =
  not (null kids) ==>
    case focusAt [0 :: Int] t of
      Nothing -> property False
      Just f ->
        let c = snd (splitF f t)
        in fst (splitF f (plugF f c b)) === b

prop_focusat_pp :: Rose Int -> Rose Int -> Rose Int -> Property
prop_focusat_pp t@(Rose _ kids) b1 b2 =
  not (null kids) ==>
    case focusAt [0 :: Int] t of
      Nothing -> property False
      Just f ->
        let c = snd (splitF f t)
            (_, c') = splitF f (plugF f c b1)
        in plugF f c' b2 === plugF f c b2

prop_focusat_missingSelector :: Rose Int -> Bool
prop_focusat_missingSelector t =
  case focusAt [(-1) :: Int] t of
    Nothing -> True
    _       -> False

prop_focusat_noChildren :: Rose Int -> Property
prop_focusat_noChildren t@(Rose _ kids) =
  null kids ==>
    case focusAt [0 :: Int] t of
      Nothing -> property True
      _       -> property False

prop_focusat_deferredError :: Rose Int -> Property
prop_focusat_deferredError t@(Rose _ kids) =
  not (null kids) ==>
    case focusAt [0 :: Int] t of
      Nothing -> property False
      Just f ->
        ioProperty $ do
          r <- try (evaluate (fst (splitF f (Rose (0 :: Int) [])))) :: IO (Either ErrorCall (Rose Int))
          pure $ case r of
            Left e  -> "focusAt" `isInfixOf` show e
            Right _ -> False

--------------------------------------------------------------------
-- elementAt — checked list focus
--------------------------------------------------------------------

prop_elementat_total :: [Int] -> NonNegative Int -> Property
prop_elementat_total xs nn =
  not (null xs) ==>
    let i = listIndex xs nn
    in case elementAt i xs of
         Nothing -> property False
         Just f ->
           overF f (+1) xs === take i xs ++ [xs !! i + 1] ++ drop (i + 1) xs

prop_elementat_outOfDomain :: [Int] -> Bool
prop_elementat_outOfDomain xs =
  isNothing (elementAt (-1) xs) && isNothing (elementAt (length xs) xs)

prop_elementat_matchesElementF :: [Int] -> NonNegative Int -> Property
prop_elementat_matchesElementF xs nn =
  not (null xs) ==>
    let i = listIndex xs nn
    in fmap (\f -> overF f (+1) xs) (elementAt i xs)
         === fmap (\f -> overF f (+1) xs) (elementF i)

--------------------------------------------------------------------
-- L-NORM — canonical form (ROADMAP 0e)
--------------------------------------------------------------------

prop_lnorm_toVL :: (Int, Int) -> Fun Int Int -> Property
prop_lnorm_toVL s g =
  let f   = fstF :: Focusing Int (Int, Int) (Int, Int) Int Int
      foc = mkFocal f
      k x = Just (applyFun g x)
  in toVL (normalize foc) k s === toVL foc k s

prop_lnorm_overFocal :: ([Int], String) -> Fun Int Int -> Property
prop_lnorm_overFocal s g =
  not (null (fst s)) ==>
    let outer = mkFocal (fstF :: Focusing String ([Int], String) ([Int], String) [Int] [Int])
        inner = mkFocal (unsafeElementF 0)
        comp  = composeFocal outer inner
        h = applyFun g
    in overFocal (normalize comp) h s === overFocal comp h s

--------------------------------------------------------------------
-- L-TVL — toVL composition (ROADMAP 0e)
--------------------------------------------------------------------

prop_ltvl_composedList :: ([Int], String) -> Fun Int Int -> Property
prop_ltvl_composedList s g =
  not (null (fst s)) ==>
    let outer = mkFocal (fstF :: Focusing String ([Int], String) ([Int], String) [Int] [Int])
        inner = mkFocal (unsafeElementF 0)
        comp  = composeFocal outer inner
        k x = Just (applyFun g x)
    in toVL comp k s === toVL outer (toVL inner k) s

prop_ltvl_fstFst :: ((Int, Int), Int) -> Fun Int Int -> Property
prop_ltvl_fstFst s g =
  let outer = mkFocal (fstF :: Focusing Int ((Int, Int), Int) ((Int, Int), Int) (Int, Int) (Int, Int))
      inner = mkFocal (fstF :: Focusing Int (Int, Int) (Int, Int) Int Int)
      comp  = composeFocal outer inner
      k x = Just (applyFun g x)
  in toVL comp k s === toVL outer (toVL inner k) s

--------------------------------------------------------------------
-- Concrete examples (regression)
--------------------------------------------------------------------

prop_concrete_tuple :: Property
prop_concrete_tuple =
  overF fstF show (42 :: Int, "hello") === ("42", "hello")

prop_concrete_list :: Property
prop_concrete_list =
  overF (unsafeElementF 1) (*10) ([1, 2, 3] :: [Int]) === [1, 20, 3]

--------------------------------------------------------------------
-- elementF contract
--------------------------------------------------------------------

prop_elementf_negative :: [Int] -> Bool
prop_elementf_negative _ = isNothing (elementF (-1 :: Int))

--------------------------------------------------------------------
-- Edit independence (observation)
--------------------------------------------------------------------

prop_obs_independentFoci :: ([Int], [Int]) -> Property
prop_obs_independentFoci (xs, ys) =
  not (null xs) && not (null ys) ==> do
    let fLs = fstF >>> unsafeElementF 0
        fRs = sndF >>> unsafeElementF 0
        applyLsThenRs t = overF fLs (const 99) (overF fRs (const 77) t)
        applyRsThenLs t = overF fRs (const 77) (overF fLs (const 99) t)
        input = (xs, ys)
    applyLsThenRs input === applyRsThenLs input

--------------------------------------------------------------------
-- FocusingE — partial channel (success-premise laws)
--------------------------------------------------------------------

prop_lgpE_idE :: Int -> Bool
prop_lgpE_idE s = overE idE id s == (Right s :: Either String Int)

prop_lgpE_limited :: Int -> Bool
prop_lgpE_limited s =
  case splitE (limitedE 10) s of
    Left _       -> True
    Right (a, c) -> plugE (limitedE 10) c a == Right s

prop_lgpE_embedFstF :: (Int, Int) -> Bool
prop_lgpE_embedFstF p =
  overE (toPartial fstF) id p == (Right p :: Either String (Int, Int))

prop_lpgE_limited :: Int -> Int -> Bool
prop_lpgE_limited s b =
  case splitE (limitedE 10) s of
    Left _       -> True
    Right (_, c) -> case plugE (limitedE 10) c b of
      Left _       -> True
      Right t      -> case splitE (limitedE 10) t of
        Right (a', _) -> a' == b
        Left _        -> False

prop_lpgE_embed :: (Int, Int) -> Int -> Bool
prop_lpgE_embed p b =
  let f = toPartial (fstF :: Focusing Int (Int, Int) (Int, Int) Int Int)
            :: FocusingE String Int (Int, Int) (Int, Int) Int Int
  in case splitE f p of
       Left _       -> False
       Right (_, c) -> case plugE f c b of
         Left _       -> False
         Right t      -> case splitE f t of
           Right (a', _) -> a' == b
           Left _        -> False

prop_lppE_limited :: Int -> Int -> Int -> Bool
prop_lppE_limited s b1 b2 =
  case splitE (limitedE 10) s of
    Left _       -> True
    Right (_, c) -> case plugE (limitedE 10) c b1 of
      Left _          -> True
      Right t         -> case splitE (limitedE 10) t of
        Left _        -> False
        Right (_, c') -> plugE (limitedE 10) c' b2 == plugE (limitedE 10) c b2

prop_lppE_composed :: Int -> Int -> Int -> Bool
prop_lppE_composed s b1 b2 =
  let p = composeE (limitedE 10) (limitedE 10)
  in case splitE p s of
       Left _       -> True
       Right (_, c) -> case plugE p c b1 of
         Left _          -> True
         Right t         -> case splitE p t of
           Left _        -> False
           Right (_, c') -> plugE p c' b2 == plugE p c b2

prop_lovfE_prefix :: Int -> Fun Int Int -> Fun Int Int -> Bool
prop_lovfE_prefix s fg fh =
  let p = limitedE 10
      g = applyFun fg
      h = applyFun fh
  in case overE p h s of
       Left _  -> True
       Right t -> overE p (g . h) s == overE p g t

prop_scE_splitShortCircuit :: Bool
prop_scE_splitShortCircuit =
  overE (composeE splitFailE explodeSplitE) id 0 == Left "split-first"

prop_scE_plugOrder :: Bool
prop_scE_plugOrder =
  overE (composeE explodePlugE plugFailE) id 0 == Left "plug-first"

prop_embE_compose :: ((Int, Int), Bool) -> Bool
prop_embE_compose s =
  overE (toPartial (fstF >>> sndF)) (+1) s
    == (overE (composeE (toPartial fstF) (toPartial sndF)) (+1) s
          :: Either String ((Int, Int), Bool))

prop_storeE_roundtrip :: Int -> Int -> Bool
prop_storeE_roundtrip s b =
  observeE (limitedE 10) s b
    == observeE (fromStoreE (toStoreE (limitedE 10))) s b

prop_discE_ppNeedsSuccess :: Bool
prop_discE_ppNeedsSuccess =
  let p = limitedE 10
  in (overE p (const (-1)) 0 >>= overE p (const 2))
       /= overE p (const 2) 0

prop_discE_uncondOVF :: Bool
prop_discE_uncondOVF =
  let p = limitedE 10
  in overE p (const 2) 0
       /= (overE p (const (-1)) 0 >>= overE p (const 2))

--------------------------------------------------------------------
-- elementE — failure-channel list focus
--------------------------------------------------------------------

prop_elementE_negative :: [Int] -> Bool
prop_elementE_negative xs =
  splitE (elementE (-1)) xs
    == (Left (NegativeIndex (-1)) :: Either ListError (Int, ([Int], [Int])))

prop_elementE_pastEnd :: [Int] -> Bool
prop_elementE_pastEnd xs =
  splitE (elementE (length xs)) xs
    == (Left (PastEnd (length xs)) :: Either ListError (Int, ([Int], [Int])))

prop_elementE_inBounds :: [Int] -> NonNegative Int -> Property
prop_elementE_inBounds xs nn =
  not (null xs) ==>
    let i = listIndex xs nn
    in case splitAt i xs of
         (l, x : r) -> splitE (elementE i) xs === Right (x, (l, r))
         _          -> property False

prop_elementE_lgp :: [Int] -> NonNegative Int -> Property
prop_elementE_lgp xs nn =
  not (null xs) ==>
    let i = listIndex xs nn
    in case splitE (elementE i) xs of
         Left _       -> property False
         Right (a, c) -> plugE (elementE i) c a === Right xs

prop_elementE_lpg :: [Int] -> NonNegative Int -> Int -> Property
prop_elementE_lpg xs nn b =
  not (null xs) ==>
    let i = listIndex xs nn
    in case splitE (elementE i) xs of
         Left _       -> property False
         Right (_, c) -> case plugE (elementE i) c b of
           Left _        -> property True
           Right t       -> case splitE (elementE i) t of
             Right (a', _) -> a' === b
             Left _        -> property False

prop_elementE_lpp :: [Int] -> NonNegative Int -> Int -> Int -> Property
prop_elementE_lpp xs nn b1 b2 =
  not (null xs) ==>
    let i = listIndex xs nn
    in case splitE (elementE i) xs of
         Left _       -> property False
         Right (_, c) -> case plugE (elementE i) c b1 of
           Left _          -> property True
           Right t         -> case splitE (elementE i) t of
             Left _        -> property False
             Right (_, c') -> plugE (elementE i) c' b2 === plugE (elementE i) c b2

prop_elementE_matchesElementF :: [Int] -> NonNegative Int -> Property
prop_elementE_matchesElementF xs nn =
  not (null xs) ==>
    let i = listIndex xs nn
    in case elementF i of
         Nothing -> property False
         Just f  -> overE (elementE i) (+1) xs === Right (overF f (+1) xs)

--------------------------------------------------------------------
-- FocusingM — effectful laws (success / effect conditions)
--------------------------------------------------------------------

prop_lgpM_log :: Int -> Bool
prop_lgpM_log s = (splitM logM s >>= \(a, c) -> plugM logM c a) == ([], s)

prop_lgpM_abs :: Int -> Bool
prop_lgpM_abs s = (splitM absM s >>= \(a, c) -> plugM absM c a) == Just s

prop_lgpM_checkedDomain :: NonNegative Int -> Bool
prop_lgpM_checkedDomain (NonNegative s) =
  (splitM checkedM s >>= \(a, c) -> plugM checkedM c a) == Right s

prop_lgpM_restore :: Int -> Bool
prop_lgpM_restore s =
  stEqM (splitM restoreM s >>= \(a, c) -> plugM restoreM c a) (pure s)

prop_lpgM_log :: Int -> Int -> Bool
prop_lpgM_log c b =
  (do t <- plugM logM c b; (a', c') <- splitM logM t; pure (t, (a', c'), a'))
    == (do t <- plugM logM c b; (a', c') <- splitM logM t; pure (t, (a', c'), b))

prop_lpgM_abs :: Int -> Int -> Bool
prop_lpgM_abs c b =
  (do t <- plugM absM c b; (a', c') <- splitM absM t; pure (t, (a', c'), a'))
    == (do t <- plugM absM c b; (a', c') <- splitM absM t; pure (t, (a', c'), b))

prop_lpgM_checked :: Int -> Int -> Bool
prop_lpgM_checked c b =
  (do t <- plugM checkedM c b; (a', c') <- splitM checkedM t; pure (t, (a', c'), a'))
    == (do t <- plugM checkedM c b; (a', c') <- splitM checkedM t; pure (t, (a', c'), b))

prop_lpgM_restore :: Bool -> Int -> Bool
prop_lpgM_restore c b =
  stEqM (do t <- plugM restoreM c b; (a', c') <- splitM restoreM t; pure (t, (a', c'), a'))
        (do t <- plugM restoreM c b; (a', c') <- splitM restoreM t; pure (t, (a', c'), b))

prop_lppM_restore :: Bool -> Int -> Int -> Bool
prop_lppM_restore c b1 b2 =
  stEqM (do _ <- plugM restoreM c b1; plugM restoreM c b2)
        (do t <- plugM restoreM c b1; (_, c') <- splitM restoreM t; plugM restoreM c' b2)

prop_lppM_checked :: Int -> Int -> Int -> Bool
prop_lppM_checked c b1 b2 =
  (do _ <- plugM checkedM c b1; plugM checkedM c b2)
    == (do t <- plugM checkedM c b1; (_, c') <- splitM checkedM t; plugM checkedM c' b2)

--------------------------------------------------------------------
-- FocusingM — composition, unit, embedding, store
--------------------------------------------------------------------

prop_compM_gp_log :: Int -> Bool
prop_compM_gp_log s =
  let p = composeM logM logM
  in (splitM p s >>= \(a, c) -> plugM p c a) == ([], s)

prop_compM_gp_restore :: Int -> Bool
prop_compM_gp_restore s =
  let p = composeM restoreM restoreM
  in stEqM (splitM p s >>= \(a, c) -> plugM p c a) (pure s)

prop_lunitM_log :: Int -> Int -> Bool
prop_lunitM_log s b =
  fmap (\(a, k) -> (a, k b)) (storeM (composeM idM logM) s)
    == fmap (\(a, k) -> (a, k b)) (storeM logM s)

prop_lassocM_log :: Int -> Int -> Bool
prop_lassocM_log s b =
  let obs p = fmap (\(a, k) -> (a, k b)) (storeM p s)
  in obs (composeM (composeM logM logM) logM) == obs (composeM logM (composeM logM logM))

prop_storeM_roundtrip_log :: Int -> Int -> Bool
prop_storeM_roundtrip_log s b =
  fmap (\(a, k) -> (a, k b)) (storeM logM s)
    == fmap (\(a, k) -> (a, k b)) (storeM (fromStoreM (storeM logM)) s)

prop_embM_pure :: (Int, Bool) -> Bool
prop_embM_pure p =
  overM (toEffectful (fstF :: Focusing Bool (Int, Bool) (Int, Bool) Int Int)) id p
    == (Just p :: Maybe (Int, Bool))

prop_embME_agree :: [Int] -> NonNegative Int -> Property
prop_embME_agree xs nn =
  not (null xs) ==>
    let i = listIndex xs nn
    in overM (toEffectfulE (elementE i)) (+1) xs === overE (elementE i) (+1) xs

--------------------------------------------------------------------
-- Law discriminators — effectful (FocusingM)
--------------------------------------------------------------------

prop_discM_barePg :: Bool
prop_discM_barePg =
  (do t <- plugM logM 0 1; (a', _) <- splitM logM t; pure a') /= pure (1 :: Int)

prop_discM_ppLog :: Bool
prop_discM_ppLog =
  (do t <- plugM logM (-2) (-1); (_, c') <- splitM logM t; plugM logM c' (-2))
    /= plugM logM (-2) (-2)

prop_discM_ppPartial :: Bool
prop_discM_ppPartial =
  (do t <- plugM checkedM 0 (-1); (_, c') <- splitM checkedM t; plugM checkedM c' 5)
    /= plugM checkedM 0 5

prop_discM_ppReplayLog :: Bool
prop_discM_ppReplayLog =
  (do _ <- plugM logM 0 1; plugM logM 0 3)
    /= (do t <- plugM logM 0 1; (_, c') <- splitM logM t; plugM logM c' 3)

prop_discM_ppReplayAbs :: Bool
prop_discM_ppReplayAbs =
  (do _ <- plugM absM (-2) 0; plugM absM (-2) 1)
    /= (do t <- plugM absM (-2) 0; (_, c') <- splitM absM t; plugM absM c' 1)

--------------------------------------------------------------------
-- Residual shape — reassociation (ROADMAP 7a)
--------------------------------------------------------------------

prop_flatten_inverse :: Int -> Bool -> Char -> Bool
prop_flatten_inverse a b c =
  unflatten (flatten ((a, b), c)) == ((a, b), c)

prop_unflatten_inverse :: Int -> Bool -> Char -> Bool
prop_unflatten_inverse a b c =
  flatten (unflatten ((a, (b, c)) :: Residual3 Int Bool Char)) == (a, (b, c))

--------------------------------------------------------------------
-- Type-changing fragment (ROADMAP 33)
--------------------------------------------------------------------

prop_tc_fstF_split :: Int -> Bool -> Bool
prop_tc_fstF_split n c =
  splitF (fstF :: Focusing Bool (Int, Bool) (String, Bool) Int String) (n, c) == (n, c)

prop_tc_fstF_plug :: Bool -> String -> Bool
prop_tc_fstF_plug c s =
  plugF (fstF :: Focusing Bool (Int, Bool) (String, Bool) Int String) c s == (s, c)

prop_tc_sndF_split :: Int -> Bool -> Bool
prop_tc_sndF_split n c =
  splitF (sndF :: Focusing Int (Int, Bool) (Int, String) Bool String) (n, c) == (c, n)

prop_tc_sndF_plug :: Int -> String -> Bool
prop_tc_sndF_plug n s =
  plugF (sndF :: Focusing Int (Int, Bool) (Int, String) Bool String) n s == (n, s)

-- | A two-stage chain that changes both the whole and the focus types: the
--   second component of an outer pair, then the first component of the inner pair.
tcComposed :: Focusing (Int, Bool) (Int, (Int, Bool)) (Int, (String, Bool)) Int String
tcComposed = composeF
  (sndF :: Focusing Int (Int, (Int, Bool)) (Int, (String, Bool)) (Int, Bool) (String, Bool))
  (fstF :: Focusing Bool (Int, Bool) (String, Bool) Int String)

prop_tc_composed :: Int -> Int -> Bool -> Bool
prop_tc_composed n x c =
  overF tcComposed show (n, (x, c)) == (n, (show x, c))

--------------------------------------------------------------------
-- focusAtE — failure-channel dynamic focus (ROADMAP 34)
--------------------------------------------------------------------

-- | Number of leading path steps that can be taken in the supplied tree.
--   When the path does not exist in the tree this is the 0-based index of
--   the first failing step.
validPrefix :: [Int] -> Rose Int -> Int
validPrefix p t = go 0 p (rootZip t)
  where
    go i []       _ = i
    go i (c : cs) z = case down c z of
      Nothing -> i
      Just z' -> go (i + 1) cs z'

prop_focusatE_validPath :: Rose Int -> Property
prop_focusatE_validPath t =
  forAll (genPathIn t) $ \p ->
    case safeNavigate p t of
      Nothing -> property False
      Just z  ->
        splitE (focusAtE p) t === Right (current z, context z)

prop_focusatE_offTree :: Rose Int -> Property
prop_focusatE_offTree t =
  forAll (genOffTreePath t) $ \p ->
    isNothing (safeNavigate p t) ==>
      splitE (focusAtE p) t
        === (Left (PathError (validPrefix p t))
              :: Either PathError (Rose Int, [RoseFrame Int]))

prop_focusatE_laterMissing :: Rose Int -> Property
prop_focusatE_laterMissing t@(Rose _ kids) =
  not (null kids) ==>
    case focusAt [0 :: Int] t of
      Nothing -> property False
      Just _  ->
        splitE (focusAtE [0 :: Int]) (Rose (0 :: Int) [])
          === (Left (PathError 0) :: Either PathError (Rose Int, [RoseFrame Int]))

prop_focusatE_gp :: Rose Int -> Rose Int -> Property
prop_focusatE_gp (Rose _ kids0) t1 =
  not (null kids0) ==>
    let f = focusAtE [0 :: Int]
              :: FocusingE PathError [RoseFrame Int] (Rose Int) (Rose Int) (Rose Int) (Rose Int)
    in case splitE f t1 of
         Left _       -> property True
         Right (a, c) -> plugE f c a === Right t1

prop_focusatE_plug :: Rose Int -> Rose Int -> Property
prop_focusatE_plug t b =
  forAll (genPathIn t) $ \p ->
    case safeNavigate p t of
      Nothing -> property False
      Just z  ->
        let f = focusAtE []
                  :: FocusingE PathError [RoseFrame Int] (Rose Int) (Rose Int) (Rose Int) (Rose Int)
        in plugE f (context z) b === Right (rebuild b (context z))

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
  lbl <- arbitrary
  subtree <- sized arbRoseSmall
  let dup = subtree
  return $ Rose lbl [subtree, dup]
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

-- | Generate a path of child selections that exists in the supplied Rose tree
--   (a leaf yields the empty path, valid at the root).
genPathIn :: Rose Int -> Gen [Int]
genPathIn (Rose _ kids)
  | null kids = pure []
  | otherwise = do
      k <- chooseInt (0, length kids - 1)
      rest <- genPathIn (kids !! k)
      pure (k : rest)

-- | Generate a path that cannot be taken in the supplied Rose tree: some
--   (possibly empty) valid prefix, then one child selection that is out of
--   range (negative or @>= length kids@). The failing 0-based index is the
--   number of valid steps.
genOffTreePath :: Rose Int -> Gen [Int]
genOffTreePath = go []
  where
    go acc (Rose _ kids) = do
      extend <- if null kids then pure False else arbitrary
      if extend
        then do
          k <- chooseInt (0, length kids - 1)
          go (k : acc) (kids !! k)
        else do
          negative <- arbitrary
          bad <- if negative
                   then chooseInt (-1 - length kids, -1)
                   else chooseInt (length kids, length kids + 1)
          pure (reverse (bad : acc))
