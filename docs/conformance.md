# Focal — Conformance Matrix

Per-instance verdicts against the law vocabulary in
[`foundation.md`](foundation.md) §3, for the `0.1.0.0` working tree
(2026-10-15). Witnesses refer to [`../test/Spec.hs`](../test/Spec.hs).

Legend: **✓** holds on the declared domain · **✗** fails · **cnd** conditional
on the obligation the instance embeds · **def** holds by definition
(non-empirical) · **N/A** not well-formed for this instance's shape · **—**
not an instance (projection).

| Instance | L-GP | L-PG | L-PP | L-OVF | Input invariance | Domain & failure modes | Witnesses | Notes |
|---|---|---|---|---|---|---|---|---|
| `idF` | def | def | def | def | ✓ | total; no failure mode | `prop_a1_idF`, `prop_a2_idF`, `prop_a3_idChain` | definitional — no empirical content |
| `fstF`, `sndF` | ✓ | ✓ | ✓ | ✓ | ✓ | total; no failure mode | `prop_a1_fstF`, `prop_a1_sndF`, `prop_a3_tupleChain`, `prop_a4_leftId_fst`, `prop_a4_rightId_fst`, `prop_fstF_update`, `prop_sndF_update`, `prop_concrete_tuple` | type-changing shapes: GP/PG/PP N/A (foundation §2) |
| `pureF`, `fromLensLike` | cnd | cnd | cnd | cnd | ✓ | inherited from the embedded `view`/`set` | `prop_a1_pureF` (identity lens — no discriminating power) | lawful iff the embedded pair is; non-trivial instance + counterexample scheduled (ROADMAP 0b); L-OVF needs the pair's put-get/put-put |
| `elementF` | ✓ | ✓ | ✓ | ✓ | ✓ | declared domain `0 <= n < length xs`; outside it, delayed `error` from `splitF` | `prop_listElement_negative` | construction-time full check (`elementAt`) scheduled (ROADMAP 0c) |
| `unsafeElementF` | ✓ | ✓ | ✓ | ✓ | ✓ | `0 <= n`; immediate `error` for `n < 0`; delayed `error` for `n >= length xs` | 15 properties — all list-family checks, incl. `prop_xd_sameFocus_overwrite` (the L-OVF instance) | in-domain behavior identical to `elementF` |
| `fromZip` | ✓\* | ✗ | ✓† | ✗ | ✗ (exempt) | total; no failure mode | `prop_a1_roseZip`, `prop_a1_binZip`, `prop_a2_rose_depends`, `prop_a4_leftId_zipper`, `prop_a4_rightId_zipper`, `prop_a6_rose`, `prop_a6_binTree`, `prop_xb_fromZip_roundtrip`, `prop_xb_multilevel` | **snapshot constructor** (foundation §4.2): `splitF` ignores its argument |
| `safeFocusAt` | ✓\* | ✗ | ✓† | ✗ | ✗ (exempt) | path validated once against the supplied tree; `Nothing`, never a throw | `prop_xb_safeFocusAt_valid`, `prop_xb_safeFocusAt_invalid` | snapshot; `Nothing` covers only the path check against `t`; retire-vs-rename decided in ROADMAP 0d |
| `unsafeFocusAt` | ✓\* | ✗ | ✓† | ✗ | ✗ (exempt) | invalid path ⇒ immediate `error` | (none — registered gap) | snapshot; naming defect registered → ROADMAP 0d |
| `overFM`, `toStoreLike` | — | — | — | — | — | `overFM`: Functor-level, no law beyond the functor laws; `toStoreLike`: projection | `prop_a5_overFM_pure` (definitional) | L-NORM / L-TVL gaps → ROADMAP 0e |
| `Focal` | N/A | N/A | N/A | N/A | — | no exported operations tested | (none — registered gap) | residual hidden; ladder + `mkFocal`/`withFocal` scheduled (ROADMAP 0e) |

Verdict footnotes:

- **✓\*** — GP holds only for the source the snapshot was built from (that is
  the tree `plugF` rebuilds). For any other source the round-trip fails; the
  shipped tests apply snapshots only to their own tree.
- **✓†** — PP is vacuous for snapshots: `splitF` is constant, so `c'` is always
  the captured stack and the equation holds by construction. It is not evidence
  of overwrite behavior on arbitrary sources.
- `fromZip`'s PG fails in general: `plugF` produces `rebuild b c`, and
  re-splitting that value returns the captured focus, not `b`.
- `fromZip`'s L-OVF fails for the same reason: after one edit, the re-split
  focus is the captured one, so a second edit ignores the first.

## Coverage honesty

Reviewed property-by-property against the working tree:

- **L-PG: 0 of 43.** No property asserts the retrieve clause directly.
- **L-PP: 0 of 43.** No property asserts the re-derived-residual equation
  directly.
- **L-OVF: 1 of 43** — `prop_xd_sameFocus_overwrite`, narrow: one instance
  (`unsafeElementF` on lists) and a fixed function pair `(+1) ∘ (*2)`
  (verified against code). It evaluates through a re-split and a re-plug, and
  separates the PP-violating model E3 (foundation §2), but its statement is the
  L-OVF equation — not PG or PP.
- **L-GP: 12 of 43** — `prop_a1_*` (8), `prop_a2_*` (3), and
  `prop_xb_fromZip_roundtrip` (1).
- **L-ASSOC: 3 of 43**; **L-UNIT: 6 of 43**.
- The remaining 21 properties: 1 definitional re-check (`prop_a3_plugLaw`),
  1 definitional smoke (`prop_a5_overFM_pure`), 3 occurrence≠value corollaries,
  2 zipper round-trips, 2 zipper navigation tests, 3 remaining XB navigation
  tests, 2 remaining XD edit-survival tests, 2 concrete regressions, 5
  list/tuple update regressions.

Entries that overstate what they assert (rewrite scheduled in ROADMAP 0b):

- `prop_a2_list_depends` and `prop_a2_rose_depends`: names mention residual
  dependence; bodies re-assert L-GP.
- `prop_a2_idF`: L-GP restatement (round-trip on a shifted source).
- `prop_xb_fromZip_roundtrip`: third restatement of L-GP for the snapshot
  family.
