# Focal — Foundation

Normative classification of every law, contract, and claim in this repository.
This file is the authority for what counts as an **axiom**; the README summarizes
it, and [`ROADMAP.md`](../ROADMAP.md) §0 carries engineering constraints.

Working tree: `focal-core-0.1.0.0` (unreleased), 2026-10-16. Code is ground truth: where
this document and the code disagree, the code wins and this document is fixed.

## 1. Terms and hierarchy

- **Declared domain** — the inputs for which a constructor promises to behave
  (e.g. `0 <= n < length xs` for `elementF`). Outside it, a registered failure
  mode applies instead.
- **Lawful instance** — a `Focusing` opted into **A-LENS** (§2) with per-instance
  witnesses registered in [`conformance.md`](conformance.md).
- **Residual image** — `image (snd . splitF)` for a given instance.
- **Failure channel** — `FocusingE e c s t a b` (`Focal.Partial`): failures travel
  in `Either e` return values; laws are the success-premise variants (§3). The
  **success domain** of a `FocusingE` is the set of sources whose `splitE`
  returns `Right`; residuals are taken from successful splits.
- **Optional focus** — 'FocusingO', 'composeO', 'overO', 'toOptional' (`Focal.Optional`):
  zero-or-one foci; a miss is absence with pass-through update, distinct from
  the failure channel (§3).
- **Effectful rung** — `FocusingM m c s t a b` (`Focal.Effectful`): failures,
  validation, logging, and state live in the monad `m`; `FocusingE` is the
  `m = Either e` case, and a pure `Focusing` embeds by purity.
- **Generic derivation** — 'Derivative1' / 'genericFocus' (`Focal.Generic`):
  one-hole contexts of the leftmost *direct* type-parameter occurrence,
  derived from `Generic1` representations (metadata wrappers delegate; sums
  delegate; products are left-biased; constants, `U1`, `V1`, and recursive
  children have no direct occurrence). Holes under recursive children remain
  the zipper's frame-stack territory.

| Level | Name | What it is | Enforced by | Violation consequence |
|---|---|---|---|---|
| **L0** | Structure definitions | `Focusing c s t a b` with `splitF :: s -> (a, c)`, `plugF :: c -> b -> t`; **type facts**: no `Env`/`IO`/state slot (locality), and the constructor is public, so forgery cannot be prevented at the type level; the failure-channel rung is `FocusingE e c s t a b` with `splitE :: s -> Either e (a, c)` and `plugE :: c -> b -> Either e t` (`Focal.Partial`); the effectful rung is `FocusingM m c s t a b` with `splitM :: s -> m (a, c)` and `plugM :: c -> b -> m t` (`Focal.Effectful`) | The type system | Cannot be prevented (registered per instance in `conformance.md`) |
| **L1** | Axiom | **A-LENS** (the only axiom): a lawful instance satisfies GP, PG, and PP on its declared domain (§2) | Assumption (assume–guarantee) + per-instance witness tests | Not in the lawful subclass; its behavior is protected by no law |
| **L2** | Definitional identities | `idF` behavior (`splitF idF s == (s, ())`, `plugF idF () b == b`); the `composeF` plug law (true by unfolding) | Definition | None (no failure mode) |
| **L3** | Corollaries | Occurrence ≠ value (corollary of GP); composition associativity and unit laws, modulo residual reassociation `((c1,c2),c3) ≅ (c1,(c2,c3))` | Derivation (§3) | None |
| **L4** | Representation theorems | `withFocal` CPS form; the coend / co-Yoneda characterization; the Van Laarhoven form (§5) | Cited proofs + premises | Citing past the premises is unsound |
| **L5** | Contracts | Constructor domains, codomains, failure modes, input invariance, claim discipline (§4) | Documentation + conformance matrix (+ later tests) | An unregistered exemption is a defect |
| **L6** | Engineering constraints | Scope boundaries and process — single home: `ROADMAP.md` §0 | Review / CI | Design defect |

