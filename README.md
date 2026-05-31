# Focal

**Explicit-residual focus interface for Haskell.** A single abstraction — `Focusing c s t a b` — that captures Lens, Zipper, evaluation contexts, and a family of ~12 structurally related specializations under one roof.

```haskell
data Focusing c s t a b = Focusing
  { splitF :: s -> (a, c)
  , plugF  :: c -> b -> t
  }
```

- **`s`** — source whole (original structure)
- **`t`** — target whole (structure after replacement)
- **`a`** — original focus (extracted from `s`)
- **`b`** — new focus (replaces `a` to form `t`)
- **`c`** — **residual context**: the first-class value recording "how to rebuild the whole from a replacement focus"

The library currently ships with a proof-of-concept set: Lens-like focusing, positional list focus, and tree-zipper navigation.

---

## Metadata

| Field | Value |
|---|---|
| **Package** | `Focal` |
| **Version** | `0.1.0.0` |
| **License** | BSD-3-Clause |
| **Compiler** | GHC ≥ 9.0, Haskell Stack |
| **Dependencies** | `base >= 4.7 && < 5` |
| **Tests** | Tasty + QuickCheck (zipper round-trips, composition laws, concrete examples) |

---

## What problem does this solve?

Lenses conflate two things: *which part you're looking at* and *how to rebuild the whole from a replacement*. The residual context — everything except the focus — is hidden inside the lens representation.

Zippers expose the residual as a concrete derivative stack, but are bound to tree navigation.

**Focal** generalizes both. The residual `c` is a first-class, inspectable, composable value. You can:

- Compose focusings with `(>>>)` (residuals accumulate as nested pairs)
- Apply monadic functions through `overFM` (effects stay in the outer Monad)
- Forget the residual to get Store-like interop with Lens via `toStoreLike`
- Keep the residual explicit for navigation, provenance tracking, or change propagation

The key architectural boundary: **Focal handles spatial decomposition; Monad handles temporal sequencing.** They compose cleanly via `overFM`.

---

## What's implemented

### 1. Lens-like Focal (`Focal.Core`, `Focal.Tuple`)

The residual **is** the original whole — enough for putback, nothing more.

```haskell
pureF :: (s -> a) -> (s -> b -> t) -> Focusing s s t a b
-- Under the hood: splitF s = (view s, s); plugF s b = set s b
```

`fstF` and `sndF` are concrete instances for pairs. This is the interop surface with `lens`/`optics`: `toStoreLike` projects a `Focusing` into a Store-like `(a, b -> t)`.

### 2. Positional list focus (`Focal.List`)

The residual is `(left segment, right segment)` — positional geometry, not raw source.

```haskell
type ListCtx a = ([a], [a])

elementF :: Int -> Maybe (Focusing (ListCtx a) [a] [a] a a)
-- splitF [1,2,3] at index 1 → (2, ([1], [3]))
-- plugF  ([1], [3]) 20     → [1,20,3]
```

Unlike a Lens, the residual carries the *position* of the focus, not the whole list. This is a stepping stone toward structured editing contexts.

### 3. Tree zipper (`Focal.Zipper`)

The residual is a derivative frame stack — the intensional specialization of `Focusing` for fixed-root tree navigation.

```haskell
class ZipTree t where
  type Frame t
  type Child t
  descend :: Child t -> t -> Maybe (t, Frame t)
  ascend  :: Frame t -> t -> t

fromZip :: ZipTree t => Zip t -> Focusing [Frame t] t t t t
```

Shipped instances: `BinTree` (binary, with left/right frames) and `Rose` (n-ary, with parent label + sibling lists). The round-trip law `ascend frame (descend child t) == t` is QuickCheck-verified.

### 4. Identity focus (`Focal.Core`)

```haskell
idF :: Focusing () s s s s
-- Residual is () — the focus IS the whole.
```

Serves as the unit of composition (`>>>`). Used in law tests to verify associativity and identity.

---

## Axiomatic foundation

Focal is not just a data type — it's a **lawful explicit-residual focus** interface. The six core axioms below are not arbitrary syntactic requirements; they are reverse-engineered from the uses Focal is designed to support: Zipper, Lens-like optic, Redex context, Refactoring, Persistence view-update, and beyond.

### Central principle

> The residual context `c` must be concrete enough to rebuild, navigate, and interpret local edits — but restricted enough that it does not absorb application semantics and effects.

### Core axioms

