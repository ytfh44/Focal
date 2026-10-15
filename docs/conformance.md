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
| `idF` | def | def | def | def | ✓ | total; no failure mode | `prop_lgp_idF`, `prop_lassoc_idChain`, `prop_lunit_*` | definitional — no empirical content |
| `fstF`, `sndF` | ✓ | ✓ | ✓ | ✓ | ✓ | total; no failure mode | `prop_lgp_fstF`, `prop_lgp_sndF`, `prop_lpg_fstF`, `prop_lpg_sndF`, `prop_lpp_fstF`, `prop_lovf_fstF`, `prop_lovf_sndF`, `prop_lassoc_tupleChain`, `prop_lunit_left_fst`, `prop_lunit_right_fst`, `prop_concrete_tuple` | type-changing shapes: GP/PG/PP N/A (foundation §2) |
| `pureF`, `fromLensLike` | cnd | cnd | cnd | cnd | ✓ | inherited from the embedded `view`/`set` | `prop_lgp_pureF`, `prop_lpg_userLens`, `prop_lpp_userLens` | lawful iff the embedded pair is; non-trivial lawful instance (`userLens`) and unlawful counterexamples (`prop_disc_*`) tested; L-OVF needs the pair's put-get/put-put |
| `elementF` | ✓ | ✓ | ✓ | ✓ | ✓ | declared domain `0 <= n < length xs`; outside it, delayed `error` from `splitF` | `prop_lgp_list`, `prop_lpg_elementF`, `prop_lpp_list`, `prop_lovf_list`, `prop_elementf_negative` | construction-time full check is `elementAt` |
| `unsafeElementF` | ✓ | ✓ | ✓ | ✓ | ✓ | `0 <= n`; immediate `error` for `n < 0`; delayed `error` for `n >= length xs` | `prop_lgp_list`, `prop_lpg_unsafeElementF`, `prop_lpp_list`, `prop_lovf_list`, `prop_lovf_composed`, `prop_concrete_list` | in-domain behavior identical to `elementF` |
| `fromZip` | ✓\* | ✗ | ✓† | ✗ | ✗ (exempt) | total; no failure mode | `prop_lgp_roseZip`, `prop_lgp_binZip`, `prop_lpp_fromZip`, `prop_lunit_left_zipper`, `prop_lunit_right_zipper`, `prop_occ_rose`, `prop_occ_binTree`, `prop_zip_multilevel`, `prop_contract_zip_ignoresInput`, `prop_contract_zip_pgCaptured` | **snapshot constructor** (foundation §4.2): `splitF` ignores its argument; snapshot contracts pinned by `prop_contract_zip_*` |
| `focusAt` | ✓ | ✓ | ✓ | ✓ | ✓ | declared domain: trees in which `path` exists; construction returns `Nothing` if the path is absent in the given tree; `splitF` on a later tree lacking the path raises a delayed `error` | `prop_focusat_*` | dynamic (input-invariant); path-validity premise per tree (foundation §2) |
| `elementAt` | ✓ | ✓ | ✓ | ✓ | ✓ | domain `0 <= n < length xs` of the construction list; `Nothing` otherwise; the returned `Focusing` keeps `elementF`'s delayed error off-domain | `prop_elementat_*` | checked construction-time variant of `elementF` |
| `overFM`, `toStoreLike` | — | — | — | — | — | `overFM`: Functor-level, no law beyond the functor laws; `toStoreLike`: projection | (none — no law claimed) | L-NORM / L-TVL are provided by `Focal.Interop` (shipped) |
| `Focal` | N/A | N/A | N/A | N/A | — | no exported operations tested directly; laws at the `Focal` level are extensional (foundation §5) | `prop_lnorm_*`, `prop_ltvl_*` | constructor hidden; `mkFocal`/`withFocal` + `Focal.Interop` shipped |
| `Focal.Interop` (`toVL`/`fromVL`/`normalize`) | — | — | — | — | — | rank-2 CPS via `mkFocal`/`withFocal`; extensional only (foundation §5) | `prop_lnorm_*`, `prop_ltvl_*` | conversions are extensional; residual not recoverable |

Verdict footnotes:

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

Reviewed property-by-property against the working tree (**64 properties**,
plus the doctest suite):

- **L-GP: 8 of 64** (`prop_lgp_*`).
- **L-PG: 7 of 64** (`prop_lpg_*`).
- **L-PP: 5 of 64** (`prop_lpp_*`; one trivially-satisfied snapshot case,
  `prop_lpp_fromZip`).
- **L-OVF: 4 of 64** (`prop_lovf_*` — four instances, arbitrary function pairs).
- **L-ASSOC: 3 of 64** (`prop_lassoc_*`); **L-UNIT: 6 of 64** (`prop_lunit_*`).
- **L-NORM: 2 of 64** (`prop_lnorm_*`); **L-TVL: 2 of 64** (`prop_ltvl_*`).
- The remaining 27 properties: 3 occurrence≠value corollaries, 5 zipper
  law/navigation tests, 2 snapshot contracts (`prop_contract_zip_*`),
  2 law discriminators (`prop_disc_*`), 8 `focusAt` tests, 3 `elementAt` tests,
  2 concrete regressions, 1 `elementF` contract test, 1 edit-independence
  observation.

Resolved in ROADMAP 0b: the `prop_a2_*` trio, `prop_a3_plugLaw`, and
`prop_xb_fromZip_roundtrip` were duplicate/definitional entries and no longer
exist.