A statement is an axiom iff it is *assumed* rather than derived or definitional,
and violations are not excluded by the types. Exactly one statement qualifies:
**A-LENS**.

## 2. The axiom: A-LENS

For the mono form (`s = t`, `a = b`), a lawful instance `f` satisfies, on its
declared domain:

- **GP (rebuild)** — `plugF f (snd (splitF f s)) (fst (splitF f s)) == s`
- **PG (retrieve)** — for every `c` in the residual image and every `b`:
  `fst (splitF f (plugF f c b)) == b`
- **PP (overwrite)** — for every such `c` and all `b1`, `b2`, with
  `(_, c') = splitF f (plugF f c b1)`:
  `plugF f c' b2 == plugF f c b2`

Well-formedness: GP and PG require `s ~ t` and `a ~ b`; PP requires `s ~ t`.
Where a shape does not satisfy this (e.g. the type-changing instance
`fstF :: Focusing b (a, b) (x, b) a x`), the clause is marked **N/A** for that
instance; it would need a type-changing lens-law system, which this library does
not provide.

### A-LENS is an assume–guarantee obligation

The `Focusing` constructor is public and `plugF` receives no `s`; nothing in the
types forces a residual to have come from `splitF`. GP/PG/PP can therefore be
assumed only for instances that declare themselves lawful and exhibit witnesses
(`conformance.md`). Violations are caught per instance, never per type.

### Independence witnesses

Each clause can fail while the other two hold.

**E1 — violates only PG** (`s = a = b = Int`):

```haskell
splitE1 :: Int -> (Int, Int)
splitE1 s = (0, s)

plugE1 :: Int -> Int -> Int
plugE1 c _ = c

-- check:
--   ( plugE1 (snd (splitE1 5)) (fst (splitE1 5)) == 5   -- GP holds
--   , fst (splitE1 (plugE1 0 9)) /= (9 :: Int) )        -- PG fails
-- == (True, True)
-- PP holds: the residual is the source itself, so re-deriving it is idempotent.
```

**E2 — violates only GP** (type-changing shape: `s :: Int`, `a :: Word`):

```haskell
splitE2 :: Int -> (Word, ())
splitE2 s = (fromIntegral (abs s), ())

plugE2 :: () -> Word -> Int
plugE2 () = fromIntegral

-- check:
--   ( plugE2 (snd (splitE2 (-5))) (fst (splitE2 (-5))) /= (-5 :: Int)  -- GP fails
--   , fst (splitE2 (plugE2 () (3 :: Word))) == 3 )                     -- PG holds
-- == (True, True)
-- PP holds: the residual is always ().
```

**E3 — violates only PP** (finite model; `a = b = B`):

```haskell
data S = T1 | X | Y
data C = C0 | C1
data B = B0 | B1

split3 :: S -> (B, C)
split3 T1 = (B0, C0)
split3 X  = (B1, C0)
split3 Y  = (B1, C1)

plug3 :: C -> B -> S
plug3 C0 B0 = T1
plug3 C0 B1 = X
plug3 C1 B0 = T1
plug3 C1 B1 = Y

-- GP holds for all of S; PG holds for all c and b.
-- PP fails at c = C1, b1 = B0, b2 = B1:
--   (_, c') = split3 (plug3 C1 B0) = split3 T1 = (B0, C0)   =>  c' = C0
--   plug3 C0 B1 = X   but   plug3 C1 B1 = Y   (X /= Y)
```

### Explicit negations

- Locality (`plugF` has no `Env`/`IO`) is an **L0** type fact — not an axiom,
  and no property can witness it.
- "Occurrence ≠ value" is an **L3** corollary of GP.
- The `idF` and `composeF` equations are **L2** definitional identities.
- Structural enforcement does **not** hold for A-LENS: the constructor is
  public and `plugF` receives no `s`.

## 3. Law vocabulary

Every law or contract claim in this repository cites one of the identifiers
below. "Witness" names existing tests (`../test/Spec.hs`); a **gap** is
scheduled in `ROADMAP.md`.

