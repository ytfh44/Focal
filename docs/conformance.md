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
| `Focal.Effectful` (`FocusingM`, `composeM`, `overM`, `storeM`) | — | — | — | — | — | GP/PG as Kleisli equations (PG in continuation form); PP as the replay-prefix equation, per instance (foundation §3) | `prop_lgpM_*`, `prop_lpgM_*`, `prop_lppM_*`, `prop_compM_*`, `prop_lunitM_*`, `prop_lassocM_*`, `prop_storeM_*`, `prop_embM*`, `prop_discM_*` | GP/PG composition closure holds for every monad; `prop_discM_*` pins the forced premises |
| `Focal.Generic` (`Derivative1`, `Ctx1`, `genericSplit1`, `genericPlug1`, `genericFocus`) | — | — | — | — | — | direct occurrences only (leftmost); a value whose parameter has no reachable direct occurrence is outside the declared domain — `genericSplit1` returns `Nothing`, `splitF` raises the registered delayed `error` (foundation §4.1) | `prop_gen_split_plug`, `prop_gen_rose_gp`, `prop_gen_rose_pg`, `prop_gen_rose_pp` | one-hole contexts derived from `Generic1`; `Rose` migrated (root label) |

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

Reviewed property-by-property against the working tree (**130 properties**,
plus the doctest suite):

- **L-GP: 15 of 130** (`prop_lgp_*` 8, partial `prop_lgpE_*` 3, effectful `prop_lgpM_*` 4).
- **L-PG: 13 of 130** (`prop_lpg_*` 7, partial `prop_lpgE_*` 2, effectful `prop_lpgM_*` 4).
- **L-PP: 9 of 130** (`prop_lpp_*` 5, partial `prop_lppE_*` 2, effectful `prop_lppM_*` 2;
  one trivially-satisfied snapshot case, `prop_lpp_fromZip`).
- **L-OVF: 5 of 130** (`prop_lovf_*` — four instances plus the partial
  success-prefix case).
- **L-ASSOC: 3 of 130** (`prop_lassoc_*`); **L-UNIT: 6 of 130** (`prop_lunit_*`).
- **L-NORM: 2 of 130** (`prop_lnorm_*`); **L-TVL: 2 of 130** (`prop_ltvl_*`).
- **Partial channel: 6 of 130** (`prop_scE_*`, `prop_embE_compose`,
  `prop_storeE_roundtrip`, `prop_discE_*`).
- **`elementE` contract: 7 of 130** (`prop_elementE_*`).
- **Effectful rung (non-law): 12 of 130** (`prop_compM_*`, `prop_lunitM_*`,
  `prop_lassocM_*`, `prop_storeM_*`, `prop_embM*`, `prop_discM_*`).
- **Residual shape: 2 of 130** (`prop_flatten_inverse`, `prop_unflatten_inverse`).
- **Type-changing fragment: 5 of 130** (`prop_tc_*`).
- **`focusAtE` contract: 5 of 130** (`prop_focusatE_*`).
- **Navigation algebra: 7 of 130** (`prop_nav_*`).
- **Generic derivation: 4 of 130** (`prop_gen_*`).
- The remaining 27 properties: 3 occurrence≠value corollaries, 5 zipper
  law/navigation tests, 2 snapshot contracts (`prop_contract_zip_*`),
  2 law discriminators (`prop_disc_*`), 8 `focusAt` tests, 3 `elementAt` tests,
  2 concrete regressions, 1 `elementF` contract test, 1 edit-independence
  observation.
