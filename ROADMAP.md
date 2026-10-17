# Focal Roadmap

Law and contract vocabulary: [`docs/foundation.md`](docs/foundation.md)
(axiom A-LENS, L0–L6 hierarchy, law-ids). Per-instance verdicts:
[`docs/conformance.md`](docs/conformance.md).

Work is layered by the semantics it adds. The **closure layers** — legitimacy
(laws, type-change, partiality, effects, representation) and the structure
algebra (derivatives, dissection, indexed syntax, focus cardinality, sharing) —
carry the core's own mathematics and take priority (§0.9): new items `33`–`38`
(P2), plus closure work already homed elsewhere (`7a`, `0f`, `9`–`11`,
`18`–`20`, `M-1`–`M-3`). The **interpreter layers** — redex, refactoring,
incremental computation, parser, query, workflow (P3 `12`–`17`, P4 `21`–`22`,
P5) — consume the core as a structural interface; their domain rules are not
derivable from `split`/`plug` (§0.8). Item ids are append-only and need not
follow section order (§0.10).

## 0. Engineering constraints

Standing constraints — checked at every review; they have no completion state.

0.1. Preserve the core shape: `Focusing c s t a b = splitF :: s -> (a,c)` + `plugF :: c -> b -> t`; `c` must remain a first-class residual.

0.2. `focal-core` does pure structural decomposition, fixed-root reconstruction, and mechanical composition only. IO, databases, validation, conflict merging, dependency graphs, and semantic bindings all go into extension packages.

0.3. The current default is single-focus; multi-focus work must first define residual merge semantics (research item M-1) and must not be stuffed directly into core.

0.4. Strong specializations come before weak ones: Lens-like, List, Zipper, Typed Syntax, Redex first; Query, Workflow last.

0.5. Claim discipline: every law or contract claim must cite a law-id (`docs/foundation.md` §3) plus well-formedness conditions, domain of validity, and a witness (a test or an explicit gap). Unenforced claims must be marked as such.

0.6. The partiality policy and input invariance are instance-admission conditions (`docs/foundation.md` §4); any exemption must be registered in `docs/conformance.md`.

0.7. Axiom / definitional identity / corollary / theorem classification is authoritative only in `docs/foundation.md`; this file carries engineering constraints and scheduling.

0.8. **Core-entry discipline.** A capability enters the core iff its semantics is primarily determined by explicit residuals and the focus laws; domain rules — evaluation strategies, validation policies, transaction/rollback semantics, parse/query resolution, workflow transitions — live in extension packages that use the core as a structural interface. New optics abstractions enter the core only when explicit residuals must be preserved or manipulated.

0.9. **Closure-first priority.** Closure work (P2 and the closure items homed elsewhere) takes precedence over the interpreter items (P3 `12`–`17`, P4 `21`–`22`, P5); an interpreter item goes ahead of an unblocked closure item only when a concrete use case requires it.

0.10. **Append-only ids.** Item ids are never renumbered — they are cited from `docs/foundation.md`, `test/Spec.hs`, and CHANGELOG entries, and `§0` is cited from README and foundation. New items continue the sequence regardless of the section they belong to, and splits use letter suffixes (`7a`, `7b`).

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

1. Establish the `focal-core` package boundary. Exports follow the current modules (`src/Focal/Core.hs` et al.); the package is named `focal-core` while modules keep the `Focal.*` namespace; the encapsulation decision for `Focal` is tracked in 0e.
Depends on: 0a. Done = ① export list documented ② no module exports undocumented internals ③ 0e decision recorded. [x]

2. Establish the law-testing framework. Subsumed by 0b (tests rewritten by law-id).
Depends on: 0b. Done = ① 0b complete ② framework covers every law-id in `docs/foundation.md` §3. [x]

3. Backfill law tests for existing implementations (`pureF`, `fstF`, `sndF`, `idF`, `elementF`, `fromZip`). Subsumed by 0b.
Depends on: 0b. Done = ① every shipped instance appears in the conformance matrix with witnesses or a registered gap. [x]

4. Split out `Focal.Partial`: define `FocusingE e c s t a b`; move failures into `split`/`plug` return values.
Depends on: 0a. Done = ① module exported ② rung registered in `docs/foundation.md` §1 ③ every throw site re-checked against §4.1 ④ Store/coend reading re-derived for the `Either e` codomain; rank re-checked (foundation §5). [x]

5. Rewrite the list focus: migrate `elementF` negative-index / out-of-bounds / empty-list cases into `FocusingE` (item 4); retain the total-safe API; add `elementAt` (0c).
Depends on: 4, 0c. Done = ① `FocusingE`-based list focus ② `elementAt` landed ③ L-GP/L-PG/L-PP rows green for both list focuses (`elementF` and the `FocusingE` variant). [x]

