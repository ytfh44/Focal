# Focal Roadmap

Law and contract vocabulary: [`docs/foundation.md`](docs/foundation.md)
(axiom A-LENS, L0–L6 hierarchy, law-ids). Per-instance verdicts:
[`docs/conformance.md`](docs/conformance.md).

## 0. Engineering constraints

Standing constraints — checked at every review; they have no completion state.

0.1. Preserve the core shape: `Focusing c s t a b = splitF :: s -> (a,c)` + `plugF :: c -> b -> t`; `c` must remain a first-class residual.

0.2. `focal-core` does pure structural decomposition, fixed-root reconstruction, and mechanical composition only. IO, databases, validation, conflict merging, dependency graphs, and semantic bindings all go into extension packages.

0.3. The current default is single-focus; multi-focus work must first define residual merge semantics (research item M-1) and must not be stuffed directly into core.

0.4. Strong specializations come before weak ones: Lens-like, List, Zipper, Typed Syntax, Redex first; Query, Workflow last.

0.5. Claim discipline: every law or contract claim must cite a law-id (`docs/foundation.md` §3) plus well-formedness conditions, domain of validity, and a witness (a test or an explicit gap). Unenforced claims must be marked as such.

0.6. The partiality policy and input invariance are instance-admission conditions (`docs/foundation.md` §4); any exemption must be registered in `docs/conformance.md`.

0.7. Axiom / definitional identity / corollary / theorem classification is authoritative only in `docs/foundation.md`; this file carries engineering constraints and scheduling.

---

## P0 — Foundations

0a. Land the foundation documentation: `docs/foundation.md` (A-LENS, L0–L6, law vocabulary, contracts, representation ladder, defect log), `docs/conformance.md` (instance × law matrix), README "Law status", and this roadmap.
Depends on: —. Done = ① documents merged ② build and tests green ③ the retired-phrase audit described in `docs/foundation.md` §6 stays clean. [x]

0b. Rewrite tests by law-id: drop duplicates and definitional entries; add witnesses for L-PG and L-PP; broaden L-OVF coverage; add snapshot-contract tests for `fromZip`; annotate every property with its law-id.
Depends on: 0a. Done = ① every conformance row claiming L-PG/L-PP has a green witness ② conformance matrix updated ③ no property name overstates what it checks. [x]

0c. List contract fixes: add `elementAt` (construction-time bounds check; total for `0 <= n < length` via `Maybe`/`Either`); turn the `Focal.List` haddock examples into genuinely runnable doctests; keep the deferred-error behavior of `elementF`/`unsafeElementF` documented.
Depends on: 0a. Done = ① `elementAt` implemented with tests ② doctests runnable ③ haddock matches behavior. [x]

0d. Zipper semantics split: keep `fromZip` as snapshot semantics (documented); add a dynamic `focusAt :: [Child t] -> t -> Maybe (Focusing ...)` that is input-invariant on its valid domain and reports invalid paths through the return channel; decide retire-vs-rename for `safeFocusAt`/`unsafeFocusAt` in this item.
Depends on: 0a. Done = ① decision recorded ② dynamic `focusAt` implemented with tests ③ conformance rows updated. [x]
Decision recorded 2026-10-15: `safeFocusAt` / `unsafeFocusAt` were retired in favor of `fromZip` (snapshot) + `focusAt` (dynamic); `focusAt` validates the path against the construction tree and re-navigates per input.

0e. Land the representation ladder: `Focal` encapsulation decision + `mkFocal`/`withFocal`; `normalize`; `Focal.Interop` (`PStore`/`reifyVL`/`toVL`/`fromVL`); L-NORM / L-TVL tests.
Depends on: 0a. Done = ① conversions implemented and tested extensionally ② L-NORM/L-TVL rows green. [x]

0f. Promote `Focal.Laws`: extract the shared law combinators once a second in-repo consumer exists.
Depends on: 0b, 0e. Done = ① ≥ 2 in-repo consumers of the shared combinators.
Status: held — trigger not met; one in-repo consumer (`test/Spec.hs`).

0g. Enforcement: doctest gate in CI; law-id-tagged property output.
Depends on: 0b, 0c. Done = ① CI fails on failing doctests ② test output prints law-id labels. [x]

---