| # | Axiom | Status in library | Test coverage |
|---|---|---|---|
| **A1** | **Split—Plug Reconstruction**: `let (a, c) = splitF f s in plugF f c a == s` | Enforced structurally | 8 properties — `idF`, `fstF`, `sndF`, list, Rose, BinTree, `pureF`, composed |
| **A2** | **Residual Legality**: `c` derives from a legitimate `splitF`, not an arbitrary forgeable value | `Focal` existential hides `c`; `Focusing` constructor exported (by design for inspection) | 3 properties — `idF`, list, Rose residuals tied to source |
| **A3** | **Composition Associativity**: `(f >>> g) >>> h ≃ f >>> (g >>> h)` up to residual reassociation `((c1,c2),c3) ≃ (c1,(c2,c3))` | `>>>` nests residuals as pairs; behaviourally equivalent | 4 properties — `idF` chain, tuple chain, cross-module, plug law |
| **A4** | **Identity Focus**: `idF >>> f ≃ f` and `f >>> idF ≃ f` | `idF` with `()` residual; law holds behaviourally | 6 properties — `fstF`, list element, zipper (left and right) |
| **A5** | **Locality**: `plugF : c -> b -> t` — no Env, no IO, no global state | Type-enforced: no effects in signature | 1 property — `overFM` purity check |
| **A6** | **Occurrence ≠ Value**: focus identity is `(a, c)`, not `a` alone; equal values at different positions yield different residuals | Residuals differ by position; type system tracks `c` | 3 properties — list (equal values at different indices), Rose, BinTree |

### Extension axioms

These extend the core for typed syntax, navigation, editing, sharing, and strategy. They are documented as the boundary between Focal's geometric guarantees and domain-specific semantics.

| # | Axiom | Status |
|---|---|---|
| **XB** | **Path—Residual Consistency**: path view and residual view agree (`focusAt` / `pathOf` roundtrip) | 4 properties — `safeFocusAt`, `fromZip` roundtrip, multi-level navigation |
| **XD** | **Edit Survival**: same-focus edits compose; nested edits decompose; independent foci commute (prefix-controlled fragment) | 3 properties — sequential `overF` composition, nested decomposition, independent-focus commutation |
| **XA** | **Type Endpoints**: residual carries endpoint sorts; replacement preserves focus sort | Deferred — requires indexed GADTs |
| **XC** | **Navigation Normalization**: arbitrary navigation normalizes to LCA + down only under tree-like and decidable-child assumptions | Implicit in `safeNavigate`; decidable-child not formalized |
| **XE** | **Sharing Boundary**: occurrence focus ≠ vertex/entity focus for DAGs | Deferred — documented boundary in DAG section |
| **XF** | **Strategy Externalization**: evaluation strategies live outside Focal core | By design — no strategy in `plugF` |
| **XG** | **Computability Witness**: child selection requires decidable equality | Not yet exposed — `ZipTree` defaults to `Int` |

### Coverage summary

The test suite has **43 QuickCheck properties** organized by axiom:

- **A1** (8) — Split/plug roundtrip for all shipped focusings
- **A2** (3) — Residual validity tied to source
- **A3** (4) — Composition associativity including cross-module
- **A4** (6) — Identity: left and right for tuple, list, zipper
- **A5** (1) — Locality: monadic bridge purity
- **A6** (3) — Occurrence ≠ value: list, Rose, BinTree
- **XB** (4) — Path—residual consistency: focusAt, fromZip, multi-level
- **XD** (3) — Edit survival: composition, nesting, commutation
- **Zipper** (4) — Descend/ascend and up/down roundtrips
- **Concrete + Regression** (7) — Tuple, list, edge cases

---

## The four degrees of freedom

`Focusing c s t a b` is not a single interface — it is a **template** that specializes into distinct types depending on how four questions are answered. These four dimensions are independent, and their combinations generate the space of all useful specializations:

### Dimension 1: Cardinality — one, zero, or many?
The focus `a` might be a single element (Lens, Zipper), an optional element (Prism), or a traversal over multiple elements. `Focusing` currently handles the single-focus case; multi-focus requires residual semantics for merging changes across positions.

### Dimension 2: What is the residual `c`?
- **Stack** (Zipper) — derivative frames for tree navigation
- **Provenance** (Persistence, Query) — database lineage or join witnesses
- **Continuation** (Redex/Evaluation) — the rest of the program to resume
- **Delta trace** (Incremental, Patch) — change-history to propagate
- **Transaction plan** (Workflow) — the surrounding state-machine context

### Dimension 3: How does `plug` operate?
- **Pure structural rebuild** — trust the residual to reconstruct (Lens, Zipper, List)
- **Strategy reduction** — evaluation contexts dictate the order of contraction (Redex)
- **Change propagation** — the residual guides how a local delta becomes a global delta (Incremental, Patch)
- **Database transaction** — the residual encodes a view-update policy (Persistence, Query)
- **Validation gate** — the residual contains a validator that either accepts or rejects the replacement (UI/Form, Workflow)

