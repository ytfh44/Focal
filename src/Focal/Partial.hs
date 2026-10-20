-- | Failure-channel companion of 'Focal.Core.Focusing': failures travel in
--   @Either e@ return values instead of deferred errors.
--
--   Composition is ordered — 'splitE' runs outer to inner, 'plugE' inner to
--   outer, and the first 'Left' short-circuits. Laws carry the success
--   premise **and** the residual premise @c ∈ R(f)@ (docs/foundation.md §3).
module Focal.Partial
  ( FocusingE(..)
  , idE
  , composeE
  , overE
  , toPartial
  , toStoreE
  , fromStoreE
  ) where

import Focal.Core (Focusing(..))

-- | A focus whose decomposition and rebuild may fail with @e@.
data FocusingE e c s t a b = FocusingE
  { splitE :: s -> Either e (a, c)
  , plugE  :: c -> b -> Either e t
  }

-- | Identity focus in the failure channel.
--
--   >>> overE (idE :: FocusingE String () Int Int Int Int) (+1) (41 :: Int)
--   Right 42
idE :: FocusingE e () s s s s
idE = FocusingE
  { splitE = \s -> Right (s, ())
  , plugE  = \() b -> Right b
  }

-- | Sequential composition: split outer then inner, plug inner then outer;
--   the first 'Left' short-circuits. Residuals pair up as @(c1, c2)@.
composeE
  :: FocusingE e c1 s t a b
  -> FocusingE e c2 a b x y
  -> FocusingE e (c1, c2) s t x y
composeE p q = FocusingE split plug
  where
    split s = do
      (a, c1) <- splitE p s
      (x, c2) <- splitE q a
      pure (x, (c1, c2))
    plug (c1, c2) y = do
      t' <- plugE q c2 y
      plugE p c1 t'

-- | Apply a pure function to the focus, rebuilding through the channel.
overE :: FocusingE e c s t a b -> (a -> b) -> s -> Either e t
overE p h s = do
  (a, c) <- splitE p s
  plugE p c (h a)

-- | Embed a pure 'Focusing'; every outcome becomes 'Right'.
toPartial :: Focusing c s t a b -> FocusingE e c s t a b
toPartial p = FocusingE
  { splitE = \s -> Right (splitF p s)
  , plugE  = \c b -> Right (plugF p c b)
  }

-- | Partial Store projection: the residual is closed over 'plugE'.
toStoreE :: FocusingE e c s t a b -> s -> Either e (a, b -> Either e t)
toStoreE p s = fmap (\(a, c) -> (a, plugE p c)) (splitE p s)

-- | Canonical representative of the partial Store reading.
--
--   >>> overE (fromStoreE (toStoreE (idE :: FocusingE String () Int Int Int Int))) (+1) (41 :: Int)
--   Right 42
fromStoreE
  :: (s -> Either e (a, b -> Either e t))
  -> FocusingE e (b -> Either e t) s t a b
fromStoreE h = FocusingE
  { splitE = h
  , plugE  = \k b -> k b
  }
