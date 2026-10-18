# Focal — Conformance Matrix

Per-instance verdicts against the law vocabulary in
[`foundation.md`](foundation.md) §3, for the `focal-core-0.2.0.0` working tree
(2026-10-18). Witnesses refer to each package's suite as named in its row;
the root suite is [`../test/Spec.hs`](../test/Spec.hs).

Legend: **✓** holds on the declared domain · **✗** fails · **cnd** conditional
on the obligation the instance embeds · **def** holds by definition
(non-empirical) · **N/A** not well-formed for this instance's shape · **—**
not an instance (projection).

| Instance | L-GP | L-PG | L-PP | L-OVF | Input invariance | Domain & failure modes | Witnesses | Notes |
|---|---|---|---|---|---|---|---|---|
| `idF` | def | def | def | def | ✓ | total; no failure mode | `prop_lgp_idF`, `prop_lassoc_idChain`, `prop_lunit_*` | definitional — no empirical content |
| `fstF`, `sndF` | ✓ | ✓ | ✓ | ✓ | ✓ | total; no failure mode | `prop_lgp_fstF`, `prop_lgp_sndF`, `prop_lpg_fstF`, `prop_lpg_sndF`, `prop_lpp_fstF`, `prop_lovf_fstF`, `prop_lovf_sndF`, `prop_lassoc_tupleChain`, `prop_lunit_left_fst`, `prop_lunit_right_fst`, `prop_concrete_tuple` | type-changing shapes: GP/PG/PP N/A (foundation §2) |
| `pureF`, `fromLensLike` | cnd | cnd | cnd | cnd | ✓ | inherited from the embedded `view`/`set` | `prop_lgp_pureF`, `prop_lpg_userLens`, `prop_lpp_userLens` | lawful iff the embedded pair is; non-trivial lawful instance (`userLens`) and unlawful counterexamples (`prop_disc_*`) tested; L-OVF needs the pair's put-get/put-put |
| `elementF` | ✓ | ✓ | ✓ | ✓ | ✓ | declared domain `0 <= n < length xs`; outside it, delayed `error` from `splitF` | `prop_lgp_list`, `prop_lpg_elementF`, `prop_lpp_list`, `prop_lovf_list`, `prop_elementf_negative` | construction-time full check is `elementAt`; failure-channel variant is `elementE` |
| `unsafeElementF` | ✓ | ✓ | ✓ | ✓ | ✓ | `0 <= n`; immediate `error` for `n < 0`; delayed `error` for `n >= length xs` | `prop_lgp_list`, `prop_lpg_unsafeElementF`, `prop_lpp_list`, `prop_lovf_list`, `prop_lovf_composed`, `prop_concrete_list` | in-domain behavior identical to `elementF` |
| `fromZip` | ✓\* | ✗ | ✓† | ✗ | ✗ (exempt) | total; no failure mode | `prop_lgp_roseZip`, `prop_lgp_binZip`, `prop_lpp_fromZip`, `prop_lunit_left_zipper`, `prop_lunit_right_zipper`, `prop_occ_rose`, `prop_occ_binTree`, `prop_zip_multilevel`, `prop_contract_zip_ignoresInput`, `prop_contract_zip_pgCaptured`, `prop_nav_*` | **snapshot constructor** (foundation §4.2): `splitF` ignores its argument; snapshot contracts pinned by `prop_contract_zip_*` |
| `focusAt` | ✓ | ✓ | ✓ | ✓ | ✓ | declared domain: trees in which `path` exists; construction returns `Nothing` if the path is absent in the given tree; `splitF` on a later tree lacking the path raises a delayed `error` | `prop_focusat_*`, `prop_focusatE_*` | dynamic (input-invariant); path-validity premise per tree (foundation §2); failure-channel counterpart `focusAtE` reports the first missing path step as `Left (PathError i)` |
| `elementAt` | ✓ | ✓ | ✓ | ✓ | ✓ | domain `0 <= n < length xs` of the construction list; `Nothing` otherwise; the returned `Focusing` keeps `elementF`'s delayed error off-domain | `prop_elementat_*` | checked construction-time variant of `elementF` |
| `elementE` | ✓ | ✓ | ✓ | ✓ | ✓ | no construction failure; `splitE` checks the supplied list: `Left (NegativeIndex n)` for `n < 0`, `Left (PastEnd n)` past the end; `plugE` total | `prop_elementE_*` | failure-channel variant of `elementF`; domain `0 <= n < length xs` re-checked per call |
| `overFM`, `toStoreLike` | — | — | — | — | — | `overFM`: Functor-level, no law beyond the functor laws; `toStoreLike`: projection | (none — no law claimed) | L-NORM / L-TVL are provided by `Focal.Interop` (shipped) |
| `Focal` | N/A | N/A | N/A | N/A | — | no exported operations tested directly; laws at the `Focal` level are extensional (foundation §5) | `prop_lnorm_*`, `prop_ltvl_*` | constructor hidden; `mkFocal`/`withFocal` + `Focal.Interop` shipped |
| `Focal.Interop` (`toVL`/`fromVL`/`normalize`) | — | — | — | — | — | rank-2 CPS via `mkFocal`/`withFocal`; extensional only (foundation §5) | `prop_lnorm_*`, `prop_ltvl_*` | conversions are extensional; residual not recoverable |
| `Focal.Partial` (`FocusingE`, `composeE`, `overE`, `toStoreE`) | — | — | — | — | — | failures in return values; laws carry success premises (foundation §3) | `prop_lgpE_*`, `prop_lpgE_*`, `prop_lppE_*`, `prop_lovfE_*`, `prop_scE_*`, `prop_embE_compose`, `prop_storeE_roundtrip` | rank ≤ 1; `toStoreE` extensional; `prop_discE_*` pins the premise necessity |
| `Focal.Optional` (`FocusingO`, `composeO`, `overO`, `toOptional`) | ✓ | ✓ | ✓ | — | ✓ | absence ≠ failure: a miss is `Nothing` with no payload; the miss laws have defined behavior (foundation §3) | `prop_opt_*` | zero-or-one foci; hit-domain GP/PG/PP plus pass-through miss; `composeO` short-circuits on the first miss |
| `Focal.Effectful` (`FocusingM`, `composeM`, `overM`, `storeM`) | — | — | — | — | — | GP/PG as Kleisli equations (PG in continuation form); PP as the replay-prefix equation, per instance (foundation §3) | `prop_lgpM_*`, `prop_lpgM_*`, `prop_lppM_*`, `prop_compM_*`, `prop_lunitM_*`, `prop_lassocM_*`, `prop_storeM_*`, `prop_embM*`, `prop_discM_*` | GP/PG composition closure holds for every monad; `prop_discM_*` pins the forced premises |
| `Focal.Generic` (`Derivative1`, `Ctx1`, `genericSplit1`, `genericPlug1`, `genericFocus`) | ✓ | ✓ | ✓ | — | ✓ | direct occurrences only (leftmost); a value whose parameter has no reachable direct occurrence is outside the declared domain — `genericSplit1` returns `Nothing`, `splitF` raises the registered delayed `error` (foundation §4.1) | `prop_gen_split_plug`, `prop_gen_rose_gp`, `prop_gen_rose_pg`, `prop_gen_rose_pp` | one-hole contexts derived from `Generic1`; `Rose` migrated (root label) |
| `Focal.Syntax` (`Stack i j`, `splitStack`, `plugStack`) | ✓ | ✓ | ✓ | — | ✓ | split needs the target sort's `TyRep`; a wrong-sort replacement is a type error (negative witness `focal-syntax/negative/SortMismatch.hs`) | `prop_tm_gp`, `prop_tm_path`, `prop_tm_pp`; the negative-witness command | sort-indexed contexts; `FocusingO` rung; suite lives in the `focal-syntax` package |
| `Focal.Redex` (`decompose`, `Decomp`, `step`, `redexF`) | ✓ | — | — | — | ✓ | closed terms (`'[]` context); `decompose` is total — the `RVar` case is uninhabited and closes by `EmptyCase`; `redexF` focuses whole-root redexes (its focus sort is fixed, so redexes below the root are reached by `decompose` alone) | `prop_rd_decompose_*`, `prop_rd_plug_*`, `prop_rd_step_*`, `prop_rd_redexF_*` (concrete); `prop_rd_plug`, `prop_rd_progress`, `prop_rd_norm`, `prop_rd_head` (laws) | GP direction: plug-after-decompose (`plugO redexF e r = plugEval e (redexTerm r)`); laws: plug-after-decompose, progress (step defined exactly off the values), normalization to a value; type preservation is the L0 result sort of `step` (`Rm '[] t -> Maybe (Rm '[] t)`), by construction — no property witnesses it; deterministic strategy pinned by the concrete canonicity regressions; `plugEval`/`contract` carry no strategy; suite lives in the `focal-redex` package |
| `Focal.Refactor` (`RCtx`, `plugRCtx`, `substitute`, `weakenFin`/`weakenRm`, `rename`, `abstract`, `inlineAt`, `etaExpand`) | — | — | — | — | ✓ | path-transported edits: the root variable's image under `weakenFin` must not occur in the path's frame terms for the commutation premise (checked per call, `frameOccurs`); capture avoidance is by construction (the replacement weakens under every binder) and witnessed directly | `prop_rf_no_capture`, `prop_rf_commute` (three path shapes), `prop_rf_substitute_id`, `prop_rf_substitute_hits`, `prop_rf_rename_involution`, `prop_rf_abstract_unit`, `prop_rf_abstract_var`, `prop_rf_eta_roundtrip`, `prop_rf_inline_hits` | refactoring layer over the de Bruijn core; `etaExpand` is the grammar's case-analogue (the core has no case constructs); suite lives in the `focal-refactor` package |
| `Focal.Delta` (`Edit`, `Patch`, `applyEdit`/`applyPatch`, `reindexEdit`/`reindexPatch`, `patchFocus`, `Delta`, `Conflict` (`Clash`/`NoSite`), `renameEdit`/`inlineEdit` bridge) | — | — | — | — | ✓ | application is always total (substitution); the failure channel reports the zero-candidate case (`NoSite`) and the two-candidate case (`Clash`); patches refuse edits at claimed variables (`addEdit` returns `Nothing`); the composition premise (second block independent of the first's variable) is checked per call | `prop_dl_hit_result` (evidence preserved, two sorts), `prop_dl_no_site`, `prop_dl_reindex` (substitution-commutes-with-weakening at the delta level), `prop_dl_delta_on`, `prop_dl_rename_bridge` (fresh-target premise; the transposition is a one-point edit exactly then — the swap case witnessed by `prop_dl_rename_swap`), `prop_dl_inline_bridge` (edit-layer inlining against `contract`, cross-layer) | patch layer over the de Bruijn core; merge stays out of v1; suite lives in the `focal-delta` package |
| `Focal.Incremental` (`traceDeps`, `Memo`, `invalidatedBy`, `memoRead`/`memoWrite`, `invalGraph`, `incrementalPlug`, `OutputDelta` (`Clean`/`Recomputed`), `memoUpdate`, `firedEdges`) | — | — | — | — | ✓ | single-cell v1: one memo, one trace; the recomputation seam is a caller-supplied patch-to-term function (v1 default `recomputePatch`); invalidation is positional over the claimed-vs-read sets; no complexity claims (costs would bind to a persistent-tree representation, out of v1 scope) | `prop_inc_invalidate` (claimed reads invalidate; recomputed output is the patched term), `prop_inc_clean` (clean patches read through), `prop_inc_memo_update` (re-keying), `prop_inc_fired` (fired edges track the reads) | incremental layer over the patch layer; suite lives in the `focal-incremental` package |
| `Focal.Form` (`WidgetPath`, `FormError`, `Field`, `validateField`, `ModelSnapshot`, `fieldKey`, `validateForm`, `FieldResidual`, `revalidate`, `residuals`, `putback`/`PutbackResult`/`applyOne`) | — | — | — | — | ✓ | validate-then-apply (C7 route): all-or-nothing form validation reports every failure and leaves the snapshot untouched; a validated field overwrites its model key, untouched keys persist; error provenance is the widget path, carried by the field residual (re-validation on transport keeps the original path); unknown field kinds fail at the boundary | `prop_fm_putback_ok` (valid edit applies by key), `prop_fm_putback_error` (error with residual), `prop_fm_putback_overwrites`, `prop_fm_revalidate_provenance`, `prop_fm_validate_form_allornothing` | form layer over the patch layer (v1: string-keyed model); suite lives in the `focal-form` package |
| `Focal.Parser` (`Grammar`, `parse`/`parseOne`, `parseAll` (pruned enumeration), `ambiguities`, `Selection`/`select`, `Forest` provenance, `focusForest`/`plugForest`, `Residual` (frame list + selection), `reparseReport`) | — | — | — | — | ✓ | v1 domain is ambiguity-free; the selection coordinate is reported as absent when out of range (never clamped); the residual is a frame list (not a tree) carrying every ancestor's provenance; ambiguity (multi-alternative kinds) is detected and reported, never resolved; replacement-induced parse-set changes are the reparse report | `prop_ps_focus_roundtrip` (plug-after-focus rebuilds), `prop_ps_selection_preserved` (the residual's coordinate re-selects the replacement), `prop_ps_provenance_preserved` (ancestors survive; the new node's provenance is its own), `prop_ps_reparse_report` (the alternatives minus the claimed one) | parser layer over the sort-indexed language; laws are stated relative to the selection (C3); suite lives in the `focal-parser` package |
| `Focal.Query` (`Table`, `Projection`/`project`, `ViewRow` provenance, `JoinWitness`, `joinView`, `Candidate`, `Policy`, `Putback`, `putbackRow`, `RelDelta`, `relPutback`) | — | — | — | — | ✓ | projection provenance is the source row index; the join witness carries a `Maybe` lookup row (no sentinels; unmatched rows pass through); the view-update policy is an ordered candidate list — zero candidates report the empty ambiguity, several report the ordered list, never a silent choice (C4 route) | `prop_rq_ok` (one candidate: the delta carries the row's provenance and the candidate's column/value), `prop_rq_ambiguous` (ordered ambiguity), `prop_rq_none` (empty ambiguity), `prop_rq_provenance` (the second view row targets its own source row) | relational layer over the sort-indexed language; suite lives in the `focal-query` package |
| `Focal.Workflow` (`Workflow`, `Run`, `TransitionContext`, `splitRun`/`plugRun`, `Compensation`, `RollbackPlan`/`rollbackPlan`, `GateVerdict`/`validateGate`, `InvalidTransition`, `workflowPlug`) | — | — | — | — | ✓ | a labelled transition system (static structure only, no liveness claims); the rollback plan composes declared compensators in reverse run order — a preorder span, not an inverse; uncompensated transitions are reported by name; the gate accepts exactly when every step is declared and reports the FIRST offending step with its index, never silently dropping it (validate-then-apply) | `prop_wf_accept` (a declared replacement is accepted with the plugged run), `prop_wf_reject` (an undeclared replacement reports its step and transition), `prop_wf_first_bad` (the gate reports the first offending step), `prop_wf_untouched` (a rejected replacement leaves the context validating) | workflow layer over the patch layer (C5 route); suite lives in the `focal-workflow` package |

Verdict footnotes:

- **Released surface** — `focal-0.2` (2026-10-18): every row below is a
  released verdict at version 0.2.0.0; each package's suite is the witness
  set named in its row.

- **✓\*** — GP holds only for the source the snapshot was built from (that is
  the tree `plugF` rebuilds). For any other source the round-trip fails; the
  shipped tests apply snapshots only to their own tree.
- **✓†** — PP is vacuous for snapshots: `splitF` is constant, so `c'` is always
  the captured stack and the equation holds by construction (`prop_lpp_fromZip`
  pins this). It is not evidence of overwrite behavior on arbitrary sources.
- `fromZip`'s PG fails in general: `plugF` produces `rebuild b c`, and
  re-splitting that value returns the captured focus, not `b`.
- `fromZip`'s L-OVF fails for the same reason: after one edit, the re-split
  focus is the captured one, so a second edit ignores the first.

## Coverage honesty

Reviewed property-by-property against the working tree (**136 properties**,
plus the doctest suite):

- **L-GP: 15 of 136** (`prop_lgp_*` 8, partial `prop_lgpE_*` 3, effectful `prop_lgpM_*` 4).
- **L-PG: 13 of 136** (`prop_lpg_*` 7, partial `prop_lpgE_*` 2, effectful `prop_lpgM_*` 4).
- **L-PP: 9 of 136** (`prop_lpp_*` 5, partial `prop_lppE_*` 2, effectful `prop_lppM_*` 2;
  one trivially-satisfied snapshot case, `prop_lpp_fromZip`).
- **L-OVF: 5 of 136** (`prop_lovf_*` — four instances plus the partial
  success-prefix case).
- **L-ASSOC: 3 of 136** (`prop_lassoc_*`); **L-UNIT: 6 of 136** (`prop_lunit_*`).
- **L-NORM: 2 of 136** (`prop_lnorm_*`); **L-TVL: 2 of 136** (`prop_ltvl_*`).
- **Partial channel: 6 of 136** (`prop_scE_*`, `prop_embE_compose`,
  `prop_storeE_roundtrip`, `prop_discE_*`).
- **`elementE` contract: 7 of 136** (`prop_elementE_*`).
- **Effectful rung (non-law): 12 of 136** (`prop_compM_*`, `prop_lunitM_*`,
  `prop_lassocM_*`, `prop_storeM_*`, `prop_embM*`, `prop_discM_*`).
- **Residual shape: 2 of 136** (`prop_flatten_inverse`, `prop_unflatten_inverse`).
- **Type-changing fragment: 5 of 136** (`prop_tc_*`).
- **`focusAtE` contract: 5 of 136** (`prop_focusatE_*`).
- **Navigation algebra: 7 of 136** (`prop_nav_*`).
- **Generic derivation: 4 of 136** (`prop_gen_*`).
- **Optional focus: 6 of 136** (`prop_opt_*`).
- **Typed syntax (focal-syntax suite): 3 properties** (`prop_tm_*`) — registered
  per package; the root total stays 136; the frozen vocabulary is exercised
  cross-package by the consistency suite below.
- **Cross-package consistency (focal-consistency suite): 23 properties** — one
  group per frozen §3 law-id (`L-GP`, `L-PG`, `L-PP`, `L-OVF`, `L-ASSOC`,
  `L-UNIT`, `L-NORM`, `L-TVL`) plus the registered channel families and domain
  round trips, each witness running through a package's public surface (all
  ten packages covered); registered as its own package; the root total stays
  136.