6. Split out `Focal.Effectful`: define `FocusingM m c s t a b`; unify failure, validation, logging, and stateful reconstruction.
Depends on: 4. Done = ① `Focal.Effectful` exported: `FocusingM(..)`, `idM`, `composeM`, `overM`, `toEffectful`, `toEffectfulE`, `storeM`, `fromStoreM` (all rank ≤ 1) ② rung registered in `docs/foundation.md` §1 ③ law witnesses: the L-GP/L-PG monadic forms green for ≥ 3 instances across distinct monads (logging, partial, state) + composition closure (GP/PG preserved under `composeM`; algebraic proof + probe/exhaustive-sweep evidence) + `prop_discM_*` pins: bare PG fails with effects; the replay-prefix PP fails for logging and sign-flipping residuals, and the prefix-less strengthening is false ④ Store/coend reading: unconditional collapse `∫^C Hom(S, m(A×C)) × Hom(C, B→mT) ≅ Hom(S, m(A×(B→mT)))` documented in §5; rank re-checked. [x]

7a. Normalize residual composition (syntax): `Residual2`, `Residual3`, flatten/unflatten, pretty/debug helpers to avoid long-term exposure of deeply nested pairs.
Depends on: 1, 4. Done = ① helpers exported ② flatten/unflatten round-trip tests. [x]

7b. `normalize` (extensional normal form for `Focal`). Tracked in 0e.
Depends on: 0e. Done = ① implemented with L-NORM tests ② conformance row green. [x]

8. Publish `focal-core-0.1`: freeze the core API, laws, partial/effectful extension points, and existing strong specializations.
Depends on: 0a–0e, 0g, 1–7b (0f is trigger-based — it does not gate the release). Done = ① foundation compliance: every claim in README/haddock maps to L0–L6 with a witness or a registered gap ② conformance matrix fully green or registering explicit exemptions ③ doctest gate active (0g) ④ multi-package mechanism decided (M-4). [x]

---

## P2 — Semantic closure (items 33–38)

The core's own mathematics: the laws and interfaces the shipped rungs leave open, plus the structure algebra. These items extend the core beyond the 0.1 freeze — they do not gate item 8. Closure work already homed elsewhere is cross-referenced at the end of this section.

33. Type-changing law suite: state the A-LENS clause forms for `s ≠ t` / `a ≠ b` with their side conditions, closing the gap between the five-parameter interface and the mono §3 statements.
Depends on: 0a, 0b. Done = ① clause forms written in `docs/foundation.md` §3 with side conditions ② ≥ 2 type-changing instances with witnesses (product components; a composed chain) ③ conformance rows updated. [x]

34. Dynamic failure channel — `focusAtE`: path focus whose invalidity at split time travels in the return channel (no deferred `error` for the caller).
Depends on: 0d, 4. Done = ① `focusAtE` exported (rank ≤ 1), per-call path validation ② tests: valid domain, off-tree path, path absent in a later tree ③ conformance row + §4.1 exemption narrowed. [x]

35. Residual representation-equivalence rules: formalize when two residuals are interchangeable — putback-equivalence (`∀b. plugF f c1 b = plugF f c2 b`) versus geometry retention — and what re-representation may discard.
Depends on: 0e, 7b. Done = ① boundary stated in §5 (function equality is not decidable; no total residual minimization) ② admissible-discard rules for `normalize`/re-representation ③ checkable rules get witnesses; the rest registered as gaps. [x]

36. Generic one-hole contexts: derive residuals/frames for algebraic datatypes instead of hand-writing one family at a time (generics or codegen — decide and record).
Depends on: 1. Done = ① mechanism decision recorded ② derivation implemented ③ ≥ 1 existing family migrated with GP/PG/PP witnesses green ④ rung/registration in `docs/foundation.md`. [x]

37. Navigation algebra: path↔frame-stack conversion, path composition, lowest common ancestor, invalid-path semantics — formalizes the `XC` boundary (README note) where child selection must be decidable.
Depends on: 0d. Done = ① operations exported on `Focal.Zipper` ② round-trip, composition, and LCA laws with witnesses ③ conformance rows; `XC` narrowed or discharged. [x]

38. Zero-or-one focus (optional cardinality): an interface whose split may find no focus, with miss pass-through semantics (update on a miss is identity) — distinct from the failure channel; state its laws.
Depends on: 0a, 4. Done = ① interface + laws in §3 ② witnesses ③ rank and boundary registered (Prism/Affine reading). [x]

Tracked elsewhere (closure layer): canonical residual products (`7a`); law-reuse infrastructure (`0f`); typed/indexed syntax (`9`–`11`); heterogeneous dissection (`M-3`); multi-focus merge including multi-edit commutation/conflict (`M-1`); DAG occurrence→vertex quotient (`M-2`); residual survival and reindexing (`18`–`20`); nominal `FocalE`/`FocalM` seals stay trigger-based (no consumers; §5 note); effect-law verdicts and GP/PG composition closure ship with item 6.

---

## P3 — Typed syntax, redex, refactoring (items 9–17)

9. Establish `focal-syntax`: typed AST examples, sort kinds, GADT nodes, typed paths.
Depends on: 8. Done = ① modules + example AST ② rung registered in `docs/foundation.md` §1. [x]

10. Implement Typed Syntax Focal: `Stack i j`, sort-checked `split`, sort-checked `plug`; a wrong-sort replacement must not type-check.
Depends on: 9. Done = ① implementation ② negative type-error witness ③ rung registered. [x]

