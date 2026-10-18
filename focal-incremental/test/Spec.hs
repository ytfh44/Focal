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
import Focal.Delta (Edit(..), Patch(..), SomeEdit(..), applyPatch)
import Focal.Incremental
  ( Memo(..), OutputDelta(..), firedEdges, incrementalPlug, memoDeps
  , memoUpdate, recomputePatch, sameSomeFin
  )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "focal-incremental — incremental plug"
  [ testGroup "Invalidation"
      [ testProperty "claimed reads invalidate; the recomputed output is the patched term"
          prop_inc_invalidate
      , testProperty "clean patches read through"
          prop_inc_clean
      , testProperty "memo updates re-key the cache"
          prop_inc_memo_update
      , testProperty "fired edges exactly track the reads"
          prop_inc_fired
      ]
  ]

--------------------------------------------------------------------
-- Invalidations
--------------------------------------------------------------------

-- | A patch claiming a read variable invalidates; the recomputed output
--   is the patched term.  The claim is targeted: it is made exactly
--   when the memo's term reads @FZ@, so the 'Clean' branch arises
--   exactly on the unread case, where the assertion confirms no read.
prop_inc_invalidate :: Property
prop_inc_invalidate = forAll genBodyU2 $ \t ->
  case incrementalPlug recomputePatch (Memo PNil t) (claimFZ t) of
    Clean _         -> property (not (readsFZ t))
    Recomputed t' _ -> t' === applyPatch (claimFZ t) t

-- | A clean patch reads through: with no claims (an empty patch), the
--   plug never invalidates and serves the cached term unchanged.
prop_inc_clean :: Property
prop_inc_clean = forAll genBodyU2 $ \t ->
  case incrementalPlug recomputePatch (Memo PNil t) PNil of
    Clean t'      -> t' === t
    Recomputed{}  -> property False

-- | The memo update re-keys the cache to the patch that produced it:
--   after a dirty run the new memo's key is the patch (positionally,
--   via 'samePatchSpec') and its term is the patched term; a clean run
--   leaves the memo untouched (same dependency trace).
prop_inc_memo_update :: Property
prop_inc_memo_update = forAll genBodyU2 $ \t ->
  let p = claimFZ t
      m = Memo PNil t
  in  case incrementalPlug recomputePatch m p of
        Clean _      -> property (not (readsFZ t))
        Recomputed{} -> case memoUpdate m (incrementalPlug recomputePatch m p) of
          Memo p' t' -> conjoin [property (samePatchSpec p' p), t' === applyPatch p t]

-- | The invalidation summary fires exactly on the reads: a fired edge
--   arises exactly when the memo's term reads @FZ@ (the claim is made
--   exactly on that condition, so firing mirrors the read set).
prop_inc_fired :: Property
prop_inc_fired = forAll genBodyU2 $ \t ->
  let p = claimFZ t
  in  case firedEdges (Memo PNil t) p of
        [] -> property (not (readsFZ t))
        _  -> property (readsFZ t)

--------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------

-- | The claim: an edit at @FZ@ exactly when the term reads @FZ@, the
--   empty patch otherwise.
claimFZ :: Rm '[U, U] U -> Patch '[U, U]
claimFZ t
  | readsFZ t = PCons (SomeEdit (Edit (FZ :: Fin '[U, U] U) (RVar (FS FZ)))) PNil
  | otherwise = PNil

-- | Does the term read @FZ@?  Positional over the dependency trace
--   (read through the memo, the module's own trace accessor).
readsFZ :: Rm '[U, U] U -> Bool
readsFZ t = any (sameFinPos (SomeFin (FZ :: Fin '[U, U] U))) (memoDeps (Memo PNil t))

-- | Positional equality of variable occurrences (the module's own
--   exported comparison, over 'SomeFin').
sameFinPos :: SomeFin g -> SomeFin g -> Bool
sameFinPos = sameSomeFin

-- | Positional patch equality: same claimed variables, in order (the
--   existential of each 'SomeEdit' is pattern-matched away; blocks are
--   not compared — the key is the claimed set).
samePatchSpec :: Patch '[U, U] -> Patch '[U, U] -> Bool
samePatchSpec PNil PNil = True
samePatchSpec (PCons (SomeEdit (Edit i _)) r1) (PCons (SomeEdit (Edit j _)) r2) =
  sameFinPos (SomeFin i) (SomeFin j) && samePatchSpec r1 r2
samePatchSpec _ _ = False

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
