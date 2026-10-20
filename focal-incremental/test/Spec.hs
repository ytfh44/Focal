{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeOperators #-}

module Main (main) where

import Test.QuickCheck (Gen, Property, conjoin, forAll, oneof, property, sized)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.QuickCheck (testProperty, (===))

import Focal.Syntax (Ty(..), TyRep(..))
import Focal.Redex (Fin(..), Rm(..))
import Focal.Refactor (SomeFin(..))
import Focal.Delta (Edit(..), Patch(..), SomeEdit(..), applyPatch, claimed)
import Focal.Incremental
  ( InvalEdge(..), Memo(..), OutputDelta(..), firedEdges, incrementalPlug
  , invalGraph, memoDeps, memoReads, memoUpdate, recomputePatch
  )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "focal-incremental — incremental plug"
  [ testGroup "Invalidation"
      [ testProperty "a clean patch ignores the seam"
          prop_inc_clean_ignores_seam
      , testProperty "a recompute serves the seam's result"
          prop_inc_recomputed_uses_seam
      , testProperty "memo updates re-key the cache"
          prop_inc_memo_update
      , testProperty "fired edges exactly track the reads"
          prop_inc_fired
      ]
  ]

--------------------------------------------------------------------
-- Invalidations
--------------------------------------------------------------------

-- | The clean branch reads through without consulting the seam: the
--   patch claims @FZ@, but the cached @RUnit@ reads nothing, so the
--   cached term is served — even though the seam here is the WRONG
--   function (it applies the patch to @base@ instead of returning its
--   own argument).  It can fail: a plug that consulted the seam on a
--   clean patch would serve the seam's rewrite, and the last conjunct
--   pins that rewrite as a different term, so the two branches are
--   observably distinct.
prop_inc_clean_ignores_seam :: Property
prop_inc_clean_ignores_seam =
  let base  = RVar FZ :: Rm '[U] U
      block = RApp (RLam TyRepU RUnit) RUnit :: Rm '[U] U
      p1    = PCons (SomeEdit (Edit (FZ :: Fin '[U] U) block)) PNil
      memo  = Memo PNil (RUnit :: Rm '[U] U)
      out   = incrementalPlug (\p _ -> applyPatch p base) memo p1
  in  case out of
        Clean t'     -> conjoin
          [ t' === RUnit
          , applyPatch p1 base === block
          , property (block /= RUnit)
          ]
        Recomputed{} -> property False

-- | The recomputed branch serves the seam's result: the memo reads the
--   claimed @FZ@, and the seam — a function that ignores both of its
--   arguments and yields @RUnit@ — supplies the output, provenance
--   included.  It can fail: a plug that recomputed with
--   'recomputePatch' instead of calling the given seam would serve the
--   patched term @block@, and the last conjunct pins that term as
--   different from the seam's @RUnit@.
prop_inc_recomputed_uses_seam :: Property
prop_inc_recomputed_uses_seam =
  let block = RApp (RLam TyRepU RUnit) RUnit :: Rm '[U] U
      p1    = PCons (SomeEdit (Edit (FZ :: Fin '[U] U) block)) PNil
      memo  = Memo PNil (RVar FZ :: Rm '[U] U)
      out   = incrementalPlug (\_ _ -> RUnit) memo p1
  in  case out of
        Recomputed t' p' -> conjoin
          [ t' === RUnit
          , show p' === show p1
          , property (applyPatch p1 (RVar FZ) /= RUnit)
          ]
        Clean _          -> property False

-- | The memo update re-keys the cache to the whole patch that produced
--   the recomputed term — the edit block included, not just the claimed
--   positions — and a clean run leaves the memo, key and dependency
--   trace alike, untouched.  It can fail: a 'memoUpdate' that kept the
--   old key, or that stored a body-less patch, does not match
--   @Memo p (applyPatch p base)@, and one that re-keyed (or rebuilt) the
--   memo on a clean run loses the cached key.
prop_inc_memo_update :: Property
prop_inc_memo_update = forAll genBodyU2 $ \body ->
  let p        = PCons (SomeEdit (Edit (FZ :: Fin '[U, U] U) body)) PNil
      base     = RVar FZ :: Rm '[U, U] U
      dmemo    = Memo PNil base
      dirty    = incrementalPlug recomputePatch dmemo p
      rekeyed  = memoUpdate dmemo dirty
      expected = Memo p (applyPatch p base)
      p0       = PCons (SomeEdit (Edit (FS FZ :: Fin '[U, U] U) RUnit)) PNil
      cmemo    = Memo p0 (RLam TyRepU (RVar FZ) :: Rm '[U, U] (U :-> U))
      clean    = incrementalPlug recomputePatch cmemo p
      kept     = memoUpdate cmemo clean
  in  conjoin
        [ case dirty of
            Recomputed{} -> show rekeyed === show expected
            Clean _      -> property False
        , case clean of
            Clean{}      -> conjoin
              [ show kept === show cmemo
              , show (memoDeps kept) === show (memoDeps cmemo)
              ]
            Recomputed{} -> property False
        ]

-- | The invalidation summary fires exactly on the reads: the patch
--   claims @FZ@ explicitly (the claim is the premise, never a
--   generator-side predicate), and a fired edge appears exactly when the
--   memo reads @FZ@.  It can fail: a 'firedEdges' that dropped the read
--   filter (reporting every claim) or that reported the memo's trace
--   instead of the claims disagrees with the claimed variables filtered
--   by 'memoReads' and with 'invalGraph'.
prop_inc_fired :: Property
prop_inc_fired = forAll genBodyU2 $ \body -> forAll genBodyU2 $ \t ->
  let p      = PCons (SomeEdit (Edit (FZ :: Fin '[U, U] U) body)) PNil
      m      = Memo PNil t
      readFz = memoReads m (SomeFin (FZ :: Fin '[U, U] U))
      firing = firedEdges m p
  in  conjoin
        [ show firing === show [ c | c <- claimed p, memoReads m c ]
        , show firing === show [ c | Edge c True <- invalGraph m p ]
        , case firing of
            [] -> property (not readFz)
            _  -> property readFz
        ]

--------------------------------------------------------------------
-- Generators — terms over '[U, U] at sort U
--------------------------------------------------------------------

genBodyU2 :: Gen (Rm '[U, U] U)
genBodyU2 = sized genBodyU2N
genBodyU2N :: Int -> Gen (Rm '[U, U] U)
genBodyU2N n = oneof
  [ pure RUnit
  , pure (RVar FZ)
  , pure (RVar (FS FZ))
  , RApp (RLam TyRepU (RVar FZ)) <$> genBodyU2N (n `div` 2)
  ]
