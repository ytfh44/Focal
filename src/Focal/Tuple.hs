-- | Tuple focus operations.
--   These are the simplest demonstrations of the Focal pattern:
--   the residual is the untouched tuple component.
module Focal.Tuple
  ( fstF
  , sndF
  ) where

import Focal.Core (Focusing(..))

-- | Focus on the first element of a pair.
--   The residual is the second element, preserved unchanged.
--
--   >>> overF fstF show (42 :: Int, "hi")
--   ("42","hi")
--
--   >>> overF fstF (*2) (3, "world")
--   (6,"world")
fstF :: Focusing b (a, b) (x, b) a x
fstF = Focusing
  { splitF = \(a, b) -> (a, b)
  , plugF  = \b x -> (x, b)
  }

-- | Focus on the second element of a pair.
--   The residual is the first element, preserved unchanged.
--
--   >>> overF sndF show ("hi", 42 :: Int)
--   ("hi","42")
--
--   >>> overF sndF (++"!") ("hello", "world")
--   ("hello","world!")
sndF :: Focusing a (a, b) (a, y) b y
sndF = Focusing
  { splitF = \(a, b) -> (b, a)
  , plugF  = \a y -> (a, y)
  }
