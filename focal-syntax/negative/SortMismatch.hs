{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

-- | Deliberate sort mismatch: this module must NOT type-check.
--
--   It is listed in no build target. The registered negative witness runs it
--   through @ghc -fno-code@ and expects a sort-mismatch error (@U@ against
--   @U :-> U@).
module SortMismatch where

import Focal.Syntax
import Focal.Syntax.Stack

bad :: Tm U
bad = plugStack (Hole :: Stack U U) (exConst :: Tm (U :-> U))
