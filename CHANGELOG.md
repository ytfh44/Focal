# Changelog for `focal-core`

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to the
[Haskell Package Versioning Policy](https://pvp.haskell.org/).

## Unreleased

## 0.2.0.0 - 2026-10-20

Integration release: ten packages over the stable core, all twelve
specializations implemented (rows 11–12 annotated as domain frameworks), with
the law surface repaired and the claim layer audited against the code. The ten
packages publish their first version here.

- Added `focal-syntax` (0.2.0.0): the sort-indexed example language with
  the typed contexts (`Stack i j`), the canonical sort-checked split, the
  law witnesses, and the negative type-error witness.
- Added `focal-redex` (0.2.0.0): the typed de Bruijn core (values, redexes,
  evaluation contexts, substitution), the canonical decomposition with the
  optional-rung redex focus, and the law family (plug-after-decompose,
  progress, normalization, head step = beta).
- Added `focal-refactor` (0.2.0.0): the top-down refactor stack with type
  facts, scope snapshots, and layout spans; capture-avoiding substitution
  and path transport with the substitution-commutes-with-path lemma; the
  basic operations (rename, abstract, inline, eta-expansion).
- Added `focal-delta` (0.2.0.0): evidence-carrying edits, patches, and the
  zero-/two-candidate conflict reports; the structural patch focus and the
  refactoring bridge (rename and inline as edits).
- Added `focal-incremental` (0.2.0.0): dependency traces, the single-cell
  memo, invalidation over claimed-vs-read sets, and the incremental plug
  with `OutputDelta`.
- Added `focal-form` (0.2.0.0): widget paths, the validation registry,
  model snapshots, and field residuals with provenance; the
  validate-then-apply putback.
- Added `focal-parser` (0.2.0.0): grammars with named alternatives,
  provenance-carrying forests, the selection focus with the frame-list
  (non-tree) residual, and the reparse report (ambiguity preserved, never
  resolved).
- Added `focal-query` (0.2.0.0): tables, projection provenance, join
  witnesses, view-update policies, and the policy-ordered relational
  putback (`AmbiguousPutback`, never a silent choice).
- Added `focal-workflow` (0.2.0.0): transition contexts, rollback plans
  (compensation as a preorder), the validation gate, and the workflow plug.
- Added `focal-consistency` (test-only): the cross-package consistency
  suite over the frozen law-id vocabulary (23 properties, all ten
  packages).
- Corrections from the independent audit pass: `renderSpans` reports global
  half-open text offsets; the form putback stores the validator's adopted
  value (the residual keeps the raw input); the workflow gate checks
  transition continuity in addition to declaration membership; `composeEdit`,
  `rename`, and `focusProv` document their actual semantics (edit transport,
  positional transposition, root-first provenance chain).

- Corrected the law vocabulary (`docs/foundation.md` §3): `L-PG` and `L-PP` carry
  the residual premise `c ∈ R(f)` in every rung, and `L-PG` names its re-hit
  clause. Pinned by the off-image discriminators `prop_discO_offImage`,
  `prop_discE_offImage`, `prop_discM_offImage`, and `prop_tm_offImage`.
- Changed `redexF`'s optional-rung focus to `CBVRedex` — a lambda applied to a
  `Value` — with the unit as residual, so `L-GP`, `L-PG`, and `L-PP` hold over
  the whole plug domain with no premise and no value-ness premise. `Redex` and
  `EvalCtx` keep their roles in `decompose`, `step`, and `plugEval`.
- Reclassified `L-ASSOC` and `L-UNIT` as L2 definitional identities, pinned by
  `prop_lassoc_residual` instead of the unfalsifiable driver group, and `L-OVF`
  as an L3 corollary of `L-PG` + `L-PP` (`L-GP` unused).
- Added the discriminating witnesses: `prop_lassoc_residual`,
  `prop_rf_commute_needsPremise`, `prop_fm_duplicate_key`, the incremental
  clean-branch and seam witnesses, and the in-suite negative witness
  `prop_neg_sortMismatch` (`focal-syntax/test/Negative.hs`,
  `-fdefer-type-errors`).
- Changed `Focal.Parser`'s residual to a sealed type: `Residual`'s constructor is
  not exported, so a residual can only be obtained from `focusForest` and
  its frames agree with its coordinate by construction — the replacement laws,
  including the re-hit clause, hold over the whole plug domain. `residualCtx`
  and `residualSel` remain functions over it.
- Changed the parser's derivation to carry the expansion path: a kind
  re-entered at the same input position consumes nothing and fails, so a cyclic
  grammar reports no parse instead of diverging; a re-entry at a later
  position has consumed input and stays legal, so a productive right-recursive
  grammar still parses.
- Changed `Focal.Workflow`'s `workflowPlug` to require the replacement to carry
  the focused transition's name (the re-hit premise) before the validation gate
  runs; a name-changing replacement is rejected with the focus's index and the
  offered transition.
- Changed `Focal.Form`'s `validateForm` to report every failure — the
  per-field validation failures first, in field order, then the duplicate
  model-key collisions (one per colliding later field, in field order, reported
  as `FormError (fieldPath f) "duplicate model key: <key>"` instead of the last
  writer winning silently) — and to leave the snapshot untouched;
  `residuals` preserves the raw input of every failure, the collisions
  included, and the colliding fields are selected by position (two identical
  fields yield one error and one residual).
- Added the witnesses `prop_lovf_userLens` (the embedded lens pair's over-law),
  `prop_rd_redexF_pp` (the unit residual's overwrite law),
  `prop_dl_add_edit_refusal` (an edit at an already-claimed variable),
  `prop_fm_validate_form_every_failure` (every failure reported, the validation
  failures first) and `prop_fm_residuals_duplicate` (the collision's residual),
  `prop_ps_rehit` (the re-hit clause over the whole plug domain),
  `prop_ps_cycle_terminates` (a cyclic grammar terminating with no parse) and
  `prop_ps_recursive_grammar` (a productive right-recursive grammar parsing),
  `prop_wf_plug_name_premise` (the name premise on the plug).
- Strengthened the witnesses that could not fail: `prop_gen_rose_pg` (the
  re-hit clause, with a fresh replacement), `prop_rf_commute` (the commutation
  premise, on a content-bearing frame), `prop_wf_pg_name` (a name-preserving
  plug re-splits to the replacement), `prop_wf_reject` and `prop_wf_first_bad`
  (the gate's rejection branch, with a same-named but undeclared replacement),
  `prop_rd_redexF_plug` and `prop_rd_redexF_pg` (both focus sorts, not one
  hand-picked term), `prop_cs_rt_query` (a non-zero row provenance) and
  `prop_cs_pp_incremental` (a memo re-key that differs from the pre-update
  cell).
- Corrected the claim layer: the residual premise `c ∈ R(f)` is stated at every
  claim site — the conformance rows for `Focal.Generic`, `Focal.Syntax`,
  `Focal.Optional` and the core list, path and path-focus instances —
  `L-TVL` is stated at the `Focal` level (extensional, per
  `docs/foundation.md` §5), the effectful rung's GP is stated on the success
  domain, `Focal.Delta`'s `Either` channel is described as carrying only
  `NoSite` (the two-candidate `Clash` comes from the separate `conflict`
  query), and `Focal.Refactor`'s commutation premise is described as the
  caller's to check (`frameOccurs`; `plugRCtx` does not check it). The README's
  specialization table states the lens-like and redex residual cells
  accurately.
- Corrected the conformance matrix's instance shapes and witness names
  (`docs/conformance.md`): the type-changing `fstF`/`sndF` row is N/A for
  GP/PG/PP, `Focal.Partial` and `Focal.Optional` carry the over-law, the
  ill-sorted witness is the in-suite one, and the layers without a `splitF`
  are not input-invariance instances — each states its own input discipline
  instead.
- Test totals: the root suite has 140 properties; the per-package suites have
  8 (`focal-syntax`), 20 (`focal-redex`), 11 (`focal-refactor`), 9
  (`focal-delta`), 4 (`focal-incremental`), 9 (`focal-form`), 9
  (`focal-parser`), 4 (`focal-query`), 7 (`focal-workflow`) and 23
  (`focal-consistency`).
- Packaging: the ten packages publish at 0.2.0.0 with internal bounds
  `>= 0.2 && < 0.3`; removed the undeclared `src/Lib.hs`.
- Documentation: `docs/foundation.md` §1/§3, the conformance matrix, the
  README specialization tables, and the roadmap reflect the released
  surface. No `focal-core` API changes in this release.

## 0.1.0.0 - 2026-10-16

- Documentation layer revision: added `docs/foundation.md` (axiom A-LENS, L0–L6
  hierarchy, law vocabulary, contracts, representation ladder, defect log) and
  `docs/conformance.md` (instance × law matrix); reworked the README law
  chapter; rewrote the roadmap around law-id-tagged acceptance criteria; and
  corrected haddock/contract wording in `Focal.Core`, `Focal.List`, and
  `Focal.Zipper`. No behavior changes.

- P0 execution (ROADMAP 0b–0e, 0g): added `elementAt` (construction-time checked
  list focus); added dynamic `focusAt` and retired `safeFocusAt`/`unsafeFocusAt`;
  hid the `Focal` constructor behind `mkFocal`/`withFocal`; added
  `Focal.Interop` (`VLens`, `PStore`, `reifyVL`, `toVL`, `fromVL`, `normalize`);
  rewrote the test suite as 64 law-id-tagged properties (L-PG/L-PP/L-OVF
  witnesses added); added a doctest test-suite gate and a minimal CI workflow;
  aligned docs, README, and roadmap. Breaking API: `Focal(..)` is now `Focal` +
  `mkFocal`/`withFocal`; `safeFocusAt`/`unsafeFocusAt` removed; `base` bound
  raised to `>= 4.16`.

- Added `Focal.Partial` (`FocusingE`, `idE`, `composeE`, `overE`, `toPartial`,
  `toStoreE`, `fromStoreE`): failures in `Either` return values, ordered
  composition, success-premise laws, partial Store reading. Test suite: 78
  law-id-tagged properties.

- Added `elementE` (`Focal.List.ListError`: `NegativeIndex`/`PastEnd`): the
  failure-channel list focus (per-call index check; total plug). Suite at 85
  properties; docs counts updated.

- Added `Focal.Effectful` (`FocusingM`, `idM`, `composeM`, `overM`,
  `toEffectful`, `toEffectfulE`, `storeM`, `fromStoreM`): both legs in a monad
  (failure, validation, logging, state); GP/PG as Kleisli equations, preserved
  by composition for every monad; PP per instance. Test suite: 136
  law-id-tagged properties.

- Tightened the effectful PP statement to the replay-prefix equation (the
  first write is shared, so failures short-circuit together and no success
  premise is needed); discriminators extended (logging and sign-flipping
  residuals fail it; the prefix-less strengthening stays pinned as false).
  Law tables now count the effectful witnesses: 136 properties; the module
  haddock and README phrasing use the replay-prefix wording.

- Added residual-shape helpers (`Residual2`, `Residual3`, `flatten`, `unflatten`,
  `prettyResidual`, `prettyResidual3`) to `Focal.Core`: canonical right-nested
  residual pairs, mutually-inverse reassociation, and debug renderings. Suite at
  136 properties.

- Stated the type-changing clause forms in `docs/foundation.md` §3 (per-clause
  side conditions; no round-trip is statable when `t ≁ s`) with witnesses for
  product components at changed types and a two-stage composed chain
  (`prop_tc_*`). Suite at 136 properties.

- Added `focusAtE` (`PathError`, `Focal.Zipper`): the failure-channel dynamic
  path focus — construction is total, `splitE` re-navigates per call and
  reports the first missing step as `Left (PathError i)`, `plugE` is total.
  Suite at 136 properties.

- Added the navigation algebra to `Focal.Zipper`: `childOf` (frames record
  their selector), `pathOf` (context stack to root-first path), `framesAt`
  (path to context stack), `lcaPath` (longest common path prefix) — with
  round-trip, composition, LCA prefix/maximality, and `childOf`/`descend`-inverse
  witnesses. Suite at 136 properties.

- Stated the residual representation-equivalence rules in `docs/foundation.md`
  §5: putback-equivalence as the law-layer residual identity between independently
  chosen representations (the definitional pairing conventions being the only
  other residual identities the laws fix), the
  geometry-vs-putback-function distinction, the admissible-discard rules for
  re-representation, and the registered boundary that no total residual
  minimization exists (function equality is undecidable).

- Added `Focal.Generic` (`Derivative1`, `Ctx1`, `genericSplit1`, `genericPlug1`,
  `genericFocus`): one-hole contexts of the leftmost direct type-parameter
  occurrence, derived from `Generic1` representations; `Rose` migrated with
  GP/PG/PP witnesses. Suite at 136 properties.

- Added `Focal.Optional` (`FocusingO`, `idO`, `composeO`, `overO`,
  `toOptional`): zero-or-one foci where a miss is absence with pass-through
  update — distinct from the failure channel; hit-domain GP/PG/PP plus miss,
  short-circuit, and composition witnesses. Suite at 136 properties.

