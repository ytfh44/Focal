-- | Zero-or-one focus: a miss is /absence/, not failure.
--
--   A @FocusingO c s t a b@ is the optional-cardinality rung of the same
--   explicit-residual idea as 'Focusing': @splitO@ either produces a focus and
--   its residual, or reports that there is nothing to focus on.
--
--   Laws.
--
--   * On the /hit domain/ @{s | splitO f s = Just _}@ the 'Focusing' laws hold
--     clause-for-clause: **GP** — if @splitO f s = Just (a, c)@ then
--     @plugO f c a = s@; **PG** — if @plugO f c b = t@ then
--     @splitO f t = Just (b, c\')@; **PP** — under the same premise,
--     @plugO f c\' b2 = plugO f c b2@ for all @b2@.
--   * On a /miss/ (@splitO f s = Nothing@), @overO f h s == s@ for every @h@:
--     the absence passes through unchanged.
--   * 'composeO' short-circuits on the first miss, and residuals pair up as
--     @(c1, c2)@ exactly as in 'Focal.Core.composeF'.
--
--   Distinction from @Focal.Partial@. There, a failure is an error that
--   travels in an @Either@ payload and the laws need explicit success
--   premises. Here, absence carries no payload and needs no premise: a miss
--   has a defined observable behaviour (pass-through), so the laws are total
--   as written above.
module Focal.Optional
  ( FocusingO(..)
  , idO
  , composeO
  , overO
  , toOptional
  ) where

import Focal.Core (Focusing(..))

-- | A focus that may or may not be present.
--
--   Type parameters are as for 'Focal.Core.Focusing'; @splitO@ returns
--   'Nothing' when the source has no focus to offer.
data FocusingO c s t a b = FocusingO
  { splitO :: s -> Maybe (a, c)
  , plugO  :: c -> b -> t
  }

-- | Identity focus: always a hit, residual unit.
--
--   >>> overO (idO :: FocusingO () Int Int Int Int) (+1) (41 :: Int)
--   42
idO :: FocusingO () s s s s
idO = FocusingO
  { splitO = \s -> Just (s, ())
  , plugO  = \() b -> b
  }

-- | Sequential composition: split outer then inner, plug inner then outer;
--   a miss at either stage is an overall miss. Residuals pair up as @(c1, c2)@
--   (mirroring 'Focal.Core.composeF').
composeO
  :: FocusingO c1 s t a b
  -> FocusingO c2 a b x y
  -> FocusingO (c1, c2) s t x y
composeO p q = FocusingO split plug
  where
    split s = do
      (a, c1) <- splitO p s
      (x, c2) <- splitO q a
      pure (x, (c1, c2))
    plug (c1, c2) y = plugO p c1 (plugO q c2 y)

-- | Apply a pure function to the focus. A hit rebuilds through 'plugO'; a miss
--   returns the source unchanged. The whole is fixed (@s@ on both sides): a
--   miss carries no data, so pass-through only has an identity to give when
--   the target equals the source.
--
--   >>> let splitHead xs = case xs of { (x:_) -> Just (x, xs); _ -> Nothing }
--   >>> let plugHead xs y = case xs of { (_:rest) -> y : rest; [] -> [] }
--   >>> let firstO = FocusingO splitHead plugHead
--   >>> overO firstO (+1) [1,2]
--   [2,2]
--   >>> overO firstO (+1) []
--   []
overO :: FocusingO c s s a b -> (a -> b) -> s -> s
overO p h s =
  case splitO p s of
    Nothing     -> s
    Just (a, c) -> plugO p c (h a)

-- | Embed a pure 'Focusing'; every source is a hit.
--
--   >>> import Focal.Tuple (fstF)
--   >>> overO (toOptional (fstF :: Focusing Bool (Int, Bool) (Int, Bool) Int Int)) (+1) (41, True)
--   (42,True)
toOptional :: Focusing c s t a b -> FocusingO c s t a b
toOptional p = FocusingO
  { splitO = \s -> Just (splitF p s)
  , plugO  = \c b -> plugF p c b
  }