- **Redex loop (focal-redex suite): 18 properties** (`prop_rd_*`) — 14 concrete
  regressions (decompose/plug/step plus the `redexF` rung trio) and 4 laws
  (plug-after-decompose, progress, normalization, head step = beta);
  registered per package; the root total stays 136.
- **Refactoring layer (focal-refactor suite): 9 properties** (`prop_rf_*`) —
  substitution identity, hit/non-hit equations, no-capture under a fresh
  binder, substitution-commutes-with-path, the rename involution, the
  abstract-then-apply round trips, and the operation round trips
  (eta-expansion, inline); registered per package; the root total stays 136.
- **Patch layer (focal-delta suite): 7 properties** (`prop_dl_*`) — patch-focus
  hits with evidence preservation, the zero-candidate equation,
  substitution-commutes-with-weakening, evidence travel, and the
  refactoring-bridge round trips; registered per package; the root total
  stays 136.
- **Incremental layer (focal-incremental suite): 4 properties** (`prop_inc_*`)
  — invalidation on claimed reads, clean read-through, memo re-keying, and
  fired-edge tracking; registered per package; the root total stays 136.
- **Form layer (focal-form suite): 5 properties** (`prop_fm_*`) — the
  validate-then-apply pipeline: valid edits apply by key, failures report
  the error with the residual, key overwrite, provenance-preserving
  re-validation, and all-or-nothing form validation; registered per
  package; the root total stays 136.
- **Parser layer (focal-parser suite): 4 properties** (`prop_ps_*`) — the
  forest focus: plug-after-focus rebuilds, the residual's coordinate
  re-selects the replacement, ancestor provenance survives, and the
  reparse report computes the parse-set change; registered per package;
  the root total stays 136.
- **Query layer (focal-query suite): 4 properties** (`prop_rq_*`) — the
  policy-ordered relational putback: one candidate applies with the row's
  provenance, several report the ordered ambiguity, zero reports the
  empty ambiguity, and provenance drives the delta's row; registered per
  package; the root total stays 136.
- **Workflow layer (focal-workflow suite): 4 properties** (`prop_wf_*`) —
  the transition-validation plug: acceptance of declared replacements,
  rejection with the offending step, first-offending-step reporting, and
  the untouched-context guarantee; registered per package; the root total
  stays 136.
- The remaining 27 properties: 3 occurrence≠value corollaries, 5 zipper
  law/navigation tests, 2 snapshot contracts (`prop_contract_zip_*`),
  2 law discriminators (`prop_disc_*`), 8 `focusAt` tests, 3 `elementAt` tests,
  2 concrete regressions, 1 `elementF` contract test, 1 edit-independence
  observation.
