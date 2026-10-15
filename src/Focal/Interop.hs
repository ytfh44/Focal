{-# LANGUAGE RankNTypes #-}

-- | Interop between 'Focal' and other representations of a focus:
--
--   * 'VLens' — the Van Laarhoven form
--     (@forall f. Functor f => (a -> f b) -> s -> f t@);
--   * 'PStore' — the Store-shaped @(view, set)@ pair.
--
--   The isomorphisms behind these conversions, and their premises, are in
--   @docs/foundation.md@ §5; the laws are @L-NORM@ and @L-TVL@ in §3.
--   All conversions here are extensional: the residual is not recoverable,
--   and distinct residuals with equal behavior are not identified.
module Focal.Interop
  ( -- * Van Laarhoven form
    VLens
  , toVL
  , fromVL
    -- * Store-shaped view/set pair
  , PStore(..)
  , reifyVL
    -- * Canonical form
  , normalize
  ) where

import Data.Functor.Const (Const(..))
import Data.Functor.Identity (Identity(..))

import Focal.Core (Focal, Focusing(..), mkFocal, withFocal)

-- | Van Laarhoven form of a focus.
type VLens s t a b = forall f. Functor f => (a -> f b) -> s -> f t

-- | The Store-shaped (view, set) pair of a focus — the polymorphic
--   (s t a b)-parameterised reading of the Store characterization in
--   @docs/foundation.md@ §5 (ladder item 2).
data PStore s t a b = PStore
  { pview :: s -> a
  , pset  :: s -> b -> t
  }

-- | Reify a 'VLens' into its first-class Store representation.
reifyVL :: VLens s t a b -> PStore s t a b
reifyVL vl = PStore
  { pview = \s -> getConst (vl Const s)
  , pset  = \s b -> runIdentity (vl (const (Identity b)) s)
  }

-- | Interpret a 'Focal' in the Van Laarhoven form (the same interpretation
--   formula as 'Focal.Core.overFM').
toVL :: Focal s t a b -> VLens s t a b
toVL foc k s =
  withFocal foc $ \g ->
    let (a, c) = splitF g s
    in fmap (plugF g c) (k a)

-- | Build a 'Focal' from a 'VLens'. The residual is the original source
--   (the canonical Store form).
fromVL :: VLens s t a b -> Focal s t a b
fromVL vl = mkFocal (Focusing split plug)
  where
    p = reifyVL vl
    split s = (pview p s, s)
    plug s b = pset p s b

-- | Canonical form (@normalize = fromVL . toVL@): re-represent a 'Focal'
--   with the source as residual. Extensional only — see module header.
--   (Written eta-expanded: point-free rank-2 composition needs
--   @ImpredicativeTypes@.)
normalize :: Focal s t a b -> Focal s t a b
normalize foc = fromVL (toVL foc)
