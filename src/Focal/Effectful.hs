-- | Effectful rebuild: the monadic rung of Focal.
--
--   @FocusingM m c s t a b@ carries both legs in a monad @m@ —
--   @splitM :: s -> m (a, c)@ and @plugM :: c -> b -> m t@ — unifying the
--   failure channel of 'Focal.Partial' (@m = Either e@), validation and
--   logging (@m = Writer@), and stateful reconstruction (@m = State@).
--
--   Composition is ordered — 'splitM' runs outer to inner, 'plugM' inner to
--   outer, and bind sequences the effects. Laws are Kleisli equations, read
--   on the success domain and carrying the residual premise @c ∈ R(f)@
--   (docs/foundation.md §3); PP holds per instance in the replay-prefix
--   form.
module Focal.Effectful
  ( FocusingM(..)
  , idM
  , composeM
  , overM
  , toEffectful
  , toEffectfulE
  , storeM
  , fromStoreM
  ) where

import Focal.Core (Focusing(..))
import Focal.Partial (FocusingE(..))

-- | A focus whose decomposition and rebuild both live in @m@.
data FocusingM m c s t a b = FocusingM
  { splitM :: s -> m (a, c)
  , plugM  :: c -> b -> m t
  }

-- | Identity focus.
--
--   >>> overM idM (+1) (41 :: Int) :: Maybe Int
--   Just 42
idM :: Monad m => FocusingM m () s s s s
idM = FocusingM
  { splitM = \s -> pure (s, ())
  , plugM  = \() b -> pure b
  }

-- | Sequential composition: split outer then inner, plug inner then outer;
--   effects are sequenced by the monad. Residuals pair up as @(c1, c2)@.
--
--   >>> import Focal.Core (Focusing)
--   >>> import Focal.Tuple (fstF)
--   >>> overM (composeM (toEffectful (fstF :: Focusing Bool (Int, Bool) (Int, Bool) Int Int)) idM) (+1) (41, True) :: Maybe (Int, Bool)
--   Just (42,True)
composeM
  :: Monad m
  => FocusingM m c1 s t a b
  -> FocusingM m c2 a b x y
  -> FocusingM m (c1, c2) s t x y
composeM p q = FocusingM split plug
  where
    split s = do
      (a, c1) <- splitM p s
      (x, c2) <- splitM q a
      pure (x, (c1, c2))
    plug (c1, c2) y = do
      u <- plugM q c2 y
      plugM p c1 u

-- | Apply a pure function to the focus, rebuilding through the monad.
overM :: Monad m => FocusingM m c s t a b -> (a -> b) -> s -> m t
overM p h s = do
  (a, c) <- splitM p s
  plugM p c (h a)

-- | Embed a pure 'Focusing'; every outcome becomes 'pure'.
toEffectful :: Monad m => Focusing c s t a b -> FocusingM m c s t a b
toEffectful p = FocusingM
  { splitM = \s -> pure (splitF p s)
  , plugM  = \c b -> pure (plugF p c b)
  }

-- | A 'FocusingE' is the @m = Either e@ case of 'FocusingM'.
--
--   >>> import Focal.List (elementE)
--   >>> overM (toEffectfulE (elementE 1)) (*10) [1,2,3]
--   Right [1,20,3]
toEffectfulE :: FocusingE e c s t a b -> FocusingM (Either e) c s t a b
toEffectfulE p = FocusingM
  { splitM = splitE p
  , plugM  = plugE p
  }

-- | Effectful Store projection: the residual is closed over 'plugM'.
storeM :: Monad m => FocusingM m c s t a b -> s -> m (a, b -> m t)
storeM p s = do
  (a, c) <- splitM p s
  pure (a, plugM p c)

-- | Canonical representative of the effectful Store reading
--   (@s -> m (a, b -> m t)@): the residual is @b -> m t@.
fromStoreM :: (s -> m (a, b -> m t)) -> FocusingM m (b -> m t) s t a b
fromStoreM h = FocusingM
  { splitM = h
  , plugM  = \k b -> k b
  }
