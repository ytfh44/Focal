{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeOperators #-}

-- | Cross-package consistency: the frozen law-id vocabulary
--   (@docs/foundation.md@ §3) exercised through every package's public
--   surface.
--
--   Each group holds concrete witnesses — exact values, no generators —
--   and, wherever a law admits one, the witness runs through a different
--   package: the sort-indexed syntax stack, the redex core, the refactor
--   context, the patch layer, the incremental memo, the form putback,
--   the parse forest, the query putback, and the workflow gate.
module Main (main) where

import Test.QuickCheck (Property, conjoin, property)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.QuickCheck (testProperty, (===))

import Focal.Core (Focal, Focusing, composeFocal, idF, mkFocal, overF, (>>>))
import Focal.Effectful (overM, toEffectfulE)
import Focal.Interop (normalize, toVL)
import Focal.List (ListError(..), elementE)
import Focal.Optional (FocusingO(splitO), overO, toOptional)
import Focal.Partial (overE, splitE)
import Focal.Tuple (fstF)

import Focal.Syntax (Tm(TApp, TLam, TUnit), Ty(..), TyRep(..), exApp, exConst)
import Focal.Syntax.Stack (Stack(Hole, AppL), plugStack, splitStack)
import Focal.Redex
  ( CBVRedex, Fin(FZ, FS), Rm(RApp, RLam, RUnit, RVar), redexF, step )
import Focal.Refactor (RCtx(RAppL, RHole), occursAt, plugRCtx, rename, substitute)
import Focal.Delta
  ( Delta(..), Edit(..), Patch(PNil, PCons), SomeEdit(..), patchDistinct, patchFocus )
import Focal.Incremental (Memo(..), OutputDelta(Recomputed), memoRead, memoUpdate)
import Focal.Form
  ( Field(..), FieldResidual(..), FormError(..), ModelSnapshot(..)
  , PutbackResult(..), WidgetPath(..), nonEmpty, putback
  )
import Focal.Parser
  ( Alt(..), Forest(..), Selection(..), focusForest, focusResidual, focused
  , plugForest, residualSel, select
  )
import Focal.Query
  ( Projection(..), RelDelta(..), Table(..), View(..), project, relPutback, writeBack )
import Focal.Workflow
  ( GateVerdict(..), Run(..), Transition(..), Workflow(..), validateGate )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "Focal — cross-package consistency (frozen law-ids)"
  [ testGroup "L-GP"
      [ testProperty "syntax: plugStack (AppL Hole TUnit) exConst = exApp"
          prop_cs_lgp_syntax
      , testProperty "parser: plugForest restores the selected node"
          prop_cs_lgp_parser
      ]
  , testGroup "L-PG"
      [ testProperty "syntax: re-split after plug recovers focus and residual"
          prop_cs_pg_syntax
      , testProperty "parser: the residual's coordinate re-selects the replacement"
          prop_cs_pg_parser
      ]
  , testGroup "L-PP"
      [ testProperty "syntax: re-split after plug keeps a stable residual"
          prop_cs_pp_syntax
      ]
  , testGroup "L-OVF"
      [ testProperty "optional: overO rebuilds the hit" prop_cs_lovf_hit
      , testProperty "optional: overO (g . h) = overO g . overO h" prop_cs_lovf_hom
      ]
  , testGroup "L-ASSOC"
      [ testProperty "tuple chain: association does not change the rebuild"
          prop_cs_lassoc
      ]
  , testGroup "L-UNIT"
      [ testProperty "idF >>> fstF behaves like fstF" prop_cs_lunit
      ]
  , testGroup "L-NORM"
      [ testProperty "toVL (normalize f) = toVL f" prop_cs_lnorm
      ]
  , testGroup "L-TVL"
      [ testProperty "toVL (composeFocal f g) k = toVL f (toVL g k)" prop_cs_ltvl
      ]
  , testGroup "Channels"
      [ testProperty "partial: elementE off the end reports PastEnd"
          prop_cs_ch_partial
      , testProperty "optional: a lambda is a miss, and a miss passes through"
          prop_cs_ch_optional
      , testProperty "effectful: toEffectfulE agrees with overE"
          prop_cs_ch_effectful
      , testProperty "form: putback reports the empty email with its residual"
          prop_cs_ch_form
      , testProperty "workflow: the gate rejects the first undeclared step"
          prop_cs_ch_workflow
      ]
  , testGroup "Domain round trips"
      [ testProperty "query: the putback lands on the view row's source"
          prop_cs_rt_query
      , testProperty "refactor: rename twice with one pair is the identity"
          prop_cs_rt_refactor
      , testProperty "redex: one call-by-value step contracts the head redex"
          prop_cs_rt_redex
      , testProperty "refactor: plugRCtx (RAppL RUnit RHole) rebuilds the application"
          prop_cs_lgp_refactor
      , testProperty "delta: patchFocus on a live site is the global delta"
          prop_cs_lgp_delta
      , testProperty "refactor: substitution re-finds the occurrence at the replacement"
          prop_cs_pg_refactor
      , testProperty "incremental: memoUpdate re-keys the cell and the read returns it"
          prop_cs_pp_incremental
      ]
  ]

--------------------------------------------------------------------
-- Fixtures — exact values, hand-checked
--------------------------------------------------------------------

-- | The two-child forest the parser witnesses select from; the
--   selection @[1]@ picks the second child.
forest0 :: Forest
forest0 =
  Forest "p" (Alt "pair")
    [ Forest "n" (Alt "lit") [Forest "x" (Alt "x") []]
    , Forest "m" (Alt "lit2") []
    ]

-- | The replacement node for the parser witnesses.
nodeZ :: Forest
nodeZ = Forest "z" (Alt "zz") []

-- | The residual of @exApp@ at @U :-> U@ (the canonical split).
stackCtx :: Stack (U :-> U) U
stackCtx = AppL Hole TUnit

-- | First replacement for the L-PP stack witness.
firstRepl :: Tm (U :-> U)
firstRepl = TLam TyRepU (TApp exConst TUnit)

-- | Second replacement for the L-PP stack witness.
secondRepl :: Tm (U :-> U)
secondRepl = exConst

-- | Optional focus on the first tuple component (every source is a hit).
optFst :: FocusingO Bool (Int, Bool) (Int, Bool) Int Int
optFst = toOptional (fstF :: Focusing Bool (Int, Bool) (Int, Bool) Int Int)

-- | Fixed value for the L-ASSOC witness.
assocVal :: (((Int, Int), String), Bool)
assocVal = (((1, 2), "s"), True)

-- | Fixed value for the L-UNIT witness.
unitPair :: (Int, Bool)
unitPair = (41, True)

-- | The first tuple component as a 'Focal' — the L-NORM / L-TVL instance.
fstFocal :: Focal (Int, Bool) (Int, Bool) Int Int
fstFocal = mkFocal (fstF :: Focusing Bool (Int, Bool) (Int, Bool) Int Int)

-- | Identity 'Focal' on @Int@ — the inner stage of the L-TVL witness.
idFocal :: Focal Int Int Int Int
idFocal = mkFocal (idF :: Focusing () Int Int Int Int)

-- | Fixed Van Laarhoven consumer for the interop witnesses.
normK :: Int -> Maybe Int
normK x = Just (x + 1)

-- | The submit-approve workflow the gate witness runs against.
wf0 :: Workflow
wf0 = Workflow ["draft", "review", "done"]
  [ Transition "submit" "draft" "review"
  , Transition "approve" "review" "done"
  ]

-- | The two-row table the query witness puts back into; the witness
--   edits the second row, whose provenance is the index 1.
tblTwo :: Table
tblTwo = Table ["id", "name"]
  [ [("id", "1"), ("name", "a")]
  , [("id", "2"), ("name", "b")]
  ]

-- | The memo cell before the update: it caches the identity term,
--   which reads the innermost variable.
preMemo :: Memo '[U] U
preMemo = Memo PNil (RVar FZ)

-- | The term the update writes into the cell: the unit, which differs
--   from the term the cell held before the update.
memoNewTerm :: Rm '[U] U
memoNewTerm = RUnit

-- | The patch the update is keyed by: an edit at the innermost
--   variable — the one the pre-update term reads.
memoUpdPatch :: Patch '[U]
memoUpdPatch = PCons (SomeEdit (Edit (FZ :: Fin '[U] U) RUnit)) PNil

--------------------------------------------------------------------
-- L-GP — split-plug reconstruction through the syntax and parser
--   layers
--------------------------------------------------------------------

-- | Syntax: filling the split's residual with the focus rebuilds
--   @exApp@.
prop_cs_lgp_syntax :: Property
prop_cs_lgp_syntax =
  plugStack (AppL Hole TUnit) exConst === exApp

-- | Parser: the frame list rebuilds the forest with the selected node
--   in its hole.
prop_cs_lgp_parser :: Property
prop_cs_lgp_parser =
  maybe (property False)
    (\ff -> plugForest (focusResidual ff) (focused ff) === forest0)
    (focusForest (Selection [1]) forest0)

--------------------------------------------------------------------
-- L-PG — residual re-focus through the syntax and parser layers
--------------------------------------------------------------------

-- | Syntax: re-splitting after the plug recovers the focus and the
--   residual.
prop_cs_pg_syntax :: Property
prop_cs_pg_syntax =
  splitStack (TyRepArr TyRepU TyRepU) (plugStack (AppL Hole TUnit) exConst)
    === Just (exConst, AppL Hole TUnit)

-- | Parser: the residual's coordinate re-selects the replacement.
prop_cs_pg_parser :: Property
prop_cs_pg_parser =
  maybe (property False)
    (\ff -> select (residualSel (focusResidual ff)) (plugForest (focusResidual ff) nodeZ)
             === Just nodeZ)
    (focusForest (Selection [1]) forest0)

--------------------------------------------------------------------
-- L-PP — residual-overwrite stability, witnessed on the syntax layer
--------------------------------------------------------------------

-- | Syntax: re-splitting after a plug yields a residual that behaves
--   exactly like the original one.
prop_cs_pp_syntax :: Property
prop_cs_pp_syntax =
  case splitStack (TyRepArr TyRepU TyRepU) (plugStack stackCtx firstRepl) of
    Nothing      -> property False
    Just (_, c') -> plugStack c' secondRepl === plugStack stackCtx secondRepl

--------------------------------------------------------------------
-- L-OVF — over composition
--------------------------------------------------------------------

-- | Optional: a hit rebuilds through the plug.
prop_cs_lovf_hit :: Property
prop_cs_lovf_hit =
  overO optFst (+1) unitPair === (42, True)

-- | Optional: @overO@ is a homomorphism over function composition on
--   the hit domain.
prop_cs_lovf_hom :: Property
prop_cs_lovf_hom =
  overO optFst ((+1) . (*2)) unitPair
    === overO optFst (+1) (overO optFst (*2) unitPair)

--------------------------------------------------------------------
-- L-ASSOC — composition associativity
--------------------------------------------------------------------

-- | Core: association of the triple chain does not change the rebuild.
prop_cs_lassoc :: Property
prop_cs_lassoc =
  overF ((idF >>> fstF) >>> fstF) id assocVal
    === overF (idF >>> (fstF >>> fstF)) id assocVal

--------------------------------------------------------------------
-- L-UNIT — identity
--------------------------------------------------------------------

-- | Core: @idF >>> fstF@ behaves like @fstF@.
prop_cs_lunit :: Property
prop_cs_lunit =
  overF (idF >>> fstF) id unitPair === overF fstF id unitPair

--------------------------------------------------------------------
-- L-NORM — canonical form
--------------------------------------------------------------------

-- | Interop: the canonical form is observationally the original.
prop_cs_lnorm :: Property
prop_cs_lnorm =
  toVL (normalize fstFocal) normK unitPair === toVL fstFocal normK unitPair

--------------------------------------------------------------------
-- L-TVL — toVL composition
--------------------------------------------------------------------

-- | Interop: @toVL@ turns composition into left-to-right application.
prop_cs_ltvl :: Property
prop_cs_ltvl =
  toVL (composeFocal fstFocal idFocal) normK unitPair
    === toVL fstFocal (toVL idFocal normK) unitPair

--------------------------------------------------------------------
-- Channels — the registered channel families
--------------------------------------------------------------------

-- | Partial: the failure channel reports the index past the end.
prop_cs_ch_partial :: Property
prop_cs_ch_partial =
  splitE (elementE 0) []
    === (Left (PastEnd 0) :: Either ListError (Int, ([Int], [Int])))

-- | Optional: a lambda is not a redex, so the redex focus misses; a miss
--   passes the source through unchanged.
prop_cs_ch_optional :: Property
prop_cs_ch_optional =
  conjoin
    [ (splitO redexF (RLam TyRepU (RVar FZ) :: Rm '[] (U :-> U))
         :: Maybe (CBVRedex '[] (U :-> U), ()))
        === Nothing
    , overO redexF id (RLam TyRepU (RVar FZ) :: Rm '[] (U :-> U))
        === RLam TyRepU (RVar FZ)
    ]

-- | Effectful: the embedding of the failure channel agrees with
--   @overE@.
prop_cs_ch_effectful :: Property
prop_cs_ch_effectful =
  overM (toEffectfulE (elementE 0)) (+1) [1, 2, 3]
    === (overE (elementE 0) (+1) [1, 2, 3] :: Either ListError [Int])

-- | Form: the empty email fails validation, and the putback reports the
--   error together with the input's residual.
prop_cs_ch_form :: Property
prop_cs_ch_form =
  putback [("email", nonEmpty)] (ModelSnapshot []) (Field (WidgetPath ["f", "email"]) "" "email")
    === PutbackError (FormError (WidgetPath ["f", "email"]) "empty")
          (FieldResidual (WidgetPath ["f", "email"]) "" "email")

-- | Workflow: the gate rejects the first undeclared step with its
--   index.
prop_cs_ch_workflow :: Property
prop_cs_ch_workflow =
  validateGate wf0 (Run [Transition "submit" "draft" "review", Transition "bogus" "review" "done"])
    === GateRejected 1 (Transition "bogus" "review" "done")

--------------------------------------------------------------------
-- Domain round trips — one per-layer equation per instance
--------------------------------------------------------------------

-- | Query: the write-back policy lands the delta on the view row's
--   source.  The witness edits the SECOND row of the table, whose
--   provenance is the non-zero index 1 — an implementation that
--   hard-coded row index 0 is caught.
prop_cs_rt_query :: Property
prop_cs_rt_query =
  case project (Projection ["name"]) tblTwo of
    View (_ : vr : _) ->
      relPutback writeBack tblTwo vr "name" "z" === Right (RelDelta 1 "name" "z")
    View _ -> property False

-- | Refactor: renaming twice with one pair is the identity.
prop_cs_rt_refactor :: Property
prop_cs_rt_refactor =
  rename (FZ :: Fin '[U, U] U) (FS FZ)
    (rename (FZ :: Fin '[U, U] U) (FS FZ)
      (RApp (RLam TyRepU (RVar FZ)) (RVar (FS FZ)) :: Rm '[U, U] U))
    === (RApp (RLam TyRepU (RVar FZ)) (RVar (FS FZ)) :: Rm '[U, U] U)

-- | Redex: one call-by-value step contracts the head redex.
prop_cs_rt_redex :: Property
prop_cs_rt_redex =
  step (RApp (RLam TyRepU (RVar FZ)) RUnit) === Just RUnit

-- | Refactor: the context fill rebuilds the application — the
--   refactor layer's own round-trip equation.
prop_cs_lgp_refactor :: Property
prop_cs_lgp_refactor =
  plugRCtx (RAppL RUnit RHole :: RCtx '[] '[] (U :-> U) U)
    (RLam TyRepU (RVar FZ) :: Rm '[] (U :-> U))
    === (RApp (RLam TyRepU (RVar FZ)) RUnit :: Rm '[] U)

-- | Delta: a live site's local replacement is the global delta — the
--   patch layer's own round-trip equation.
prop_cs_lgp_delta :: Property
prop_cs_lgp_delta =
  patchFocus (Edit (FZ :: Fin '[U] U) RUnit) (RVar FZ :: Rm '[U] U)
    === Right (Delta (Edit (FZ :: Fin '[U] U) RUnit) RUnit)

-- | Refactor: after substituting, the transported position occurs in
--   the image (the replacement is re-found there) — the refactor
--   layer's own round-trip equation.
prop_cs_pg_refactor :: Bool
prop_cs_pg_refactor =
  occursAt (FS FZ :: Fin '[U, U] U)
    (substitute (FZ :: Fin '[U, U] U) (RVar (FS FZ)) (RVar FZ))

-- | Incremental: the layer's put-put content — the incremental
--   layer's own round-trip equation.  A 'memoUpdate' that carries a
--   recomputed term RE-KEYS the cell to the patch that produced it,
--   and the cell the update wrote is what a later read returns.
--
--   The two values compared differ: the update writes the unit, while
--   the cell held the identity term (@RVar FZ@) beforehand, and the
--   update's patch claims the very variable that pre-update term
--   reads — so the pre-update cell is stale under that patch and
--   reads 'Nothing'.  An update that dropped the write, or that kept
--   the pre-update cell, is therefore caught, and the re-key is
--   observed through the key's claims rather than the term.
prop_cs_pp_incremental :: Property
prop_cs_pp_incremental = conjoin
  [ -- the cell was re-keyed to the patch that produced the new term
    case memoUpdate preMemo (Recomputed memoNewTerm memoUpdPatch) of
      Memo key _ -> patchDistinct (FZ :: Fin '[U] U) key === False
    -- the read after the update returns the cell the update wrote
  , memoRead (memoUpdate preMemo (Recomputed memoNewTerm memoUpdPatch))
      memoUpdPatch
    === Just memoNewTerm
  ]
