{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeOperators #-}

module Main (main) where

import Test.QuickCheck (Gen, Property, conjoin, forAll, oneof, property, sized)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.QuickCheck (testProperty, (===))

import Focal.Syntax (Ty(..), TyRep(..), eqRep)
import Focal.Redex (Fin(..), Rm(..))
import Focal.Refactor
  ( RCtx(..), occursAt, substitute, weakenFin, weakenRm
  )
import Focal.Delta
  ( Conflict(..), Delta(..), Edit(..), deltaOn, patchFocus, reindexDelta
  , samePos, survives
  )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "focal-delta — structural patch focus"
  [ testGroup "Patch focus"
      [ testProperty "hit: result is the substituted term, evidence preserved"
          prop_dl_hit_result
      , testProperty "zero candidates: no occurrence, no delta"
          prop_dl_no_site
      , testProperty "reindexed deltas apply equivalently on transported terms"
          prop_dl_reindex
      , testProperty "evidence travels to other terms"
          prop_dl_delta_on
      ]
  ]

-- | Positional comparison of blocks with independent existentials (the
--   spec-side mirror of the module's edit-equality discipline): the
--   pattern-matched edit's block sort is existential, so evidence
--   preservation is asserted positionally rather than through the
--   sort-refining '(===)'.
eqBlockSpec :: Rm g1 t1 -> Rm g2 t2 -> Bool
eqBlockSpec RUnit        RUnit        = True
eqBlockSpec (RVar i)     (RVar j)     = samePos i j
eqBlockSpec (RLam r1 b1) (RLam r2 b2) = eqRep r1 r2 && eqBlockSpec b1 b2
eqBlockSpec (RApp f1 x1) (RApp f2 x2) = eqBlockSpec f1 f2 && eqBlockSpec x1 x2
eqBlockSpec _            _            = False

-- | A patch focus with a surviving variable is a delta whose result is
--   the substituted term, with the edit's block preserved as evidence.
--   The 'NoSite' branch is witnessed exactly by the survival witness:
--   every 'Left' is a 'NoSite', arising exactly when the variable does
--   not occur.  Both fixed result sorts are exercised: the edit's sort
--   ('U', the only variable sort over @'[U]@) is independent of the
--   target term's sort.
prop_dl_hit_result :: Property
prop_dl_hit_result = conjoin
  [ forAll genBodyU1 $ \t -> forAll genBodyU1 $ \a ->
      case patchFocus (Edit (FZ :: Fin '[U] U) a) t of
        Left (NoSite _) -> property (not (survives (Edit (FZ :: Fin '[U] U) a) t))
        Left _          -> property False
        Right (Delta (Edit _ a') t') ->
          conjoin [property (eqBlockSpec a' a), t' === substitute iFZ a t]
  , forAll genArrU1 $ \t -> forAll genBodyU1 $ \a ->
      case patchFocus (Edit (FZ :: Fin '[U] U) a) t of
        Left (NoSite _) -> property (not (survives (Edit (FZ :: Fin '[U] U) a) t))
        Left _          -> property False
        Right (Delta (Edit _ a') t') ->
          conjoin [property (eqBlockSpec a' a), t' === substitute iFZ a t]
  ]
  where
    iFZ = FZ :: Fin '[U] U

-- | Zero candidates: no occurrence, no delta.
prop_dl_no_site :: Property
prop_dl_no_site =
  patchFocus (Edit (FZ :: Fin '[U] U) RUnit) (RUnit :: Rm '[U] U)
    === Left (NoSite FZ)

-- | Evidence travels: reindexing a delta along a path and applying it
--   to the transported term substitutes the transported variable by the
--   transported block — equal to transporting the substituted term
--   (the substitution-commutes-with-weakening witness, at the delta
--   level).
prop_dl_reindex :: Property
prop_dl_reindex = forAll genBodyU1 $ \t ->
  let k = RLamC TyRepU RHole :: RCtx '[U] '[U, U] U (U :-> U)
      i = FZ :: Fin '[U] U
      a = RVar FZ :: Rm '[U] U
  in  case deltaOn (reindexDelta k (Delta (Edit i a) t)) (weakenRm k t) of
        Left (NoSite _) ->
          property (not (occursAt (weakenFin k i) (weakenRm k t)))
        Left _            -> property False
        Right (Delta _ t') -> t' === weakenRm k (substitute i a t)

-- | The delta re-applies: the evidence travels to other terms, and the
--   zero-candidate conflict arises exactly when the new term does not
--   contain the edit's variable.
prop_dl_delta_on :: Property
prop_dl_delta_on = forAll genBodyU1 $ \t1 -> forAll genBodyU1 $ \t2 ->
  case patchFocus (Edit (FZ :: Fin '[U] U) (RVar FZ :: Rm '[U] U)) t1 of
    Left _  -> property True   -- no site in t1: no evidence to carry
    Right d -> case deltaOn d t2 of
      Left (NoSite _) ->
        property (not (survives (Edit (FZ :: Fin '[U] U) (RVar FZ)) t2))
      Left _             -> property False
      Right (Delta _ t') -> t' === substitute (FZ :: Fin '[U] U) (RVar FZ) t2

--------------------------------------------------------------------
-- Generators — terms over '[U] and '[U, U] at the two fixed sorts
--------------------------------------------------------------------

-- Terms over context '[U] at sort U.
genBodyU1 :: Gen (Rm '[U] U)
genBodyU1 = sized genBodyU1N
genBodyU1N :: Int -> Gen (Rm '[U] U)
genBodyU1N n = oneof
  [ pure RUnit
  , pure (RVar FZ)
  , RApp (RLam TyRepU (RVar FZ)) <$> genBodyU1N (n `div` 2)
  , RApp <$> genArrBodyU1 (n `div` 2) <*> pure (RVar FZ)
  ]
  where
    genArrBodyU1 m = oneof
      [ pure (RLam TyRepU (RVar FZ))
      , pure (RLam TyRepU (RVar (FS FZ)))
      , RLam TyRepU <$> genBodyU12 (m `div` 2)
      ]
    genBodyU12 m = oneof
      [ pure RUnit
      , pure (RVar FZ)
      , pure (RVar (FS FZ))
      , RApp (RLam TyRepU (RVar FZ)) <$> genBodyU12 (m `div` 2)
      ]

-- Function-sorted terms over context '[U] (lambda bodies at the hole).
genArrU1 :: Gen (Rm '[U] (U :-> U))
genArrU1 = sized genArrU1N
genArrU1N :: Int -> Gen (Rm '[U] (U :-> U))
genArrU1N n = oneof
  [ pure (RLam TyRepU (RVar FZ))
  , RLam TyRepU <$> genBodyU2N (n `div` 2)
  , RApp (RLam TyRepU (RLam TyRepU (RVar FZ))) <$> genBodyU1N (n `div` 2)
  ]

-- Terms over context '[U, U] at sort U (under one refactor binder).
genBodyU2N :: Int -> Gen (Rm '[U, U] U)
genBodyU2N n = oneof
  [ pure RUnit
  , pure (RVar FZ)
  , pure (RVar (FS FZ))
  , RApp (RLam TyRepU (RVar FZ)) <$> genBodyU2N (n `div` 2)
  ]
