{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -fdefer-type-errors -Wno-deferred-type-errors #-}

-- | The negative witness, kept inside the test suite: @bad@ is ill-sorted
--   and must not type-check.  The module defers type errors, so @bad@ is
--   a thunk that raises when it is forced — which is what
--   'Focal.Syntax's @prop_neg_sortMismatch@ observes.  The deferred
--   warning is switched off here because the error it reports is the
--   whole point of the module (the property asserts the raise).
module Negative (bad) where

import Focal.Syntax
import Focal.Syntax.Stack

bad :: Tm U
bad = plugStack (Hole :: Stack U U) (exConst :: Tm (U :-> U))