### Dimension 4: What guarantees legality?
- **Structural types** — the residual's type encodes invariants (Indexed/Typed Syntax Focal)
- **Runtime validation** — `Either Error` in the return type (Form, Workflow)
- **Proof witness** — a separate certificate of correctness (if using dependent types)
- **External transaction** — the database or system of record is the source of truth (Persistence)

---

## The twelve-specialization landscape

These four dimensions combine naturally to produce the following family. They are ranked by how directly they inherit from the core `Focusing` structure — not by engineering importance.

### Strong specializations (residual IS the core structure)

These map cleanly onto `Focusing` without adding new conceptual machinery. The residual is the primary data structure, and `plug` is deterministic given the residual.

| # | Specialization | Residual `c` | `plug` behavior | Impl? |
|---|---|---|---|---|
| 1 | **Lens-like** | Original source `s` | Pure setter | ✅ `fstF`, `sndF`, `pureF` |
| 2 | **Zipper** | Frame stack `[Frame t]` | Structural rebuild | ✅ `fromZip` |
| 3 | **List position** | `(left, right)` segments | Concatenation | ✅ `elementF` |
| 4 | **Typed Syntax** | Indexed stack `Stack j i` | Sort-checked rebuild | ❌ |
| 5 | **Redex / Evaluation** | Evaluation context | Contraction strategy | ❌ |

- **Typed Syntax Focal** (4) is the indexed version: the residual carries both the tree path and the endpoint sorts, so a replacement with the wrong sort is a type error, not a runtime failure. It requires GADTs and type-level path tracking, which is why it's not in the initial release — but it is a natural extension of `Focal.Zipper`.

- **Redex Focal** (5) is a Focal where `plug` is not structural rebuild but **operational semantics**: the evaluation context dictates how to contract the redex. This is not Lens or Zipper — it's the decompose-contract-plug loop that underlies abstract machines. Danvy and Nielsen's refocusing work shows how this loop fuses into a single state-transition function. Focal gives this a type.

### Medium-strong specializations (residual carries extra semantics)

These still fit the `split`/`plug` shape, but the residual carries *semantic provenance* beyond raw geometry. `plug` produces a delta, a validated result, or a change plan — not just a rebuilt structure.

| # | Specialization | Residual `c` | `plug` produces | Impl? |
|---|---|---|---|---|
| 6 | **Refactoring** | Syntax stack + layout/type/scope facts | AST edit | ❌ |
| 7 | **Patch / Delta** | Survival/reindexing witness | `Delta s` or conflict | ❌ |
| 8 | **Incremental Computation** | Dependency trace + memo cells | `OutputDelta` | ❌ |
| 9 | **UI / Form** | Widget path + validation context | `ModelDelta` or error | ❌ |
| 10 | **Parser / Grammar** | Parser state + choice provenance | Parse forest | ❌ |

- **Refactoring Focal** (6) extends the zipper residual with layout information, scope snapshots, type facts, and span data. This is what IDE refactoring tools (extract-local, rename, case-split) need: not just "where" but "what's around it semantically." Focal's split/plug boundary captures exactly the tree-traversal and local-replacement part. The rest — alpha-equivalence, substitution, binder-sensitive equality — lives *outside* Focal in a language-semantics layer.

- **Patch Focal** (7) and **Incremental Focal** (8) are closely related: the residual tracks *what survived* a structural edit and *what depends on what*. `plug` produces a delta rather than a wholesale rebuild. This is the space where build systems (incremental compilation) and structured editors (AST patching) live.

- **UI/Form Focal** (9) bridges the gap between a presentation-level field value and a domain model. The residual includes the widget path (where in the form tree), the validation context, and a snapshot of the original model. `plug` runs validation and produces a model delta or an error — not a raw structural rebuild.

- **Parser Focal** (10) is the most unusual of this group: the residual carries parser state and grammar-choice provenance. Unlike a tree zipper, grammar zippers must handle non-tree structures, ambiguity, and the interaction between parser state and AST position.

### Weaker specializations (domain frameworks, borderline Focal)

These still satisfy the split/plug contract, but the residual becomes dominated by domain semantics rather than Focal's structural decomposition. They are useful patterns, but calling them "Focal specializations" rather than "domain frameworks that happen to use Focal" becomes debatable.

| # | Specialization | Residual `c` | `plug` produces |
|---|---|---|---|
| 11 | **Query / Relational** | Projection provenance + join witnesses | `RelDelta` or `AmbiguousPutback` |
| 12 | **Workflow / State-Machine** | Transition context + rollback plan | Workflow or `InvalidTransition` |

- **Query Focal** (11) is adjacent to Persistence Focal but operates at the relational algebra level (materialized views, BI dashboards). The hard problem is not decomposition but *putback policy* — when a user edits a projection, which base relations should change? This is the view-update problem from bidirectional transformation research.

