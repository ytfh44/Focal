{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

-- | Generic one-hole contexts, derived from 'Generic1' representations.
--
--   The mechanism is the dissection derivative of a representable functor:
--   @Ctx1 (Rep1 f)@ is the one-hole context of the leftmost /direct/
--   occurrence of the type parameter — an occurrence represented by 'Par1',
--   not one sitting under another functor. The structural instances walk the
--   representation: metadata wrappers ('M1') delegate through; sums ('(:+:)')
--   delegate to the live side, tagged with @L1@ or @R1@; products ('(:*:)')
--   are left-biased, the context recording which side holds the hole.
--   Constants ('K1'), 'U1', 'V1', recursive children ('Rec1'), and parameters
--   under another functor ('(:.:)') have no direct occurrence: their context
--   type is 'V1' and 'split1' is 'Nothing'.
--
--   Boundary: only /direct/ occurrences of the parameter are reachable here.
--   A hole inside a recursive child ('Rec1') is the zipper's frame-stack
--   territory (see "Focal.Zipper"), not a direct occurrence; a datatype whose
--   parameter occurs only under other functors has no generic hole here.
module Focal.Generic
  ( Derivative1(..)
  , genericSplit1
  , genericPlug1
  , genericFocus
  ) where

import Data.Kind (Type)
import GHC.Generics
  ( Generic1(..)
  , K1
  , M1(..)
  , Par1(..)
  , Rec1
  , U1(..)
  , V1
  , (:+:)(..)
  , (:*:)(..)
  , (:.:)
  )

import Focal.Core (Focusing(..))

-- | A functor whose generic representation has a derivative at the leftmost
--   direct occurrence of its parameter.
--
--   'Ctx1' is the one-hole context of that occurrence: 'split1' decomposes a
--   value into the hole and its context, and 'plug1' rebuilds from the two.
--   'split1' returns 'Nothing' exactly when the value has no direct parameter
--   occurrence; instances with no direct occurrence use 'V1' as their context
--   type, so no context value ever exists to plug.
--
--   Laws, on contexts reachable from 'split1':
--
--   * GP: if @'split1' s == 'Just' (x, c)@ then @'plug1' c x == s@;
--   * PG: @'split1' ('plug1' c x) == 'Just' (x, c)@.
--
--   'Ctx1' is a total type: for a shape with a second direct occurrence of
--   the parameter the 'R1' branch is inhabited but not producible by
--   'split1', so PG is stated on the image.
class Derivative1 (f :: Type -> Type) where
  -- | One-hole context of the leftmost direct parameter occurrence.
  type Ctx1 f :: Type -> Type

  -- | Decompose into the leftmost direct parameter occurrence and its
  --   context, or 'Nothing' when the parameter does not occur directly.
  split1 :: f x -> Maybe (x, Ctx1 f x)

  -- | Rebuild from a context and a replacement for the hole.
  plug1 :: Ctx1 f x -> x -> f x

-- | Metadata wrappers delegate to what they wrap, mapping the wrapper over
--   the context.
instance Derivative1 f => Derivative1 (M1 i c f) where
  type Ctx1 (M1 i c f) = M1 i c (Ctx1 f)
  split1 (M1 x) = case split1 x of
    Just (hole, ctx) -> Just (hole, M1 ctx)
    Nothing          -> Nothing
  plug1 (M1 ctx) x = M1 (plug1 ctx x)

-- | The parameter itself: the hole is the value, the context is trivial.
instance Derivative1 Par1 where
  type Ctx1 Par1 = U1
  split1 (Par1 x) = Just (x, U1)
  plug1 U1 x = Par1 x

-- | A constant carries no parameter occurrence.
instance Derivative1 (K1 i c) where
  type Ctx1 (K1 i c) = V1
  split1 _ = Nothing
  plug1 v _ = case v of {}

-- | The nullary representation has no field to decompose.
instance Derivative1 U1 where
  type Ctx1 U1 = V1
  split1 _ = Nothing
  plug1 v _ = case v of {}

-- | The empty representation has no value to decompose (and no context to
--   plug into).
instance Derivative1 V1 where
  type Ctx1 V1 = V1
  split1 _ = Nothing
  plug1 v _ = case v of {}

-- | A recursive child is not a direct occurrence: its holes belong to the
--   zipper's frames.
instance Derivative1 (Rec1 f) where
  type Ctx1 (Rec1 f) = V1
  split1 _ = Nothing
  plug1 v _ = case v of {}

-- | A composition puts the parameter under another functor: not a direct
--   occurrence, so there is nothing to decompose.
instance Derivative1 (f :.: g) where
  type Ctx1 (f :.: g) = V1
  split1 _ = Nothing
  plug1 v _ = case v of {}

-- | Sums delegate to the side the value lives in; the context is tagged with
--   @L1@ or @R1@ so that plugging dispatches back.
instance (Derivative1 f, Derivative1 g) => Derivative1 (f :+: g) where
  type Ctx1 (f :+: g) = Ctx1 f :+: Ctx1 g
  split1 (L1 x) = case split1 x of
    Just (hole, ctx) -> Just (hole, L1 ctx)
    Nothing          -> Nothing
  split1 (R1 x) = case split1 x of
    Just (hole, ctx) -> Just (hole, R1 ctx)
    Nothing          -> Nothing
  plug1 (L1 ctx) x = L1 (plug1 ctx x)
  plug1 (R1 ctx) x = R1 (plug1 ctx x)

-- | Products are left-biased: the hole is the leftmost direct occurrence, so
--   the left side wins when it has one and the right side is tried otherwise.
--   The context records which side holds the hole; plugging dispatches on it.
instance (Derivative1 f, Derivative1 g) => Derivative1 (f :*: g) where
  type Ctx1 (f :*: g) = (Ctx1 f :*: g) :+: (f :*: Ctx1 g)
  split1 (l :*: r) = case split1 l of
    Just (hole, ctx) -> Just (hole, L1 (ctx :*: r))
    Nothing          -> case split1 r of
      Just (hole, ctx) -> Just (hole, R1 (l :*: ctx))
      Nothing          -> Nothing
  plug1 (L1 (ctx :*: r)) x = plug1 ctx x :*: r
  plug1 (R1 (l :*: ctx)) x = l :*: plug1 ctx x

-- | Decompose a 'Generic1' value at its leftmost direct parameter occurrence.
--
--   >>> :set -XDeriveGeneric
--   >>> import GHC.Generics (Generic1)
--   >>> data P a = P Int a deriving (Generic1, Show)
--   >>> fmap fst (genericSplit1 (P 3 'x'))
--   Just 'x'
--   >>> fmap (\(x, c) -> genericPlug1 c x) (genericSplit1 (P 3 'x')) :: Maybe (P Char)
--   Just (P 3 'x')
--   >>> import Focal.Core (overF)
--   >>> overF genericFocus succ (P 3 'x')
--   P 3 'y'
genericSplit1
  :: (Generic1 f, Derivative1 (Rep1 f))
  => f x
  -> Maybe (x, Ctx1 (Rep1 f) x)
genericSplit1 = split1 . from1

-- | Rebuild a 'Generic1' value from a context and a hole produced by
--   'genericSplit1'.
genericPlug1
  :: (Generic1 f, Derivative1 (Rep1 f))
  => Ctx1 (Rep1 f) x
  -> x
  -> f x
genericPlug1 ctx = to1 . plug1 ctx

-- | The generic focus at the leftmost direct parameter occurrence.
--
--   'splitF' uses 'genericSplit1'. A value whose parameter occurs only
--   indirectly (or not at all) is outside the declared domain, and 'splitF'
--   then raises a delayed 'error' — the library's convention for declared
--   domains. 'plugF' rebuilds through 'genericPlug1'.
genericFocus
  :: (Generic1 f, Derivative1 (Rep1 f))
  => Focusing (Ctx1 (Rep1 f) a) (f a) (f a) a a
genericFocus = Focusing
  { splitF = \s -> case genericSplit1 s of
      Just (hole, ctx) -> (hole, ctx)
      Nothing          ->
        error "genericFocus: no reachable direct parameter occurrence"
  , plugF = genericPlug1
  }
