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
| **Package** | `focal-core` |
| **Version** | `0.2.0.0` |
| **License** | BSD-3-Clause |
| **Compiler** | GHC ≥ 9.2, Haskell Stack |
| **Dependencies** | `base >= 4.16 && < 5` |
| **Tests** | Tasty + QuickCheck (zipper round-trips, composition laws, concrete examples); doctest gate included; classification in [docs/conformance.md](docs/conformance.md) |

---

## What problem does this solve?

Lenses conflate two things: *which part you're looking at* and *how to rebuild the whole from a replacement*. The residual context — everything except the focus — is hidden inside the lens representation.

Zippers expose the residual as a concrete derivative stack, but are bound to tree navigation.

**Focal** generalizes both. The residual `c` is a first-class, inspectable, composable value. You can:

- Compose focusings with `(>>>)` (residuals accumulate as nested pairs)
- Apply effectful functions through `overFM` — only `Functor` is required (effects stay in the outer functor)
- Forget the residual to get Store-like interop with Lens via `toStoreLike`
- Keep the residual explicit for navigation, provenance tracking, or change propagation

The key architectural boundary: **Focal handles spatial decomposition; the functor handles external interpretation.** They compose cleanly via `overFM`, whose type requires only `Functor` — the Van Laarhoven interpretation formula `fmap rebuild (k a)`.

---

## What's implemented

### 1. Lens-like Focal (`Focal.Core`, `Focal.Tuple`)

The residual **is** the original whole — enough for putback, nothing more.

```haskell
pureF :: (s -> a) -> (s -> b -> t) -> Focusing s s t a b
-- Under the hood: splitF s = (view s, s); plugF s b = set s b
```

`fstF` and `sndF` are concrete instances for pairs. The shipped interop surface with `lens`/`optics` is `toStoreLike`, which projects a `Focusing` into a Store-like `(a, b -> t)`; the Van Laarhoven conversions (`toVL`/`fromVL`) ship in `Focal.Interop` and hold extensionally only — see [docs/foundation.md](docs/foundation.md) §5.

### 2. Positional list focus (`Focal.List`)

The residual is `(left segment, right segment)` — positional geometry, not raw source.

```haskell
type ListCtx a = ([a], [a])

elementF :: Int -> Maybe (Focusing (ListCtx a) [a] [a] a a)
-- splitF [1,2,3] at index 1 → (2, ([1], [3]))
-- plugF  ([1], [3]) 20     → [1,20,3]
```

Failure-channel variant: `elementE :: Int -> FocusingE ListError (ListCtx a) [a] [a] a a`
— the index check runs at every split against the supplied list:
`overE (elementE 1) (*10) [1,2,3] == Right [1,20,3]`,
`splitE (elementE 9) [1,2,3] == Left (PastEnd 9)`.

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

By-path focus is dynamic (`focusAt`, checked at construction); its failure-channel counterpart `focusAtE` is total at construction and reports the first missing path step as `Left (PathError i)` at split time.

### 4. Identity focus (`Focal.Core`)

```haskell
idF :: Focusing () s s s s
-- Residual is () — the focus IS the whole.
```

Serves as the unit of composition (`>>>`). Used in law tests to verify associativity and identity.

### 5. Failure channel (`Focal.Partial`)

```haskell
data FocusingE e c s t a b = FocusingE
  { splitE :: s -> Either e (a, c)
  , plugE  :: c -> b -> Either e t
  }

overE :: FocusingE e c s t a b -> (a -> b) -> s -> Either e t
```

Failures travel in return values instead of deferred errors. `composeE` runs
split outer→inner and plug inner→outer; the first `Left` short-circuits.
`toPartial` embeds any pure `Focusing`; `toStoreE`/`fromStoreE` give the
partial Store reading.

### 6. Effectful rebuild (`Focal.Effectful`)

```haskell
data FocusingM m c s t a b = FocusingM
  { splitM :: s -> m (a, c)
  , plugM  :: c -> b -> m t
  }
```

Both legs live in a monad `m`: failures (`m = Either e`), validation, logging
(`m = Writer`), and stateful reconstruction (`m = State`). `FocusingE` is the
`m = Either e` case (`toEffectfulE`); a pure `Focusing` embeds by purity
(`toEffectful`). GP/PG hold as Kleisli equations and are preserved by
`composeM` for every monad; PP holds per instance in the replay-prefix form.

### 7. Generic one-hole contexts (`Focal.Generic`)