| law-id | Statement | Well-formed (mono) conditions | Obligation bearer | Witness |
|---|---|---|---|---|
| `L-GP` | `plugF f (snd (splitF f s)) (fst (splitF f s)) == s` | `s ~ t`, `a ~ b` | Lawful instances (A-LENS clause 1) | 15 of 136: `prop_lgp_*` (8), partial `prop_lgpE_*` (3), effectful `prop_lgpM_*` (4) |
| `L-PG` | `c ∈ residual image  ⇒  fst (splitF f (plugF f c b)) == b` | `s ~ t`, `a ~ b` | Lawful instances (clause 2) | 13 of 136: `prop_lpg_*` (7), partial `prop_lpgE_*` (2), effectful `prop_lpgM_*` (4) |
| `L-PP` | `let (_, c') = splitF f (plugF f c b1) in plugF f c' b2 == plugF f c b2`, for `c ∈ residual image` | `s ~ t` | Lawful instances (clause 3) | 9 of 136: `prop_lpp_*` (5), partial `prop_lppE_*` (2), effectful `prop_lppM_*` (2) (one trivially-satisfied snapshot case, `prop_lpp_fromZip`) |
| `L-OVF` | `overF f (g . h) == overF f g . overF f h` (heterogeneous shapes well-formed when `h :: a -> a`) | — | Lawful instances; implied by GP ∧ PG ∧ PP | 5 of 136: `prop_lovf_*` (four instances plus the partial success-prefix case) |
| `L-ASSOC` | `(f >>> g) >>> h ≅ f >>> (g >>> h)` modulo residual reassociation `((c1,c2),c3) ≅ (c1,(c2,c3))` | — | `composeF` construction + lawful instances | 3 of 136: `prop_lassoc_*` |
| `L-UNIT` | `idF >>> f ≅ f` and `f >>> idF ≅ f` | — | `idF` + lawful instances | 6 of 136: `prop_lunit_*` |
| `L-NORM` | `fromVL ∘ toVL = normalize` (extensional) | `Focal`-level (residual hidden) | `Focal.Interop` (shipped) | 2 of 136: `prop_lnorm_*` |
| `L-TVL` | `toVL (f >>> g) ≅ toVL f ∘ toVL g` | `Focal`-level | `Focal.Interop` (shipped) | 2 of 136: `prop_ltvl_*` |
| definitional (L2) | `plugF (composeF f g) (c1,c2) x == plugF f c1 (plugF g c2 x)` | — | `composeF`'s definition | — (definitional identities are not tested; ROADMAP 0b policy) |

Derived: GP ∧ PG ∧ PP ⇒ `L-OVF`. The derivation plugs `b1 = g1 a` (PG gives the
re-split focus `a' = g1 a`, using `(a, c) = splitF f s`), then applies PP with
`b2 = g2 a'` to move from the re-derived residual back to `c`.

`L-NORM` and `L-TVL` are extensional by necessity: `Focal` hides `c`, and an
existential in Haskell is not a quotient (§5). Any law needing the residual must
be stated on `Focusing`.

**Failure channel (`FocusingE`).** With failures in return values, the clauses
read with explicit success premises (success domain as in §1): **GP** — if
`splitE f s = Right (a, c)` then `plugE f c a = Right s`; **PG** — if
`plugE f c b = Right t` then `splitE f t = Right (b, c')`; **PP** — under the
same premise, `plugE f c' b2 = plugE f c b2` for all `b2` (outcomes compared
including `Left`); **OVF** — if `overE f h s = Right t` then
`overE f (g . h) s = overE f g t`. The unconditional forms are false (a failed
write leaves no `c'`): pinned by `prop_discE_ppNeedsSuccess`,
`prop_discE_uncondOVF`, and the wiring group `prop_scE_*`.

