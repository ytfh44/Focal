-- | Focal: Explicit-residual focus library.
--
--   Focal unifies Lens, Zipper, and evaluation contexts under a common
--   "explicit residual focus" abstraction. The key insight: a focus is
--   never alone — it always comes with a residual context that records
--   how to rebuild the whole from a replacement focus.
--
--   Module overview:
--
--   * "Focal.Core"  — 'Focusing', 'Focal', composition, application
--   * "Focal.Tuple" — 'fstF', 'sndF'
--   * "Focal.List"  — 'elementF', 'unsafeElementF'
--   * "Focal.Zipper" — 'ZipTree', 'Zip', navigation, tree instances
module Lib
  ( module Focal.Core
  , module Focal.Tuple
  , module Focal.List
  , module Focal.Zipper
  ) where

import Focal.Core
import Focal.Tuple
import Focal.List
import Focal.Zipper