One-hole contexts of the leftmost *direct* occurrence of the type parameter, derived from `Generic1` representations (`Derivative1`/`Ctx1`, `genericSplit1`/`genericPlug1`, `genericFocus`); the shipped `Rose` tree is migrated at its root label. Direct occurrences only — a parameter reachable only under another functor or recursion has no generic hole.

### 8. Optional focus (`Focal.Optional`)

```haskell
data FocusingO c s t a b = FocusingO
  { splitO :: s -> Maybe (a, c)
  , plugO  :: c -> b -> t
  }

overO :: FocusingO c s s a b -> (a -> b) -> s -> s
```

A miss is **absence**, not failure: `overO` passes the source through unchanged
and `composeO` short-circuits on the first miss. With a list-head focus,
`overO headO (+1) [1,2] == [2,2]` on a hit and `overO headO (+1) [] == []` on a
miss.

---

## Law status

Focal is not just a data type — it's a focus **interface with explicit law obligations** (see [docs/foundation.md](docs/foundation.md)): every guarantee it makes is classified as an axiom, a definitional identity, a corollary, a representation theorem, or a contract.

The library's **only axiom** is **A-LENS**: every *lawful* instance satisfies, on its declared domain, the three clauses below. Everything else Focal states is a definitional identity, a corollary, a representation theorem, or a contract. A-LENS is an assume–guarantee obligation, not a structural guarantee — the `Focusing` constructor is public and `plugF` receives no `s`, so legality is established per instance by witnesses.

| Clause | Statement (mono form: `s = t`, `a = b`) |
|---|---|
| **GP** (rebuild) | `plugF f (snd (splitF f s)) (fst (splitF f s)) == s` |
| **PG** (retrieve) | for `c` in the image of `snd . splitF`: `fst (splitF f (plugF f c b)) == b` |
| **PP** (overwrite) | for such `c` and `b1`, `b2`, with `(_, c') = splitF f (plugF f c b1)`: `plugF f c' b2 == plugF f c b2` |

### Central principle

> The residual context `c` must be concrete enough to rebuild, navigate, and interpret local edits — but restricted enough that it does not absorb application semantics and effects.

### Hierarchy

| Level | What it is | Enforced by | Witness |
|---|---|---|---|
| **L0** | Structure facts (`Focusing` signatures; public constructor) | The type system | Signature inspection |
| **L1** | Axiom **A-LENS** (GP ∧ PG ∧ PP) | Assumption per instance | L-GP / L-PG / L-PP families — see conformance |
| **L2** | Definitional identities (`idF`; `composeF` plug law) | Definition | Definitional (no failure mode) |
| **L3** | Corollaries (occurrence ≠ value; associativity/unit modulo residual reassociation) | Derivation | L-ASSOC / L-UNIT families |
| **L4** | Representation theorems (CPS, coend/co-Yoneda, Van Laarhoven form, the Either and effectful readings) | Cited proofs + premises | Paper proofs — [docs/foundation.md](docs/foundation.md) §5 |
| **L5** | Contracts (domains, failure modes, input invariance) | Documentation + conformance matrix | [docs/conformance.md](docs/conformance.md) |
| **L6** | Engineering constraints (scope and process) | Review / CI | [ROADMAP.md](ROADMAP.md) §0 |

**Test families.** The suite is law-id tagged — `L-GP`, `L-PG`, `L-PP`, `L-OVF`, `L-ASSOC`, `L-UNIT`, `L-NORM`, `L-TVL` — plus their partial success-premise variants (`prop_*E_*`), contract groups (`focusAt`, `focusAtE`, `elementAt`, `elementE`, snapshot contracts, discriminators), the failure-channel wiring group (`FocusingE`), the effectful groups (`FocusingM`: laws, composition/embedding/store, discriminators), the navigation algebra (`prop_nav_*`), the generic-derivation group (`prop_gen_*`), the optional-focus group (`prop_opt_*`), and regression groups; per-instance witnesses are listed in the conformance matrix.

**Boundary notes.** `XA` (type endpoints): deferred — requires indexed GADTs. `XC` (navigation normalization): discharged — frames record their selector (`childOf`), so path↔frame conversion decides the selector directly; no child enumeration. `XE` (sharing boundary): occurrence focus ≠ vertex focus for DAGs — documented boundary. `XF` (strategy externalization): no strategy in `plugF`, by design. `XG` (computability witness): `ZipTree` child selection defaults to `Int`; not yet exposed.

### Coverage

