# Focal — Conformance Matrix

Per-instance verdicts against the law vocabulary in
[`foundation.md`](foundation.md) §3, for the `focal-core-0.2.0.0` working tree
(2026-10-20). Witnesses refer to each package's suite as named in its row;
the root suite is [`../test/Spec.hs`](../test/Spec.hs).

Legend: **✓** holds on the declared domain · **✗** fails · **cnd** conditional
on the obligation the instance embeds · **def** holds by definition
(non-empirical) · **N/A** not well-formed for this instance's shape · **—**
not an instance (projection).

| Instance | L-GP | L-PG | L-PP | L-OVF | Input invariance | Domain & failure modes | Witnesses | Notes |
|---|---|---|---|---|---|---|---|---|
| `idF` | def | def | def | def | ✓ | total; no failure mode | `prop_lgp_idF`, `prop_lassoc_tupleChain`, `prop_lunit_*`; `prop_lassoc_residual` pins the reassociation | definitional — no empirical content |
| `fstF`, `sndF` | N/A | N/A | N/A | ✓ | ✓ | total; no failure mode | `prop_lgp_fstF`, `prop_lgp_sndF`, `prop_lpg_fstF`, `prop_lpg_sndF`, `prop_lpp_fstF`, `prop_lovf_fstF`, `prop_lovf_sndF`, `prop_lassoc_tupleChain`, `prop_lunit_left_fst`, `prop_lunit_right_fst`, `prop_concrete_tuple` | type-changing shapes: GP/PG/PP N/A (foundation §2); the mono instantiation (`x = a`) is statable and is what the listed witnesses exercise |
| `pureF`, `fromLensLike` | cnd | cnd | cnd | cnd | ✓ | inherited from the embedded `view`/`set` | `prop_lgp_pureF`, `prop_lpg_userLens`, `prop_lpp_userLens`, `prop_lovf_userLens` | lawful iff the embedded pair is; non-trivial lawful instance (`userLens`) and unlawful counterexamples (`prop_disc_*`) tested; L-OVF needs the pair's put-get/put-put |
| `elementF` | ✓ | cnd | cnd | ✓ | ✓ | declared domain `0 <= n < length xs`; outside it, delayed `error` from `splitF`; L-PG and L-PP hold on the residual image (`c ∈ R(f)`) — the residual type is wider than the split image, and an off-image residual re-splits to a different focus | `prop_lgp_list`, `prop_lpg_elementF`, `prop_lpp_list`, `prop_lovf_list`, `prop_elementf_negative` | construction-time full check is `elementAt`; failure-channel variant is `elementE` |
| `unsafeElementF` | ✓ | cnd | cnd | ✓ | ✓ | `0 <= n`; immediate `error` for `n < 0`; delayed `error` for `n >= length xs`; L-PG and L-PP hold on the residual image (`c ∈ R(f)`) — the residual type is wider than the split image, and an off-image residual re-splits to a different focus | `prop_lgp_list`, `prop_lpg_unsafeElementF`, `prop_lpp_list`, `prop_lovf_list`, `prop_lovf_composed`, `prop_concrete_list` | in-domain behavior identical to `elementF` |
| `fromZip` | ✓\* | ✗ | ✓† | ✗ | ✗ (exempt) | total; no failure mode | `prop_lgp_roseZip`, `prop_lgp_binZip`, `prop_lpp_fromZip`, `prop_lunit_left_zipper`, `prop_lunit_right_zipper`, `prop_occ_rose`, `prop_occ_binTree`, `prop_zip_multilevel`, `prop_contract_zip_ignoresInput`, `prop_contract_zip_pgCaptured`, `prop_nav_*` | **snapshot constructor** (foundation §4.2): `splitF` ignores its argument; snapshot contracts pinned by `prop_contract_zip_*` |
| `focusAt` | ✓ | cnd | cnd | ✓ | ✓ | declared domain: trees in which `path` exists; construction returns `Nothing` if the path is absent in the given tree; `splitF` on a later tree lacking the path raises a delayed `error`; L-PG and L-PP hold on the residual image (`c ∈ R(f)`) — the frame-stack residual is wider than the split image, and an off-image residual re-splits to a different focus | `prop_focusat_*`, `prop_focusatE_*` | dynamic (input-invariant); path-validity premise per tree (foundation §2); failure-channel counterpart `focusAtE` reports the first missing path step as `Left (PathError i)` |
| `elementAt` | ✓ | cnd | cnd | ✓ | ✓ | domain `0 <= n < length xs` of the construction list; `Nothing` otherwise; the returned `Focusing` keeps `elementF`'s delayed error off-domain; L-PG and L-PP hold on the residual image (`c ∈ R(f)`) — the residual type is wider than the split image, and an off-image residual re-splits to a different focus | `prop_elementat_*` | checked construction-time variant of `elementF` |
| `elementE` | ✓ | cnd | cnd | ✓ | ✓ | no construction failure; `splitE` checks the supplied list: `Left (NegativeIndex n)` for `n < 0`, `Left (PastEnd n)` past the end; `plugE` total; L-PG and L-PP hold on the residual image (`c ∈ R(f)`) — the residual type is wider than the split image, and an off-image residual re-splits to a different focus | `prop_elementE_*`, `prop_discE_offImage` (the shipped discriminator for the failure channel) | failure-channel variant of `elementF`; domain `0 <= n < length xs` re-checked per call |
| `overFM`, `toStoreLike` | — | — | — | — | — | `overFM`: Functor-level, no law beyond the functor laws; `toStoreLike`: projection | (none — no law claimed) | L-NORM / L-TVL are provided by `Focal.Interop` (shipped) |
| `Focal` | N/A | N/A | N/A | N/A | — | the `Focal`-level operations are exercised extensionally; the laws at the `Focal` level are extensional (foundation §5) | `prop_lnorm_*`, `prop_ltvl_*` (including `prop_lnorm_overFocal`) | constructor hidden; `mkFocal`/`withFocal` + `Focal.Interop` shipped |
| `Focal.Interop` (`toVL`/`fromVL`/`normalize`) | — | — | — | — | — | rank-2 CPS via `mkFocal`/`withFocal`; extensional only (foundation §5) | `prop_lnorm_*`, `prop_ltvl_*` | conversions are extensional; residual not recoverable |
| `Focal.Partial` (`FocusingE`, `composeE`, `overE`, `toStoreE`) | ✓ | ✓ | ✓ | ✓ | — | failures in return values; GP, PG and PP are read on the success domain with the residual premise `c ∈ R(f)` (foundation §3) | `prop_lgpE_*`, `prop_lpgE_*`, `prop_lppE_*`, `prop_lovfE_*`, `prop_scE_*`, `prop_embE_compose`, `prop_storeE_roundtrip` | rank ≤ 1; `toStoreE` extensional; `prop_discE_*` pins the premise necessity |
| `Focal.Optional` (`FocusingO`, `composeO`, `overO`, `toOptional`) | ✓ | ✓ | ✓ | ✓ | ✓ | absence ≠ failure: a miss is `Nothing` with no payload; the miss laws have defined behavior (foundation §3); on the hit domain the laws hold with `c ∈ R(f)`, and the over-law holds on the hit domain | `prop_opt_*`, `prop_cs_lovf_hit`, `prop_cs_lovf_hom` (in the `focal-consistency` suite) | zero-or-one foci; hit-domain GP/PG/PP plus pass-through miss; `composeO` short-circuits on the first miss |
| `Focal.Effectful` (`FocusingM`, `composeM`, `overM`, `storeM`) | ✓ | ✓ | ✓ | — | — | GP on the success domain (when `splitM` succeeds) and PG as Kleisli equations (PG in continuation form), both with the residual premise `c ∈ R(f)`; PP as the replay-prefix equation, per instance (foundation §3) | `prop_lgpM_*`, `prop_lpgM_*`, `prop_lppM_*`, `prop_compM_*`, `prop_lunitM_*`, `prop_lassocM_*`, `prop_storeM_*`, `prop_embM*`, `prop_discM_*` | GP/PG composition closure holds for every monad; `prop_discM_*` pins the forced premises; no over-law is claimed for this rung (no witness) |
| `Focal.Generic` (`Derivative1`, `Ctx1`, `genericSplit1`, `genericPlug1`, `genericFocus`) | ✓ | cnd | cnd | — | ✓ | direct occurrences only (leftmost); a value whose parameter has no reachable direct occurrence is outside the declared domain — `genericSplit1` returns `Nothing`, `splitF` raises the registered delayed `error` (foundation §4.1); L-PG and L-PP hold on the residual image (`c ∈ R(f)`) — the residual type `Ctx1` is wider than the split image (the product's right-hand branch is never produced by the split), and an off-image residual re-splits to a different focus | `prop_gen_split_plug`, `prop_gen_rose_gp`, `prop_gen_rose_pg`, `prop_gen_rose_pp` | one-hole contexts derived from `Generic1`; `Rose` migrated (root label) |
| `Focal.Syntax` (`Stack i j`, `splitStack`, `plugStack`) | ✓ | cnd | cnd | — | ✓ | split needs the target sort's `TyRep`; a wrong-sort replacement is a type error (the in-suite ill-sorted witness `prop_neg_sortMismatch`, module `focal-syntax/test/Negative.hs`, compiled with `-fdefer-type-errors`); L-PG and L-PP hold on the residual image (`c ∈ R(f)`) — the residual type `Stack i j` is wider than the split image, and an off-image residual re-splits to a different focus | `prop_tm_gp`, `prop_tm_path`, `prop_tm_pp`, `prop_tm_offImage` (the shipped discriminator) | sort-indexed contexts; `FocusingO` rung; suite lives in the `focal-syntax` package |
| `Focal.Redex` (`decompose`, `Decomp`, `step`, `redexF`) | ✓ | ✓ | ✓ | — | ✓ | closed terms (`'[]` context); `decompose` is total — the `RVar` case is uninhabited and closes by `EmptyCase`; `redexF` focuses whole-root redexes (its focus sort is fixed, so redexes below the root are reached by `decompose` alone); its residual is the unit — the unit is the whole residual image, so the replacement laws hold over the entire plug domain with no premise | `prop_rd_decompose_*`, `prop_rd_plug_*`, `prop_rd_step_*`, `prop_rd_redexF_*` (concrete), `prop_rd_redexF_pg`, `prop_rd_redexF_pp`; `prop_rd_plug`, `prop_rd_progress`, `prop_rd_norm`, `prop_rd_head` (laws) | GP direction: plug-after-decompose (`plugO redexF () r = cbvRedexTerm r`); the evaluation-context fill belongs to the wider `decompose`/`plugEval` loop, whose residual is `EvalCtx`; laws: plug-after-decompose, progress (step defined exactly off the values), normalization to a value; type preservation is the L0 result sort of `step` (`Rm '[] t -> Maybe (Rm '[] t)`), by construction — no property witnesses it; deterministic strategy pinned by the concrete canonicity regressions; `plugEval`/`contract` carry no strategy; suite lives in the `focal-redex` package |
| `Focal.Refactor` (`RCtx`, `plugRCtx`, `substitute`, `weakenFin`/`weakenRm`, `rename`, `abstract`, `inlineAt`, `etaExpand`, `renderSpans`) | — | — | — | — | — | path-transported edits: the root variable's image under `weakenFin` must not occur in the path's frame terms for the commutation premise; the premise is the caller's to check (`frameOccurs`) — `plugRCtx` does not check it, so an unchecked call is outside the lemma's premise; capture avoidance is by construction (the replacement weakens under every binder) and witnessed directly; `renderSpans` reports global half-open text offsets; input discipline: the focus operation is a context fill (`plugRCtx`) — it depends on the path's frame terms and the replacement, and on no source whole | `prop_rf_no_capture`, `prop_rf_commute` (four path shapes), `prop_rf_commute_needsPremise` (the premise is load-bearing), `prop_rf_substitute_id`, `prop_rf_substitute_hits`, `prop_rf_rename_involution`, `prop_rf_abstract_unit`, `prop_rf_abstract_var`, `prop_rf_eta_roundtrip`, `prop_rf_inline_hits`, `prop_rf_spans_global` (global text offsets pinned) | refactoring layer over the de Bruijn core; `etaExpand` is the grammar's case-analogue (the core has no case constructs); suite lives in the `focal-refactor` package |
| `Focal.Delta` (`Edit`, `Patch`, `applyEdit`/`applyPatch`, `reindexEdit`/`reindexPatch`, `patchFocus`, `Delta`, `Conflict` (`Clash`/`NoSite`), `renameEdit`/`inlineEdit` bridge) | — | — | — | — | — | application is always total (substitution); the `Either` failure channel of the patch focus carries only the zero-candidate report (`NoSite`), while the two-candidate report (`Clash`) comes from the separate `conflict` query; patches refuse edits at claimed variables (`addEdit` returns `Nothing`); `composeEdit` transports the second block (`applyEdit e1 a'`) — not the sequential-application law (pinned by `prop_dl_compose_divergence`); input discipline: the focus operation is `patchFocus` — it depends on the supplied term (the edit's variable must occur in it) and on the edit, and on nothing else | `prop_dl_hit_result` (evidence preserved, two sorts), `prop_dl_no_site`, `prop_dl_reindex` (substitution-commutes-with-weakening at the delta level), `prop_dl_delta_on`, `prop_dl_compose_divergence` (the transport boundary), `prop_dl_add_edit_refusal` (an edit at an already-claimed variable is refused), `prop_dl_rename_bridge` (fresh-target premise; the transposition is a one-point edit exactly then — the swap case witnessed by `prop_dl_rename_swap`), `prop_dl_inline_bridge` (edit-layer inlining against `contract`, cross-layer) | patch layer over the de Bruijn core; merge stays out of v1; suite lives in the `focal-delta` package |
| `Focal.Incremental` (`traceDeps`, `Memo`, `invalidatedBy`, `memoRead`/`memoWrite`, `invalGraph`, `incrementalPlug`, `OutputDelta` (`Clean`/`Recomputed`), `memoUpdate`, `firedEdges`) | — | — | — | — | — | single-cell v1: one memo, one trace; the recomputation seam is a caller-supplied patch-to-term function (v1 default `recomputePatch`); invalidation is positional over the claimed-vs-read sets; no complexity claims (costs would bind to a persistent-tree representation, out of v1 scope); input discipline: the focus operation is `incrementalPlug` — it depends on the memo, the patch, and the caller-supplied seam, and on nothing else | `prop_inc_clean_ignores_seam` (a clean patch reads through without consulting the seam), `prop_inc_recomputed_uses_seam` (the recomputed output is the seam's term), `prop_inc_memo_update` (re-keying), `prop_inc_fired` (fired edges track the reads) | incremental layer over the patch layer; suite lives in the `focal-incremental` package |
| `Focal.Form` (`WidgetPath`, `FormError`, `Field`, `validateField`, `ModelSnapshot`, `fieldKey`, `validateForm`, `FieldResidual`, `revalidate`, `residuals`, `putback`/`PutbackResult`/`applyOne`) | — | — | — | — | — | validate-then-apply (C7 route): all-or-nothing form validation reports every failure and leaves the snapshot untouched — the per-field validation failures first, then the duplicate model-key collisions (one per colliding later field, in field order) — and every failure's residual preserves the raw input, the collisions included; a validated field overwrites its model key, untouched keys persist; error provenance is the widget path, carried by the field residual (re-validation on transport keeps the original path); unknown field kinds fail at the boundary; the validator's adopted value (its `Right` result) is stored under the field key, while the residual keeps the raw input; input discipline: the focus operation is `putback` — it depends on the validator registry, the snapshot, and the field, and on nothing else | `prop_fm_putback_ok` (valid edit applies by key), `prop_fm_putback_error` (error with residual), `prop_fm_putback_overwrites`, `prop_fm_revalidate_provenance`, `prop_fm_validate_form_allornothing`, `prop_fm_adopts_value` (the adopted value is stored), `prop_fm_duplicate_key` (a colliding model key is a failure of the later field), `prop_fm_validate_form_every_failure` (every failure is reported, the validation failures first), `prop_fm_residuals_duplicate` (the collision's residual is preserved) | form layer over the patch layer (v1: string-keyed model); suite lives in the `focal-form` package |
| `Focal.Parser` (`Grammar`, `parse`/`parseOne`, `parseAll` (pruned enumeration), `ambiguities`, `Selection`/`select`, `Forest` provenance, `focusForest`/`plugForest`, `Residual` (frame list + selection), `admits`, `reparseReport`) | ✓ | ✓ | ✓ | — | — | v1 domain is ambiguity-free; the selection coordinate is reported as absent when out of range (never clamped); the residual is a frame list (not a tree) carrying every ancestor's provenance, and it is sealed — `Residual`'s constructor is not exported, so a residual can only come from `focusForest` and its frames agree with its coordinate by construction, so the replacement laws (including the re-hit clause) hold over the whole plug domain; the derivation carries the expansion path: re-entering a kind at the same input position fails (no progress is possible), while a re-entry at a later position stays legal — so a cyclic grammar reports no parse instead of diverging, and a productive right-recursive grammar still parses; ambiguity (multi-alternative kinds) is detected and reported, never resolved; replacement-induced parse-set changes are computed by the local admission (`admits`, children only — the residual position is not re-derived) and reported with the remaining alternatives; `parseAll`'s enumeration is exact for non-nullable nonterminals (a nullable derivation is dropped, not looped); input discipline: the focus operation is `focusForest` — it depends on the selection coordinate and the forest, and on nothing else | `prop_ps_focus_roundtrip` (plug-after-focus rebuilds), `prop_ps_selection_preserved` (the residual's coordinate re-selects the replacement), `prop_ps_provenance_preserved` (ancestors survive; the new node's provenance is its own), `prop_ps_reparse_report` (the local admission plus the alternatives minus the claimed one), `prop_ps_ambiguity_multi` (both derivations of an ambiguous kind enumerated; the first alternative is the deterministic default), `prop_ps_nullable_divergence` (the documented nullable precondition, pinned), `prop_ps_rehit` (the re-hit clause over the whole plug domain), `prop_ps_cycle_terminates` (a cyclic grammar terminates with no parse), `prop_ps_recursive_grammar` (a productive right-recursive grammar parses) | parser layer over the sort-indexed language; the sealed residual makes the forest focus a lawful optional-rung instance (L-GP/L-PG/L-PP hold over the whole plug domain); laws are stated relative to the selection (C3); the provenance chain runs root-first, selected last; suite lives in the `focal-parser` package |
| `Focal.Query` (`Table`, `Projection`/`project`, `ViewRow` provenance, `JoinWitness`, `joinView`, `Candidate`, `Policy`, `Putback`, `putbackRow`, `RelDelta`, `relPutback`) | — | — | — | — | — | projection provenance is the source row index (a v1 identity — base-table reordering or deletion moves it); the join witness carries a `Maybe` lookup row (no sentinels; unmatched rows pass through); the view-update policy is an ordered candidate list — zero candidates report the empty ambiguity, several report the ordered list, never a silent choice (C4 route); input discipline: the focus operation is `relPutback` — it depends on the write-back policy, the table, the view row, and the edited column and value, and on nothing else | `prop_rq_ok` (one candidate: the delta carries the row's provenance and the candidate's column/value), `prop_rq_ambiguous` (ordered ambiguity), `prop_rq_none` (empty ambiguity), `prop_rq_provenance` (the second view row targets its own source row) | relational layer over the sort-indexed language; suite lives in the `focal-query` package |
| `Focal.Workflow` (`Workflow`, `Run`, `TransitionContext`, `splitRun`/`plugRun`, `Compensation`, `RollbackPlan`/`rollbackPlan`, `GateVerdict`/`validateGate`, `InvalidTransition`, `workflowPlug`) | — | — | — | — | — | a labelled transition system (static structure only, no liveness claims); the rollback plan composes declared compensators in reverse run order — a preorder span, not an inverse; uncompensated transitions are reported by name; the gate accepts exactly when every step is declared AND consecutive steps chain (each step's source is the previous step's target; a run may begin in any state — no initial state in v1), and reports the FIRST offending step with its index, never silently dropping it (validate-then-apply); the validated plug additionally requires the replacement to carry the focused transition's name (the re-hit premise) and then runs the gate — a name-changing replacement is rejected with the focus's index and the offered transition; input discipline: the focus operation is `workflowPlug` — it depends on the workflow, the transition context, and the replacement transition, and on nothing else | `prop_wf_accept` (a declared replacement is accepted with the plugged run), `prop_wf_reject` (an undeclared replacement reports its step and transition), `prop_wf_first_bad` (the gate reports the first offending step), `prop_wf_continuity` (consecutive steps must chain), `prop_wf_untouched` (a rejected replacement leaves the context validating), `prop_wf_plug_name_premise` (a name-changing replacement is rejected), `prop_wf_pg_name` (a name-preserving plug re-splits to the replacement) | workflow layer over the patch layer (C5 route); suite lives in the `focal-workflow` package |

Verdict footnotes:

- **Released surface** — `focal-core-0.2.0.0` (2026-10-20); the rows below are the
  verdicts for that release. Each package's suite is the witness set named in
  its row.

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

Reviewed property-by-property against the working tree (**140 properties**,
plus the doctest suite):

- **L-GP: 15 of 140** (`prop_lgp_*` 8, partial `prop_lgpE_*` 3, effectful `prop_lgpM_*` 4).
- **L-PG: 13 of 140** (`prop_lpg_*` 7, partial `prop_lpgE_*` 2, effectful `prop_lpgM_*` 4).
- **L-PP: 9 of 140** (`prop_lpp_*` 5, partial `prop_lppE_*` 2, effectful `prop_lppM_*` 2;
  one trivially-satisfied snapshot case, `prop_lpp_fromZip`).
- **L-OVF: 6 of 140** (`prop_lovf_*` — five instances, including the embedded
  lens pair, plus the partial success-prefix case).
- **L-ASSOC: 3 of 140** (`prop_lassoc_*`); **L-UNIT: 6 of 140** (`prop_lunit_*`).
- **L-NORM: 2 of 140** (`prop_lnorm_*`); **L-TVL: 2 of 140** (`prop_ltvl_*`).
- **Partial channel: 7 of 140** (`prop_scE_*`, `prop_embE_compose`,
  `prop_storeE_roundtrip`, `prop_discE_*` — three discriminators).
- **`elementE` contract: 7 of 140** (`prop_elementE_*`).
- **Effectful rung (non-law): 13 of 140** (`prop_compM_*`, `prop_lunitM_*`,
  `prop_lassocM_*`, `prop_storeM_*`, `prop_embM*`, `prop_discM_*`).
- **Residual shape: 2 of 140** (`prop_flatten_inverse`, `prop_unflatten_inverse`).
- **Type-changing fragment: 5 of 140** (`prop_tc_*`).
- **`focusAtE` contract: 5 of 140** (`prop_focusatE_*`).
- **Navigation algebra: 7 of 140** (`prop_nav_*`).
- **Generic derivation: 4 of 140** (`prop_gen_*`).
- **Optional focus: 7 of 140** (six `prop_opt_*` plus `prop_discO_offImage`).
- **Typed syntax (focal-syntax suite): 8 properties** — three concrete plug
  regressions (`prop_stack_*`), the well-sorted round trip and the path and
  overwrite laws on the residual image (`prop_tm_gp`, `prop_tm_path`,
  `prop_tm_pp`), the off-image discriminator `prop_tm_offImage`, and the
  in-suite ill-sorted witness `prop_neg_sortMismatch` (module
  `focal-syntax/test/Negative.hs`, compiled with `-fdefer-type-errors`);
  registered per package; the root total stays 140; the frozen vocabulary is
  exercised cross-package by the consistency suite below.
- **Cross-package consistency (focal-consistency suite): 23 properties** — one
  group per frozen §3 law-id (`L-GP`, `L-PG`, `L-PP`, `L-OVF`, `L-ASSOC`,
  `L-UNIT`, `L-NORM`, `L-TVL`) plus the registered channel families and domain
  round trips, each witness running through a package's public surface (all
  ten packages covered); registered as its own package; the root total stays
  140.
- **Redex loop (focal-redex suite): 20 properties** (`prop_rd_*`) — the
  decompose/plug/step trio on three term shapes, the `redexF` split and miss,
  and 7 laws (plug-after-decompose, progress, normalization, head step = beta,
  the redexF rebuild, the redexF re-hit and the redexF put-put equation — the
  last three over both focus sorts); registered per package; the root total
  stays 140.
- **Refactoring layer (focal-refactor suite): 11 properties** (`prop_rf_*`) —
  substitution identity, hit/non-hit equations, no-capture under a fresh
  binder, substitution-commutes-with-path (with `prop_rf_commute_needsPremise`
  pinning the frame-occurrence premise), the rename involution, the
  abstract-then-apply round trips, the operation round trips (eta-expansion,
  inline), and the global text offsets of the renderer; registered per
  package; the root total stays 140.
- **Patch layer (focal-delta suite): 9 properties** (`prop_dl_*`) — patch-focus
  hits with evidence preservation, the zero-candidate equation,
  substitution-commutes-with-weakening, evidence travel, the edit-transport
  divergence boundary, the refusal of an edit at an already-claimed variable,
  and the refactoring-bridge round trips; registered per package; the root
  total stays 140.
- **Incremental layer (focal-incremental suite): 4 properties** (`prop_inc_*`)
  — the clean branch reading through without consulting the seam, the
  recomputed branch using the caller-supplied seam, memo re-keying, and
  fired-edge tracking; registered per package; the root total stays 140.
- **Form layer (focal-form suite): 9 properties** (`prop_fm_*`) — the
  validate-then-apply pipeline: valid edits apply by key, failures report
  the error with the residual, key overwrite, provenance-preserving
  re-validation, all-or-nothing form validation, the adopted value being
  stored, the duplicate model-key collision, the every-failure report (the
  validation failures first, then the collisions), and the collision's
  residual; registered per package; the root total stays 140.
- **Parser layer (focal-parser suite): 9 properties** (`prop_ps_*`) — the
  forest focus: plug-after-focus rebuilds, the residual's coordinate
  re-selects the replacement, ancestor provenance survives, the reparse
  report (local admission plus the remaining alternatives), both
  derivations of an ambiguous kind enumerated with the first alternative
  as the deterministic default, the documented nullable precondition
  pinned, the re-hit clause over the whole plug domain, a cyclic grammar
  terminating with no parse, and a productive right-recursive grammar
  parsing; registered per package; the root total stays 140.
- **Query layer (focal-query suite): 4 properties** (`prop_rq_*`) — the
  policy-ordered relational putback: one candidate applies with the row's
  provenance, several report the ordered ambiguity, zero reports the
  empty ambiguity, and provenance drives the delta's row; registered per
  package; the root total stays 140.
- **Workflow layer (focal-workflow suite): 7 properties** (`prop_wf_*`) —
  the transition-validation plug: acceptance of declared replacements,
  rejection with the offending step, first-offending-step reporting, the
  chain-continuity check, the untouched-context guarantee, the name premise
  on the plug, and the name-carrying re-split; registered per package; the
  root total stays 140.
- The remaining 27 properties: 3 occurrence≠value positional-encoding checks, 5 zipper
  law/navigation tests, 2 snapshot contracts (`prop_contract_zip_*`),
  2 law discriminators (`prop_disc_*`), 8 `focusAt` tests, 3 `elementAt` tests,
  2 concrete regressions, 1 `elementF` contract test, 1 edit-independence
  observation.