- **Workflow Focal** (12) treats a long-running process as a focusable structure: the current task is the focus, the surrounding workflow state is the residual, and `plug` checks transition validity. It is not a Monad replacement — Monad sequences effects; Focal locates the current task within the workflow's spatial/topological structure.

---

## Why these four and not the other eight?

The library implements ~3.5 of the 12 specializations. The choice is not arbitrary — it follows a deliberate boundary:

### What's in scope for the core library

1. **Pure structural decomposition** — `splitF` and `plugF` are total, deterministic functions. The residual is geometric (position, frame stack, segments). No external state, no IO, no database.

2. **Fixed-root tree replacement** — the library's strongest result is the zipper fiber: for trees where every reachable vertex has a unique root path, the zipper context is proof-irrelevant (rebuilding is unique). This is the "sweet spot" for Focal's geometric guarantees.

3. **Composition is mechanical** — `(>>>)` nests residuals as `(c1, c2)`. This trivial composition works because the library deals only with pure spatial decomposition.

### What's explicitly deferred

The remaining ~8 specializations require one or more of these, which the library deliberately does not provide:

| Requirement | Affected specializations |
|---|---|
| **Dependent / indexed types** (sort tracking at the type level) | Typed Syntax (4) |
| **Operational semantics** (evaluation strategy, not just rebuild) | Redex (5) |
| **Language-specific provenance** (alpha-equivalence, binding, substitution) | Refactoring (6) |
| **Conflict detection & resolution** (non-trivial merge semantics) | Patch (7), Query (11) |
| **Mutable dependency graphs** (invalidation, incremental recomputation) | Incremental (8) |
| **Validation logic** (domain-specific, runtime-checked) | UI/Form (9), Workflow (12) |
| **Non-tree structures** (grammars, DAGs with sharing, relational joins) | Parser (10), Query (11) |

Each of these is a genuine engineering problem that the Focal pattern can *structure* but not *solve*. The library draws the line at geometric decomposition of pure tree-like structures. Everything beyond that belongs in downstream packages that depend on `Focal.Core` but add domain-specific semantics.

### The DAG boundary

The Zipper module explicitly works only on trees where each reachable vertex has a unique root path. When sharing is introduced (DAGs, common subexpression elimination, database views with joins), different paths to the same focus produce different residuals. The quotient from "occurrence zipper" (path-indexed) to "vertex position" requires additional merge or disambiguation logic that is not part of the core Focal contract.

---

## Quick start

```haskell
import Focal.Core
import Focal.Tuple
import Focal.List

-- Tuple focus
overF fstF (*2) (3, "world")  -- → (6, "world")
overF sndF reverse ("hi", "there")  -- → ("hi", "ereht")

-- List element focus
overF (unsafeElementF 2) (*10) [1, 2, 3, 4, 5]  -- → [1, 2, 30, 4, 5]

-- Composition: focus deeper
let deep = fstF >>> fstF  -- inside ((a, b), c), focus on a
overF deep show ((42, "x"), True)  -- → (("42", "x"), True)

-- Monadic bridge
overFM fstF (\x -> putStrLn ("Got: " ++ show x) >> pure (x + 1)) (41, "ok")
-- prints "Got: 41", returns (42, "ok")

-- Zipper (binary tree)
import Focal.Zipper
let t  = Node (Node (Leaf 1) (Leaf 2)) (Leaf 3)
    Just f = safeFocusAt [GoLeft, GoRight] t
overF f (*10) t  -- doubles the right child of the left subtree
```

---

## Related work

- **Clowns to the Left of Me, Jokers to the Right** ([POPL '08](https://doi.org/10.1145/1328438.1328474)) — McBride's dissection of datatypes into one-hole contexts where elements to the left and right of the hole are distinguished in type. The `ListCtx` and zipper frame stacks in this library are concrete instances of this idea.
- **Profunctor Optics** ([arXiv:1703.10857](https://arxiv.org/abs/1703.10857)) — Unified categorical treatment of Lens, Prism, Traversal. Focal is orthogonal: it exposes the residual that profunctor optics abstract away.
- **Refocusing in Reduction Semantics** ([BRICS RS-04-26](https://www.brics.dk/RS/04/26/)) — Danvy & Nielsen's fusion of decompose-contract-plug into a single state transition. The Redex Focal specialization directly mirrors this loop.
- **Bidirectional Transformations** ([arXiv:2502.18954](https://arxiv.org/abs/2502.18954)) — The view-update problem in databases, structured documents, and model transformation. Persistence Focal and Query Focal are the Focal-shaped interface to this research area.
- **Self-Adjusting Computation** ([CMU](https://www.cs.cmu.edu/~rwh/students/acar.pdf)) — Incremental computation via dependency tracking and change propagation. The Incremental Computation Focal builds on these ideas.

---

## License

BSD-3-Clause. See [LICENSE](LICENSE).
