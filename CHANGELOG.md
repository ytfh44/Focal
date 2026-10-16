# Changelog for `Focal`

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to the
[Haskell Package Versioning Policy](https://pvp.haskell.org/).

## Unreleased

- Documentation layer revision: added `docs/foundation.md` (axiom A-LENS, L0–L6
  hierarchy, law vocabulary, contracts, representation ladder, defect log) and
  `docs/conformance.md` (instance × law matrix); reworked the README law
  chapter; rewrote the roadmap around law-id-tagged acceptance criteria; and
  corrected haddock/contract wording in `Focal.Core`, `Focal.List`, and
  `Focal.Zipper`. No behavior changes.

- P0 execution (ROADMAP 0b–0e, 0g): added `elementAt` (construction-time checked
  list focus); added dynamic `focusAt` and retired `safeFocusAt`/`unsafeFocusAt`;
  hid the `Focal` constructor behind `mkFocal`/`withFocal`; added
  `Focal.Interop` (`VLens`, `PStore`, `reifyVL`, `toVL`, `fromVL`, `normalize`);
  rewrote the test suite as 64 law-id-tagged properties (L-PG/L-PP/L-OVF
  witnesses added); added a doctest test-suite gate and a minimal CI workflow;
  aligned docs, README, and roadmap. Breaking API: `Focal(..)` is now `Focal` +
  `mkFocal`/`withFocal`; `safeFocusAt`/`unsafeFocusAt` removed; `base` bound
  raised to `>= 4.16`.

- Added `Focal.Partial` (`FocusingE`, `idE`, `composeE`, `overE`, `toPartial`,
  `toStoreE`, `fromStoreE`): failures in `Either` return values, ordered
  composition, success-premise laws, partial Store reading. Test suite: 78
  law-id-tagged properties.

- Added `elementE` (`Focal.List.ListError`: `NegativeIndex`/`PastEnd`): the
  failure-channel list focus (per-call index check; total plug). Suite at 85
  properties; docs counts updated.

- Added `Focal.Effectful` (`FocusingM`, `idM`, `composeM`, `overM`,
  `toEffectful`, `toEffectfulE`, `storeM`, `fromStoreM`): both legs in a monad
  (failure, validation, logging, state); GP/PG as Kleisli equations, preserved
  by composition for every monad; PP per instance. Test suite: 136
  law-id-tagged properties.

- Tightened the effectful PP statement to the replay-prefix equation (the
  first write is shared, so failures short-circuit together and no success
  premise is needed); discriminators extended (logging and sign-flipping
  residuals fail it; the prefix-less strengthening stays pinned as false).
  Law tables now count the effectful witnesses: 136 properties; the module
  haddock and README phrasing use the replay-prefix wording.

- Added residual-shape helpers (`Residual2`, `Residual3`, `flatten`, `unflatten`,
  `prettyResidual`, `prettyResidual3`) to `Focal.Core`: canonical right-nested
  residual pairs, mutually-inverse reassociation, and debug renderings. Suite at
  136 properties.

- Stated the type-changing clause forms in `docs/foundation.md` §3 (per-clause
  side conditions; no round-trip is statable when `t ≁ s`) with witnesses for
  product components at changed types and a two-stage composed chain
  (`prop_tc_*`). Suite at 136 properties.

- Added `focusAtE` (`PathError`, `Focal.Zipper`): the failure-channel dynamic
  path focus — construction is total, `splitE` re-navigates per call and
  reports the first missing step as `Left (PathError i)`, `plugE` is total.
  Suite at 136 properties.

- Added the navigation algebra to `Focal.Zipper`: `childOf` (frames record
  their selector), `pathOf` (context stack to root-first path), `framesAt`
  (path to context stack), `lcaPath` (longest common path prefix) — with
  round-trip, composition, LCA prefix/maximality, and `childOf`/`descend`-inverse
  witnesses. Suite at 136 properties.

- Stated the residual representation-equivalence rules in `docs/foundation.md`
  §5: putback-equivalence as the law-layer residual identity, the
  geometry-vs-putback-function distinction, the admissible-discard rules for
  re-representation, and the registered boundary that no total residual
  minimization exists (function equality is undecidable).

- Added `Focal.Generic` (`Derivative1`, `Ctx1`, `genericSplit1`, `genericPlug1`,
  `genericFocus`): one-hole contexts of the leftmost direct type-parameter
  occurrence, derived from `Generic1` representations; `Rose` migrated with
  GP/PG/PP witnesses. Suite at 136 properties.

- Added `Focal.Optional` (`FocusingO`, `idO`, `composeO`, `overO`,
  `toOptional`): zero-or-one foci where a miss is absence with pass-through
  update — distinct from the failure channel; hit-domain GP/PG/PP plus miss,
  short-circuit, and composition witnesses. Suite at 136 properties.

## 0.1.0.0 - YYYY-MM-DD