## P1 — Core package and hardening (items 1–8)

1. Establish the `focal-core` package boundary. Exports follow the current modules (`src/Focal/Core.hs` et al.); the encapsulation decision for `Focal` is tracked in 0e.
Depends on: 0a. Done = ① export list documented ② no module exports undocumented internals ③ 0e decision recorded. [x]

2. Establish the law-testing framework. Subsumed by 0b (tests rewritten by law-id).
Depends on: 0b. Done = ① 0b complete ② framework covers every law-id in `docs/foundation.md` §3. [x]

3. Backfill law tests for existing implementations (`pureF`, `fstF`, `sndF`, `idF`, `elementF`, `fromZip`). Subsumed by 0b.
Depends on: 0b. Done = ① every shipped instance appears in the conformance matrix with witnesses or a registered gap. [x]

4. Split out `Focal.Partial`: define `FocusingE e c s t a b`; move failures into `split`/`plug` return values.
Depends on: 0a. Done = ① module exported ② rung registered in `docs/foundation.md` §1 ③ every throw site re-checked against §4.1 ④ Store/coend reading re-derived for the `Either e` codomain; rank re-checked (foundation §5). [x]

5. Rewrite the list focus: migrate `elementF` negative-index / out-of-bounds / empty-list cases into `FocusingE` (item 4); retain the total-safe API; add `elementAt` (0c).
Depends on: 4, 0c. Done = ① `FocusingE`-based list focus ② `elementAt` landed ③ L-GP/L-PG/L-PP rows green for both list focuses (`elementF` and the `FocusingE` variant).

6. Split out `Focal.Effectful`: define `FocusingM m c s t a b`; unify failure, validation, logging, and stateful reconstruction.
Depends on: 4. Done = ① module exported ② rung registered ③ witness tests for its laws ④ Store/coend reading re-derived for the `m` codomain; rank re-checked (foundation §5).

7a. Normalize residual composition (syntax): `Residual2`, `Residual3`, flatten/unflatten, pretty/debug helpers to avoid long-term exposure of deeply nested pairs.
Depends on: 1, 4. Done = ① helpers exported ② flatten/unflatten round-trip tests.

7b. `normalize` (extensional normal form for `Focal`). Tracked in 0e.
Depends on: 0e. Done = ① implemented with L-NORM tests ② conformance row green. [x]

8. Publish `focal-core-0.1`: freeze the core API, laws, partial/effectful extension points, and existing strong specializations.
Depends on: 0a–0e, 0g, 1–7b (0f is trigger-based — it does not gate the release). Done = ① foundation compliance: every claim in README/haddock maps to L0–L6 with a witness or a registered gap ② conformance matrix fully green or registering explicit exemptions ③ doctest gate active (0g) ④ multi-package mechanism decided (M-4).

---

## P2 — Typed syntax, redex, refactoring (items 9–17)

9. Establish `focal-syntax`: typed AST examples, sort kinds, GADT nodes, typed paths.
Depends on: 8. Done = ① modules + example AST ② rung registered in `docs/foundation.md` §1.

10. Implement Typed Syntax Focal: `Stack i j`, sort-checked `split`, sort-checked `plug`; a wrong-sort replacement must not type-check.
Depends on: 9. Done = ① implementation ② negative type-error witness ③ rung registered.

11. Add laws for Typed Syntax Focal: well-sorted round-trip, path preservation, ill-sorted replacement rejection.
Depends on: 10. Done = ① law-ids registered in `docs/foundation.md` §3 ② witnesses green.

12. Establish `focal-redex`: term, value, redex, evaluation context, contract.
Depends on: 10. Done = ① modules + docs ② rung registered.

13. Implement Redex Focal: `decompose :: Term -> Either Value (Redex, EvalCtx)`, `plug`/`contract`/`step`, forming a decompose-contract-plug loop. Note: `plug` here is not structural rebuild — it must register through an extended rung (`FocusingE`/`FocusingM` or a new one) before any law claim.
Depends on: 12, 0e. Done = ① loop implemented ② rung registered ③ plug-after-decompose witness.

14. Add laws for Redex Focal: plug-after-decompose, deterministic strategy, step preserves well-typedness.
Depends on: 13. Done = ① law-ids registered ② witnesses green.

