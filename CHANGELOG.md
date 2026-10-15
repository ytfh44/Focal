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
  by composition for every monad; PP per instance. Test suite: 105
  law-id-tagged properties.

## 0.1.0.0 - YYYY-MM-DD