The test suite has **136 QuickCheck properties** plus a doctest suite; every law-id has witnesses — classification and per-instance verdicts in [docs/conformance.md](docs/conformance.md).

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
- **Context fill** — the residual is an evaluation context; the fill itself is structural, and contraction lives in the surrounding decompose-contract loop (Redex)
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
| 2 | **Zipper** | Frame stack `[Frame t]` | Structural rebuild (snapshot ‡) | ✅ `fromZip` |
| 3 | **List position** | `(left, right)` segments | Concatenation | ✅ `elementF` |
| 4 | **Typed Syntax** | Indexed stack `Stack i j` | Sort-checked rebuild | ✅ `Focal.Syntax.Stack` |
| 5 | **Redex / Evaluation** | Evaluation context `EvalCtx` | Context fill (strategy outside) | ✅ `Focal.Redex` † |

*† Row 5 registers on the optional rung (`FocusingO`): its focus is a whole-root redex; the wider decompose-contract-plug loop reports the redex sort existentially (`Decomp`), reaching redexes below the root. ‡ `fromZip` is a snapshot constructor: `splitF` ignores its argument — see [docs/foundation.md](docs/foundation.md) §4.2; by-path focus is the dynamic `focusAt`.*

- **Typed Syntax Focal** (4) is the indexed version: the residual carries both the tree path and the endpoint sorts, so a replacement with the wrong sort is a type error, not a runtime failure. It requires GADTs and type-level path tracking; it ships in the `focal-syntax` package (`Focal.Syntax.Stack`).

- **Redex Focal** (5) ships the decompose-contract-plug loop (`Focal.Redex`): `decompose` finds the canonical (leftmost-outermost) redex and its evaluation context, `contract` performs the beta step, and `plug` fills the context — the law-bearing direction is `plug (E, r) = t`, with the strategy outside the plug. This is not Lens or Zipper — it's the loop that underlies abstract machines; Danvy and Nielsen's refocusing work shows how it fuses into a single state-transition function. Focal gives this a type.

### Medium-strong specializations (residual carries extra semantics)

These still fit the `split`/`plug` shape, but the residual carries *semantic provenance* beyond raw geometry. `plug` produces a delta, a validated result, or a change plan — not just a rebuilt structure.

| # | Specialization | Residual `c` | `plug` produces | Impl? |
|---|---|---|---|---|
| 6 | **Refactoring** | Syntax stack + layout/type/scope facts | AST edit | ✅ `focal-refactor` |
| 7 | **Patch / Delta** | Survival/reindexing witness | `Delta s` or conflict | ✅ `focal-delta` |
| 8 | **Incremental Computation** | Dependency trace + memo cells | `OutputDelta` | ✅ `focal-incremental` |
| 9 | **UI / Form** | Widget path + validation context | `ModelDelta` or error | ✅ `focal-form` |
| 10 | **Parser / Grammar** | Parser state + choice provenance | Parse forest | ✅ `focal-parser` |

*Rows 7–10 carry their domain failure channels as return values (`Either` reports: conflicts, invalidation, validation errors, ambiguity) rather than at the `Focusing` rung; every row's verdicts are registered in [docs/conformance.md](docs/conformance.md).*

- **Refactoring Focal** (6) extends the zipper residual with layout information, scope snapshots, type facts, and span data. This is what IDE refactoring tools (extract-local, rename, case-split) need: not just "where" but "what's around it semantically." Focal's split/plug boundary captures exactly the tree-traversal and local-replacement part. The rest — alpha-equivalence, substitution, binder-sensitive equality — lives *outside* Focal in a language-semantics layer.

- **Patch Focal** (7) and **Incremental Focal** (8) are closely related: the residual tracks *what survived* a structural edit and *what depends on what*. `plug` produces a delta rather than a wholesale rebuild. This is the space where build systems (incremental compilation) and structured editors (AST patching) live.

- **UI/Form Focal** (9) bridges the gap between a presentation-level field value and a domain model. The residual includes the widget path (where in the form tree), the validation context, and a snapshot of the original model. `plug` runs validation and produces a model delta or an error — not a raw structural rebuild.

- **Parser Focal** (10) is the most unusual of this group: the residual carries parser state and grammar-choice provenance. Unlike a tree zipper, grammar zippers must handle non-tree structures, ambiguity, and the interaction between parser state and AST position.

### Weaker specializations (domain frameworks, borderline Focal)

These still satisfy the split/plug contract, but the residual becomes dominated by domain semantics rather than Focal's structural decomposition. They are useful patterns, but calling them "Focal specializations" rather than "domain frameworks that happen to use Focal" becomes debatable.

