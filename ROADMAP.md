# Focal Roadmap

## 0. Constraints

0.1. Preserve core shape: `Focusing c s t a b = splitF :: s -> (a,c)` + `plugF :: c -> b -> t`; `c` must be a first-class residual.

0.2. `focal-core` does pure structural decomposition, fixed-root reconstruction, and mechanical composition only. IO, databases, validation, conflict merging, dependency graphs, and semantic bindings all go into extension packages.

0.3. Current default is single-focus; multi-focus must first define residual merge semantics and must not be stuffed directly into core.

0.4. Strong specializations before weak ones: Lens-like, List, Zipper, Typed Syntax, Redex first; Query, Workflow last.

0.5. Any implementation must uphold round-trip, identity, associativity, and composition plug laws.

---

## 1. Establish `focal-core` Package Boundary

Export only: `Focusing`, `splitF`, `plugF`, `idF`, `composeF/(>>>)`, `overF`, `overFM`.

## 2. Establish Law Testing Framework

Write unified QuickCheck combinators for round-trip, identity, associativity, and composition plug laws.

## 3. Backfill Law Tests for Existing Implementations

`pureF`, `fstF`, `sndF`, `idF`, `elementF`, `fromZip`. Depends on: 1, 2.

## 4. Split Out `Focal.Partial`

Define `FocusingE e c s t a b`; move failures into `split` or `plug` return values. Depends on: 1.

## 5. Rewrite List Focus

Migrate `elementF` negative indices, out-of-bounds, and empty list cases into `FocusingE`; retain total-safe API. Depends on: 4.

## 6. Split Out `Focal.Effectful`

Define `FocusingM m c s t a b`; unify failure, validation, logging, and stateful reconstruction. Depends on: 4.

## 7. Normalize Residual Composition

Add `Residual2`, `Residual3`, flatten/unflatten, pretty/debug helpers to avoid long-term exposure of deeply nested pairs. Depends on: 1, 4.

## 8. Publish `focal-core-0.1`

Freeze core API, laws, partial/effectful extension points, and existing strong specializations. Depends on: 1-7.

## 9. Establish `focal-syntax`

Define typed AST examples, sort kinds, GADT nodes, typed paths. Depends on: 8.

## 10. Implement Typed Syntax Focal

`Stack i j`, sort-checked `split`, sort-checked `plug`; wrong-sort replacement must not type-check. Depends on: 9.

## 11. Add Laws for Typed Syntax Focal

Well-sorted round-trip, path preservation, ill-sorted replacement rejection. Depends on: 10.

## 12. Establish `focal-redex`

Define term, value, redex, evaluation context, contract. Depends on: 10.

## 13. Implement Redex Focal

`decompose :: Term -> Either Value (Redex, EvalCtx)`, `plug`/`contract`/`step`, forming a decompose-contract-plug loop. Depends on: 12.

## 14. Add Laws for Redex Focal

Plug-after-decompose, deterministic strategy, step preserves well-typedness. Depends on: 13.

## 15. Establish `focal-refactor`

Define syntax stack, span, layout, scope snapshot, type facts. Depends on: 10, 13.

## 16. Implement Binder-Aware Replacement

Alpha-renaming, capture avoidance, scope-preserving `plug`. Depends on: 15.

## 17. Implement Basic Refactoring Operations

Rename, extract local, inline, case split. Depends on: 16.

## 18. Establish `focal-delta`

Define `Delta`, survival witness, reindexing witness, conflict type. Depends on: 8.

## 19. Implement Structural Patch Focus

Local replacement produces global delta; conflicts return `Either Conflict Delta`. Depends on: 18.

## 20. Connect Refactoring to Delta

Refactoring operations output patches, not just new ASTs. Depends on: 17, 19.

## 21. Establish `focal-incremental`

Define dependency trace, memo cell, invalidation graph. Depends on: 19.

## 22. Implement Incremental Plug

Local delta drives invalidation; outputs `OutputDelta`. Depends on: 21.

## 23. Establish `focal-form`

Define widget path, model snapshot, validation context, field residual. Depends on: 6, 19.

## 24. Implement Form Putback

Field edit -> validation -> `Either Error ModelDelta`. Depends on: 23.

## 25. Establish `focal-parser`

Define parser state, grammar choice provenance, parse forest node focus. Depends on: 6, 10, 19.

## 26. Implement Grammar Focus

Parse forest local replacement, ambiguity preservation, non-tree residual. Depends on: 25.

## 27. Establish `focal-query`

Define projection provenance, join witness, view-update policy. Depends on: 19, 26.

## 28. Implement Relational Putback

View edit -> `Either AmbiguousPutback RelDelta`. Depends on: 27.

## 29. Establish `focal-workflow`

Define transition context, rollback plan, validation gate. Depends on: 6, 19, 24.

## 30. Implement Workflow Plug

Current task replacement -> transition validation -> `Either InvalidTransition Workflow`. Depends on: 29.

## 31. Cross-Package Consistency Tests

Core, syntax, redex, refactor, delta, incremental, form, parser, query, workflow share law vocabulary. Depends on: 8-30.

## 32. Publish `focal-0.2` Integration Release

Core stable; strong specializations available; mid-strength specializations have minimal implementations; weak specializations annotated as domain frameworks. Depends on: 31.