15. Establish `focal-refactor`: syntax stack, span, layout, scope snapshot, type facts.
Depends on: 10, 13. Done = ① modules + docs.

16. Implement binder-aware replacement: alpha-renaming, capture avoidance, scope-preserving `plug`.
Depends on: 15. Done = ① implementation ② capture-avoidance tests.

17. Implement basic refactoring operations: rename, extract local, inline, case split.
Depends on: 16. Done = ① operations implemented ② round-trip tests per operation.

---

## P3 — Delta and incrementality (items 18–22)

18. Establish `focal-delta`: `Delta`, survival witness, reindexing witness, conflict type.
Depends on: 8. Done = ① modules + docs ② law-ids registered if claimed.

19. Implement structural patch focus: local replacement produces a global delta; conflicts return `Either Conflict Delta`.
Depends on: 18. Done = ① implementation ② conflict tests.

20. Connect refactoring to delta: refactoring operations output patches, not just new ASTs.
Depends on: 17, 19. Done = ① integration ② patch round-trip tests.

21. Establish `focal-incremental`: dependency trace, memo cell, invalidation graph.
Depends on: 19. Done = ① modules + docs.

22. Implement incremental plug: local delta drives invalidation; outputs `OutputDelta`.
Depends on: 21. Done = ① implementation ② invalidation tests.

---

## P4 — Domain specializations (items 23–30)

23. Establish `focal-form`: widget path, model snapshot, validation context, field residual.
Depends on: 6, 19. Done = ① modules + docs.

24. Implement form putback: field edit -> validation -> `Either Error ModelDelta`.
Depends on: 23. Done = ① implementation ② validation tests.

25. Establish `focal-parser`: parser state, grammar choice provenance, parse forest node focus.
Depends on: 6, 10, 19. Done = ① modules + docs.

26. Implement grammar focus: parse forest local replacement, ambiguity preservation, non-tree residual.
Depends on: 25. Done = ① implementation ② ambiguity tests.

27. Establish `focal-query`: projection provenance, join witness, view-update policy.
Depends on: 19, 26. Done = ① modules + docs.

28. Implement relational putback: view edit -> `Either AmbiguousPutback RelDelta`.
Depends on: 27. Done = ① implementation ② policy tests.

29. Establish `focal-workflow`: transition context, rollback plan, validation gate.
Depends on: 6, 19, 24. Done = ① modules + docs.

30. Implement workflow plug: current task replacement -> transition validation -> `Either InvalidTransition Workflow`.
Depends on: 29. Done = ① implementation ② transition tests.

---

## P5 — Cross-package consistency and release (items 31–32)

31. Cross-package consistency tests: core, syntax, redex, refactor, delta, incremental, form, parser, query, and workflow share the frozen law-id vocabulary; each package's conformance suite cites `docs/foundation.md` §3 law-ids.
Depends on: 8–30. Done = ① suite runs against frozen law-ids ② every package registers its verdicts.

32. Publish `focal-0.2` integration release: core stable; strong specializations available; mid-strength specializations have minimal implementations; weak specializations annotated as domain frameworks.
Depends on: 31. Done = ① release published ② README/conformance reflect the released surface ③ no claim without a witness or a registered gap.

---

## Research items (unscheduled)

M-1. Multi-focus residual merge semantics.
Depends on: —. Trigger: multi-focus work is scheduled (§0.3). Done = ① design note with invariants ② law-ids registered in `docs/foundation.md` §3 ③ rank/coend re-derivation (merge is not a product — the shipped composition argument does not transfer).

M-2. DAG occurrence → vertex quotient (the `XE` boundary).
Depends on: —. Trigger: the `XE` boundary becomes load-bearing (a shared-subterm traversal is scheduled). Done = ① quotient construction, or a documented impossibility ② conformance exemption updated.

M-3. Dissection left/right heterogeneous upgrade (type-changing residuals for `ListCtx`).
Depends on: —. Trigger: a type-changing (heterogeneous) residual use case appears. Done = ① formulation + worked example ② law statement for the asymmetric case.

M-4. `Focal` → `focal-core` multi-package mechanism.
Depends on: —. Trigger: the item-8 release line (the mechanism is needed before publishing). Done = ① mechanism decided (packages, versioning) ② items 1 and 0e updated accordingly.