| # | Specialization | Residual `c` | `plug` produces | Impl? |
|---|---|---|---|---|
| 11 | **Query / Relational** | Projection provenance + join witnesses | `RelDelta` or `AmbiguousPutback` | ✅ `focal-query` |
| 12 | **Workflow / State-Machine** | Transition context + rollback plan | Workflow or `InvalidTransition` | ✅ `focal-workflow` |

*Rows 11–12 ship as annotated domain frameworks ([docs/foundation.md](docs/foundation.md) §1): v1 keeps the minimal implementations above, and their domain rules — view-update policy, transition semantics — stay outside the core (§0.8).*

- **Query Focal** (11) is adjacent to Persistence Focal but operates at the relational algebra level (materialized views, BI dashboards). The hard problem is not decomposition but *putback policy* — when a user edits a projection, which base relations should change? This is the view-update problem from bidirectional transformation research. It ships in the `focal-query` package (v1: policy-ordered `relPutback`, ambiguity reported, never silently resolved).

- **Workflow Focal** (12) treats a long-running process as a focusable structure: the current task is the focus, the surrounding workflow state is the residual, and `plug` checks transition validity. It is not a Monad replacement — Monad sequences effects; Focal locates the current task within the workflow's spatial/topological structure. It ships in the `focal-workflow` package (v1: static transition validation and rollback plans; no liveness claims).

---

## Why these four and not the other eight?

The **core** implements the four strong specializations as laws; the other
eight ship as separate packages — rows 6–10 with minimal implementations
(`focal-refactor`, `focal-delta`, `focal-incremental`, `focal-form`,
`focal-parser`), rows 11–12 annotated as domain frameworks
(`focal-query`, `focal-workflow`). The choice is not arbitrary — it
follows a deliberate boundary:

### What's in scope for the core library

1. **Pure structural decomposition** — `splitF` and `plugF` are total on their declared domains and deterministic; partiality is confined to the registered failure modes ([docs/foundation.md](docs/foundation.md) §4). The residual is geometric (position, frame stack, segments). No external state, no IO, no database.

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

-- Functor-level bridge (only `Functor` is required)
overFM fstF (\x -> putStrLn ("Got: " ++ show x) >> pure (x + 1)) (41, "ok")
-- prints "Got: 41", returns (42, "ok")

-- Zipper (binary tree). `focusAt` re-navigates the supplied tree on every
-- split, so the focus is the one at `path` in whichever tree you apply it to.
import Focal.Zipper
let t  = Node (Node (Leaf 1) (Leaf 2)) (Leaf 3)
    Just f = focusAt [GoLeft, GoRight] t
overF f (*10) t  -- multiplies the right child of the left subtree by 10
```

---

## Related work

- **Clowns to the Left of Me, Jokers to the Right** ([POPL '08](https://doi.org/10.1145/1328438.1328474)) — McBride's dissection of datatypes into one-hole contexts where elements to the left and right of the hole are distinguished in type. The `ListCtx` and zipper frame stacks in this library are concrete instances of this idea.
- **Profunctor Optics** ([arXiv:1703.10857](https://arxiv.org/abs/1703.10857)) — Unified categorical treatment of Lens, Prism, Traversal. Focal is orthogonal: it exposes the residual that profunctor optics abstract away.
- **Refocusing in Reduction Semantics** ([BRICS RS-04-26](https://www.brics.dk/RS/04/26/)) — Danvy & Nielsen's fusion of decompose-contract-plug into a single state transition. The Redex Focal specialization directly mirrors this loop.
- **Bidirectional Transformations** ([arXiv:2502.18954](https://arxiv.org/abs/2502.18954)) — The view-update problem in databases, structured documents, and model transformation. Persistence Focal and Query Focal are the Focal-shaped interface to this research area.
- **Self-Adjusting Computation** ([CMU](https://www.cs.cmu.edu/~rwh/students/acar.pdf)) — Incremental computation via dependency tracking and change propagation. The Incremental Computation Focal builds on these ideas.
- **A Representation Theorem for Second-Order Functionals** ([JFP '15](https://doi.org/10.1017/S0956796815000088)) — Jaskelioff & O'Connor's representation theorem for second-order functionals; the Van Laarhoven-form reading of `Focusing` in [docs/foundation.md](docs/foundation.md) §5 rests on it.
- **(Co)end Calculus** ([arXiv:1501.02503](https://arxiv.org/abs/1501.02503)) — Loregian's treatment of (co)ends and the co-Yoneda lemma; `Focal`'s existential packaging is a coend, characterized extensionally as `S → (A × (B → T))` — see [docs/foundation.md](docs/foundation.md) §5 for the caveats.

---

## License

BSD-3-Clause. See [LICENSE](LICENSE).