**Effectful rung (`FocusingM`).** With both legs in a monad `m`, the clauses
read as Kleisli equations: **GP** — `splitM f s >>= \ (a, c) -> plugM f c a
= return s`; **PG** — for all continuations `k`,
`plugM f c b >>= \ t -> splitM f t >>= \ (a', c') -> k t (a', c') a'` equals
the same with the pair's observation `a'` replaced by `b` (the effects of the
plug and of the re-split appear on both sides; the bare form demanding
`return b` is false with effects — `prop_discM_barePg`); **PP** — the replay-prefix equation:
`plugM f c b1 >>= \_ -> plugM f c b2` equals `plugM f c b1 >>= \ t ->
splitM f t >>= \ (_, c') -> plugM f c' b2` (the first write is shared, so
failures short-circuit together and no success premise is needed). It is
**not universal** — it fails for logging (`prop_discM_ppReplayLog`) and for
sign-flipping residuals (`prop_discM_ppReplayAbs`) — and holds per instance
(`prop_lppM_checked`, `prop_lppM_restore`); the stronger prefix-less form
(`… = plugM f c b2`) is false with effects (`prop_discM_ppLog`) and for
partial plugs (`prop_discM_ppPartial`).
**Composition closure:** GP and PG are preserved under 'composeM' for every
monad — bind associativity plus the component laws, no commutativity needed —
witnessed by `prop_compM_*` and an exhaustive small-universe sweep.

**Type-changing fragment.** The clauses above hold at *coherent* instantiations — exactly those where the equation is well-typed; the side conditions are: GP needs `t ~ s` and `b ~ a` (the round-trip returns the source type, and the replacement is the extracted focus); PG needs `t ~ s` (the re-split consumes a source) and `b ~ a`; PP needs `t ~ s` only (the re-split of a plug output requires the source type; `b1` and `b2` stay at the focus type). Where `t ≁ s` the interface remains usable — `splitF` decomposes any source, `plugF` rebuilds any target — but no round-trip is *statable*: no operation re-splits a target. The accountable content of that fragment is per-instance: the decomposition equation (each instance's `splitF f s` definition) and the rebuild equation (`plugF f c b` definition), plus composition typing — `composeF` residuals carry the polymorphism through. Witnesses: `prop_tc_fstF_*` and `prop_tc_sndF_*` (product components at `s ≠ t`, `a ≠ b`) and `prop_tc_composed` (a two-stage chain changing both).

**Optional fragment (`FocusingO`).** A split may find no focus: on a hit, the
clauses are GP/PG/PP on the hit domain `{s | splitO f s = Just _}`; on a miss,
the observable behavior is fixed instead of derived — `overO f h s == s` for
every `h` (the whole is fixed: `overO` is mono in the whole type, since a miss
has no data to build a different target from). `composeO` short-circuits on the
first miss. This is distinct from the failure channel: absence carries no error
payload, and the miss laws need no success premise because the miss itself has
defined behavior. Witnesses: `prop_opt_*`.

## 4. Contracts

### 4.1 Totality policy

Safe constructors must not throw on their declared domains. Partiality is
permitted only as:

1. a **deferred `error`** — for checks that cannot run at construction time
   (`Focusing` has no failure channel); or
2. a **return channel** (`FocusingE`, `Focal.Partial`).

Every throw site is registered below and in `conformance.md`:

| Throw site | Domain | Behavior |
|---|---|---|
| `elementF`'s `splitF` | outside `0 <= n < length xs` | delayed `error` ("precondition violated") |
| `unsafeElementF`, construction | `n < 0` | immediate `error` |
| `unsafeElementF`'s `splitF` | `n >= length xs` | delayed `error` |
| `focusAt`'s `splitF` | path absent in the supplied tree (the construction tree is checked separately, returning `Nothing`) | delayed `error` |
| `genericFocus`'s `splitF` | a value whose parameter has no reachable direct occurrence | delayed `error` ("genericFocus: no reachable direct parameter occurrence") |

The registered `error` sites are kept unchanged; for new code the channel variant is the interface (`Focal.Partial`, `Focal.Effectful`; `Focal.List.elementE` for the list focus); the `focusAt` counterpart `focusAtE` is total at construction and reports the first missing path step in the return channel (`Left (PathError i)`) — no deferred `error`.

### 4.2 Input invariance

`splitF f s` may depend on `s` and on nothing else — not on external state, not
on a residual or focus captured at construction time.

**Exemption (must be named):** the snapshot constructor `fromZip` ignores its
argument by construction. It is exempt and is marked as such in
`conformance.md`. Consequences: for this instance GP holds only for the tree
the snapshot was taken from, and PG fails in general.

### 4.3 Claim discipline

Every guarantee-style statement in the README or in haddock must map to an
L0–L6 level and cite either a witness or an explicit not-enforced marker.
Claims that cannot be so mapped are defects, not documentation.

## 5. Representation ladder and caveats

Equivalent readings of `Focusing` (items 1–4), `FocusingE` (item 5), and `FocusingM` (item 6), each with its own premise:

1. **CPS closure.** Packing the residual as an existential is the CPS form:
   `∃C. P(C) ≅ ∀R. (∀C. P(C) → R) → R` — exposed as `mkFocal` / `withFocal`
   (shipped).
2. **Coend / co-Yoneda.** The existential pair of a decomposition and a rebuild
   is a coend:
   `∫^C Hom(S, A×C) × Hom(C×B, T) ≅ S → (A × (B → T))` — the `Focal` packaging
   is extensionally a Store; the residual is not recoverable from `Focal`.
3. **Van Laarhoven form.** For the mono lawful case, the same data is
   `≅ ∀F. Functor F ⇒ (A → F B) → S → F T`; the interpretation formula is
   `\k s -> fmap (plugF f c) (k a)` where `(a, c) = splitF f s`. This is what
   `overFM` implements (and `Focal.Interop.toVL`), and why only `Functor` is
   required.
4. **Extensional-only laws.** Laws stated on `Focal` (`L-NORM`, `L-TVL`) hold
   only extensionally, because of item 1.
5. **Either reading (failure channel).** With failures in return values, a
   `FocusingE e c s t a b` is characterized extensionally as
   `S → E + (A × (B → E + T))` — the Kleisli pair of `splitE`/`plugE` modulo
   residual change-of-representation. Component-wise currying as in item 2
   fails at `E + (A×C)` (no distributivity); the canonical residual is
   `B → E + T`. Residuals are not recoverable and laws do not transport
   (item 4 applies unchanged). Rank: the `Focal.Partial` exports are rank ≤ 1;
   a nominal `FocalE` seal, if added, costs exactly one rank-2 eliminator
   (the item-1 sealing induction).
6. **Effectful reading.** For any functor `m`, the `FocusingM` coend
   `∫^C Hom(S, m(A×C)) × Hom(C, B→mT)` collapses unconditionally to
   `Hom(S, m(A×(B→mT)))` (Yoneda reduction in the second variable; no
   distributivity or commutativity premises) — the Store form is
   `s -> m (a, b -> m t)` with canonical residual `b -> m t`. Residuals are
   not recoverable and laws do not transport (item 4 applies unchanged).
   Rank: every `Focal.Effectful` export is rank ≤ 1 (no new quantifiers).

Caveats:

- **An existential in Haskell is not a quotient.** Distinct residual
  representations with equal behavior are not identified; equations on `Focal`
  are extensional.
- **Parametricity assumptions.** The isomorphisms above hold for the total,
  parametric fragment. Bottom, `seq`, and `unsafeCoerce` can break the
  implication from representation to behavior — the known limitation of
  Van Laarhoven-style representations.
- References: Jaskelioff & O'Connor, *A representation theorem for second-order
  functionals*, JFP 2015, [doi:10.1017/S0956796815000088](https://doi.org/10.1017/S0956796815000088);
  McBride, *Clowns to the Left of Me, Jokers to the Right*, POPL '08;
  Huet, *Functional Pearl: The Zipper*, JFP 1997.

**Residual representation-equivalence rules.** Two residuals of the same
instance are *putback-equivalent* when they rebuild identically:

@
c1 ~ c2  ⇔  ∀ b. plugF f c1 b == plugF f c2 b
@

Putback-equivalence is the residual identity the law layer uses between
*independently chosen* residuals — residuals are functions into the target, and
function equality is not decidable in Haskell, so no general residual *value*
comparison is sound. Beyond it, the laws fix only the library's own definitional
pairing conventions — the product `(c1, c2)`, the unit `()`, and the
reassociation `((c1,c2),c3) ≅ (c1,(c2,c3))` that `L-ASSOC` and `L-UNIT` are
stated modulo — never the identity of an arbitrary residual representation.
Two residuals may be
putback-equivalent while carrying different geometry (position, provenance,
debug information): *residual as geometry* and *residual as putback function*
are distinct, and the second is the quotient by `~`. Re-representations
(`normalize`, `toStoreLike`, the Van Laarhoven conversions) may discard residual
structure exactly up to `~`; their accounting is extensional (`L-NORM`,
`L-TVL`), and any law that needs residual identity rather than putback behavior
must be stated on `Focusing`. Boundary (registered gap): there is no total
residual minimization — `normalize` canonicalizes extensional behavior, it does
not minimize, and the undecidability of function equality is why.

## 6. Defect log

"Before" paraphrases the old wording instead of quoting it, so that the retired
phrases do not survive anywhere in this repository (see the audit note below).

| ID | Where | Before | After |
|---|---|---|---|
| D1 | README, former axiom chapter | The A1–A6 list was presented as a set of axioms, mixing one (unstated) axiom with definitional identities, instance obligations, and a corollary | README "Law status" + §1 here: A-LENS is the only axiom; the rest is classified L0–L6 |
| D2 | README axiom-status column | A1/A2/A4/A6 were marked as structurally enforced although the constructor is public and `plugF` receives no `s` | "Enforced by" columns state assumption + per-instance witnesses (§2) |
| D3 | README "What's in scope", item 1 | Asserted both functions to be total and deterministic | "Total on their declared domains"; partiality policy §4.1 + conformance registry |
| D4 | README, old axiom chapter opening | Called the interface lawful without stating any law | "Interface with explicit law obligations": obligations enumerated as law-ids (§3) |
| D5 | README, Lens-like section | Claimed a general interop surface with `lens`/`optics`, including conversions that are not shipped | Limited to the shipped `toStoreLike` projection; `toVL`/`fromVL` ship in `Focal.Interop` — extensional only (§5) |
| D6 | README boundary sentence, demo comment, `overFM` haddock | Framed the bridge as monadic, implying a `Monad` requirement | Functor-level wording: only `Functor` is required; Van Laarhoven interpretation formula |
| D7 | README, A5 row | Locality was listed as an axiom with test coverage | L0 structure fact (signature-level); no law or witness claimed (conformance) |
| D8 | README quick start + `fromZip` haddock | Snapshot builders were presented as general path focus; the demo comment did not match the operation | Snapshot semantics documented (input-invariance exemption §4.2); demo comment matches `(*10)` |
| D9 | `Focal.Core`, `overFM` haddock | Contained a typo in the phrase describing effect externalization and assigned sequencing to `Monad` | Rewritten paragraph (typo removed; `Functor` only) |
| D10 | `test/Spec.hs`, headers | Group titles asserted an "Axiom 1–6" scheme, and a comment claimed residuals cannot be forged | Law-id group titles; the forgery claim replaced by a conformance pointer |
| D11 | README, coverage summary | Implied the property suite covered each listed axiom, including a residual-legality claim | Honest statement: property count kept; per-law witnesses and classification in conformance |
| D12 | README, specialization tables | Rows needing extended rungs were listed alongside core-supportable ones; the zipper row lacked the snapshot note | Table footnotes: extended rungs (`FocusingE`/`FocusingM`); snapshot semantics |
| D13 | README, related work | Claimed strong representation results while omitting the representation-theorem references | Jaskelioff–O'Connor 2015 and the coend/co-Yoneda reference added (§5) |

Audit: no file under `README.md`, `ROADMAP.md`, `src/`, `test/`, or `docs/`
contains the retired phrases paraphrased in the "Before" column.