11. Add laws for Typed Syntax Focal: well-sorted round-trip, path preservation, ill-sorted replacement rejection.
Depends on: 10. Done = ① law-ids registered in `docs/foundation.md` §3 ② witnesses green. [x]

12. Establish `focal-redex`: term, value, redex, evaluation context, contract.
Depends on: 10. Done = ① modules + docs ② rung registered. [x]

13. Implement Redex Focal: `decompose :: Term -> Either Value (Redex, EvalCtx)`, `plug`/`contract`/`step`, forming a decompose-contract-plug loop where `step = plug (E, contract r)`. The law-bearing direction is the context fill `plug (E, r) = t`; `contract` and the strategy stay in the evaluation layer — a `plug` that contracts breaks GP. `plug` registers through an extended rung (`FocusingE`/`FocusingM` or a new one) before any law claim.
Depends on: 12, 0e. Done = ① loop implemented ② rung registered ③ plug-after-decompose witness. [x]

14. Add laws for Redex Focal: plug-after-decompose, deterministic strategy, step preserves well-typedness.
Depends on: 13. Done = ① law-ids registered ② witnesses green. [x]

15. Establish `focal-refactor`: syntax stack, span, layout, scope snapshot, type facts.
Depends on: 10, 13. Done = ① modules + docs. [x]

16. Implement binder-aware replacement: alpha-renaming, capture avoidance, scope-preserving `plug`.
Depends on: 15. Done = ① implementation ② capture-avoidance tests. [x]

17. Implement basic refactoring operations: rename, extract local, inline, case split.
Depends on: 16. Done = ① operations implemented ② round-trip tests per operation. [x]

---

## P4 — Delta and incrementality (items 18–22)

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

## P5 — Domain specializations (items 23–30)

These frameworks interpret the core. Their domain rules — validation policies, transaction semantics, ambiguity and query resolution, workflow transitions — are not derivable from `split`/`plug` and stay outside it (§0.8); they follow the closure layer in priority (§0.9).

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

## P6 — Cross-package consistency and release (items 31–32)

31. Cross-package consistency tests: core, syntax, redex, refactor, delta, incremental, form, parser, query, and workflow share the frozen law-id vocabulary; each package's conformance suite cites `docs/foundation.md` §3 law-ids.
Depends on: 8–30. Done = ① suite runs against frozen law-ids ② every package registers its verdicts.

32. Publish `focal-0.2` integration release: core stable; strong specializations available; mid-strength specializations have minimal implementations; weak specializations annotated as domain frameworks.
Depends on: 31. Done = ① release published ② README/conformance reflect the released surface ③ no claim without a witness or a registered gap.

---

## Research items (unscheduled)

The open mathematical questions: legitimacy and type-change (items 33, 35); residual generalization (item 36, M-3); focus cardinality and merge (item 38, M-1); identity survival under structural change (items 18–20, M-2). Taken up when their trigger fires.

M-1. Multi-focus residual merge semantics.
Depends on: —. Trigger: multi-focus work is scheduled (§0.3). Done = ① design note with invariants (including commutation for independent edits and conflict semantics for overlapping ones) ② law-ids registered in `docs/foundation.md` §3 ③ rank/coend re-derivation (merge is not a product — the shipped composition argument does not transfer).

M-2. DAG occurrence → vertex quotient (the `XE` boundary).
Depends on: —. Trigger: the `XE` boundary becomes load-bearing (a shared-subterm traversal is scheduled). Done = ① quotient construction, or a documented impossibility ② conformance exemption updated.

M-3. Dissection left/right heterogeneous upgrade (type-changing residuals for `ListCtx`).
Depends on: —. Trigger: a type-changing (heterogeneous) residual use case appears. Done = ① formulation + worked example ② law statement for the asymmetric case.

M-4. `Focal` → `focal-core` multi-package mechanism.
Depends on: —. Trigger: the item-8 release line (the mechanism is needed before publishing). Done = ① mechanism decided (packages, versioning) ② items 1 and 0e updated accordingly. [x]
Decision recorded 2026-10-16: single package `focal-core` (modules stay `Focal.*`, repository remains `Focal`); versioning: minor bump per release in the 0.x series; per-package split (`focal-syntax` et al.) only when a second package is scheduled (P3). The Hackage upload is a manual owner step outside item 8's Done.

M-5. Heterogeneous error composition: allow `composeE` across distinct error types with origin-preserving injections (`e1 + e2`), or record the single-`e` policy as final.
Depends on: —. Trigger: a composition spanning two distinct error types appears. Done = ① decision (injection API vs single-`e` policy) ② if adopted: origin-preservation witnesses + conformance row.

M-6. Law-committed instances (trusted construction): decide whether law commitment travels in types (a certificate wrapper around `Focusing`) or stays a documented assume–guarantee obligation.
Depends on: —. Trigger: a consumer must accept only law-committed instances. Done = ① decision recorded in §2/§4 ② if a wrapper is adopted: trusted constructor + admission tests.
