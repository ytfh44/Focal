{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeOperators #-}

module Main (main) where

import Test.QuickCheck (Gen, Property, conjoin, forAll, oneof, property, sized, (=/=), (==>))
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.QuickCheck (testProperty, (===))

import Focal.Syntax (Ty(..), TyRep(..), eqRep)
import Focal.Redex (Fin(..), Rm(..), Redex(..), contract, lift1)
import Focal.Refactor
  ( RCtx(..), SomeFin(..), occursAt, rename, substitute, weakenFin, weakenRm
  )
import Focal.Delta
  ( Conflict(..), Delta(..), Edit(..), Patch(..), SomeEdit(..), addEdit
  , applyEdit, applyPatch, claimed, composeEdit, deltaOn
  , inlineApply, patchFocus, reindexDelta, renameEdit, samePos, survives
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
      , testProperty "compose transports the second block (divergence boundary)"
          prop_dl_compose_divergence
      , testProperty "addEdit refuses an edit at an already-claimed variable"
          prop_dl_add_edit_refusal
      ]
  , testGroup "Refactoring bridge"
      [ testProperty "rename through the edit layer reproduces the operation (fresh target)"
          prop_dl_rename_bridge
      , testProperty "renaming to an occupied target is not the one-point edit"
          prop_dl_rename_swap
      , testProperty "inlining through the edit layer is lifted beta contraction"
          prop_dl_inline_bridge
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

-- | The composite transports the second block; it diverges from
--   sequential application when the first edit removes the variable
--   (the documented boundary).
prop_dl_compose_divergence :: Property
prop_dl_compose_divergence =
  conjoin
    [ occursAt (FZ :: Fin '[U, U] U) (RVar (FS FZ) :: Rm '[U, U] U) === False
    , applyEdit (Edit (FZ :: Fin '[U, U] U) RUnit)
        (applyEdit (Edit (FZ :: Fin '[U, U] U) RUnit) (RVar FZ :: Rm '[U, U] U))
        === RUnit
    , applyEdit (composeEdit (Edit (FZ :: Fin '[U, U] U) RUnit)
                             (Edit (FZ :: Fin '[U, U] U) (RVar (FS FZ))))
        (RVar FZ :: Rm '[U, U] U)
        === RVar (FS FZ)
    ]

-- | 'addEdit' is the checked form of extending a patch: it refuses an
--   edit at a variable the patch already claims (the conflict — two
--   candidate blocks for one variable, no evidence to prefer either) and
--   accepts an edit at a fresh variable, extending the patch with it.
prop_dl_add_edit_refusal :: Property
prop_dl_add_edit_refusal =
  case addEdit atFresh p of
    Nothing -> property False
    Just p'  -> conjoin
      [ property (case addEdit atClaimed p of
                   Nothing -> True
                   Just _  -> False)
      , case claimed p' of
          [SomeFin jFresh, SomeFin jClaimed] ->
            conjoin
              [ property (samePos jFresh (FS FZ :: Fin '[U, U] U))
              , property (samePos jClaimed (FZ :: Fin '[U, U] U))
              ]
          _ -> property False
      , applyPatch p' (RVar (FS FZ) :: Rm '[U, U] U) === RUnit
      ]
  where
    p         = PCons (SomeEdit (Edit (FZ :: Fin '[U, U] U) RUnit)) PNil
    atClaimed = Edit (FZ :: Fin '[U, U] U) (RVar (FS FZ))
    atFresh   = Edit (FS FZ :: Fin '[U, U] U) (RVar FZ)

--------------------------------------------------------------------
-- Refactoring bridge
--------------------------------------------------------------------

-- | The rename bridge: applying the rename's edit reproduces the rename
--   operation when the target position is fresh (not occurring in the
--   term).  The non-vacuous concrete leg pins a variable-only term; the
--   generator leg carries the freshness premise (under a binder the
--   fresh position is the binder's own variable, which "Focal.Refactor"'s
--   'substitute' never touches and 'rename' transposes only when both
--   positions are used).
prop_dl_rename_bridge :: Property
prop_dl_rename_bridge = conjoin
  [ applyEdit (renameEdit (FZ :: Fin '[U, U] U) (FS FZ)) (RVar FZ)
      === rename (FZ :: Fin '[U, U] U) (FS FZ) (RVar FZ)
  , forAll genBodyU2 $ \t ->
      not (occursAt (FS FZ :: Fin '[U, U] U) t) ==>
        applyEdit (renameEdit (FZ :: Fin '[U, U] U) (FS FZ)) t
          === rename (FZ :: Fin '[U, U] U) (FS FZ) t
  ]

-- | Renaming to an occupied target transposes: the positions swap
--   roles, so the one-point edit and the operation differ (witnessed on
--   a term using both positions).
prop_dl_rename_swap :: Property
prop_dl_rename_swap =
  applyEdit (renameEdit (FZ :: Fin '[U, U] U) (FS FZ))
    (RVar (FS FZ) :: Rm '[U, U] U)
    =/= rename (FZ :: Fin '[U, U] U) (FS FZ)
      (RVar (FS FZ) :: Rm '[U, U] U)

-- | Inlining through the edit layer is lifted beta contraction: the
--   edit applies "Focal.Refactor"'s binder-aware substitution
--   ('applyEdit', i.e. 'substitute') in the extended context, keeping
--   the binder's slot; "Focal.Redex"'s 'contract' drops the slot —
--   relating the two is exactly 'lift1' (the
--   substitution-commutes-with-weakening cross-layer witness).
prop_dl_inline_bridge :: Property
prop_dl_inline_bridge = conjoin
  [ inlineApply (RVar FZ :: Rm '[U] U) (RVar FZ :: Rm '[U, U] U) === RVar (FS FZ)
  , forAll genBodyU2 $ \b ->
      inlineApply (RVar FZ :: Rm '[U] U) b
        === lift1 (contract (Beta TyRepU b (RVar FZ :: Rm '[U] U)))
  ]

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

-- Wrapper for the refactoring-bridge properties.
genBodyU2 :: Gen (Rm '[U, U] U)
genBodyU2 = sized genBodyU2N
