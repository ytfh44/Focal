{-# LANGUAGE GADTs #-}

-- | Core types and operations for the Focal library.
--   Focal unifies Lens, Zipper, and evaluation contexts under a common
--   "explicit residual focus" abstraction.
--
--   A @Focusing c s t a b@ consists of:
--
--   * @splitF :: s -> (a, c)@ — decompose source into focus and residual context
--   * @plugF  :: c -> b -> t@ — rebuild target from residual and new focus
--
--   The residual @c@ is a first-class value recording \"how to rebuild the whole
--   from a replacement focus.\" This is what Lens hides and Zipper concretizes
--   as a frame stack.
module Focal.Core
  ( -- * Core types
    Focusing(..)
  , Focal(..)
    -- * Construction
  , idF
  , fromLensLike
  , pureF
    -- * Composition
  , composeF
  , (>>>)
    -- * Application
  , overF
  , overFM
    -- * Forgetful projections
  , toStoreLike
  , toStoreLikeFocal
    -- * Focal-level wrappers
  , overFocal
  , composeFocal
  ) where

-- | An explicit-residual focusing structure.
--
--   Type parameters:
--
--   * @c@ — residual context type (the \"leftover\" needed to rebuild)
--   * @s@ — source whole (original structure)
--   * @t@ — target whole (structure after replacement)
--   * @a@ — original focus (extracted from @s@)
--   * @b@ — new focus (replaces @a@ to form @t@)
--
--   Diagram:
--
--   @
--           splitF
--      s ───────────▶ a × c
--
--      c × b ───────▶ t
--           plugF
--   @
data Focusing c s t a b = Focusing
  { splitF :: s -> (a, c)
    -- ^ Decompose the source into a focus and a residual context.
    --   The residual records everything needed to later rebuild.
  , plugF :: c -> b -> t
    -- ^ Rebuild the target from a residual context and a new focus.
  }

-- | Existentially quantified variant of 'Focusing'.
--   The residual type @c@ is hidden — only the composable interface remains.
--
--   Use 'Focusing' when you need to inspect the residual (zipper navigation,
--   refactoring context, database provenance). Use 'Focal' when you only need
--   composition and the residual shape is an implementation detail.
data Focal s t a b where
  Focal :: Focusing c s t a b -> Focal s t a b

-- | Identity focus. The residual is unit — no extra information is needed
--   because the \"focus\" is the whole structure.
--
--   Laws:
--
--   * @splitF idF s == (s, ())@
--   * @plugF idF () a == a@
idF :: Focusing () s s s s
idF = Focusing
  { splitF = \s -> (s, ())
  , plugF  = \() b -> b
  }

-- | Compose two focusings. The residuals accumulate as a nested pair.
--   This is the fundamental operation: focus deeper, then rebuild outward.
--
--   @
--   composeF outer inner:
--     1. split outer to get (a, c1)
--     2. split inner on a to get (x, c2)
--     3. modify x to y
--     4. plug inner: use c2 to put y back into a\'s position
--     5. plug outer: use c1 to put the result back into s\'s position
--   @
--
--   Law: @plugF (composeF f g) (c1, c2) y == plugF f c1 (plugF g c2 y)@
composeF
  :: Focusing c1 s t a b   -- ^ outer: s→t, focus a→b
  -> Focusing c2 a b x y   -- ^ inner: a→b, focus x→y
  -> Focusing (c1, c2) s t x y
composeF f g = Focusing split plug
  where
    split s =
      let (a, c1) = splitF f s
          (x, c2) = splitF g a
      in (x, (c1, c2))
    plug (c1, c2) y =
      plugF f c1 (plugF g c2 y)

-- | Infix alias for 'composeF'. Reads left-to-right: \"focus deeper\".
--
--   @
--   personName >>> nameString >>> stringLength
--   -- Focuses on a person\'s name, then the string, then its length.
--   @
infixr 3 >>>
(>>>) :: Focusing c1 s t a b -> Focusing c2 a b x y -> Focusing (c1, c2) s t x y
(>>>) = composeF

-- | Apply a pure function to the focus, rebuilding the whole.
--
--   Law: @overF f id == id@ (no-op update preserves the structure)
overF :: Focusing c s t a b -> (a -> b) -> s -> t
overF f g s =
  let (a, c) = splitF f s
  in plugF f c (g a)

-- | Monadic bridge. Apply a monadic function to the focus while keeping
--   the 'Focusing' itself pure. Effects belong to the outer 'Monad'.
--
--   This follows the \"effect exteralization\" principle: Focal handles
--   spatial decomposition; Monad handles temporal sequencing.
overFM :: Functor m => Focusing c s t a b -> (a -> m b) -> s -> m t
overFM f k s =
  let (a, c) = splitF f s
  in plugF f c <$> k a

-- | Forget the residual, yielding a Store-like representation.
--   This is the extensional projection: useful for Lens interop
--   but lossy — the @b -> t@ function discards residual structure.
--
--   @
--   toStoreLike f s = (view s, set s)
--     where view s = fst (splitF f s)
--           set s b = plugF f (snd (splitF f s)) b
--   @
toStoreLike :: Focusing c s t a b -> s -> (a, b -> t)
toStoreLike f s =
  let (a, c) = splitF f s
  in (a, plugF f c)

-- | 'Focal'-level version of 'toStoreLike'.
toStoreLikeFocal :: Focal s t a b -> s -> (a, b -> t)
toStoreLikeFocal (Focal f) = toStoreLike f

-- | Construct a 'Focusing' from a Lens-like interface (view + set).
--   The residual IS the original whole — the simplest putback-sufficient
--   information. This is how traditional lenses embed into Focal.
--
--   @
--   nameF = fromLensLike
--     (\p -> personName p)
--     (\p newName -> p { personName = newName })
--   @
fromLensLike :: (s -> a) -> (s -> b -> t) -> Focusing s s t a b
fromLensLike view set = Focusing split plug
  where
    split s = (view s, s)
    plug s b = set s b

-- | Alias for 'fromLensLike'. The name emphasizes that the residual is
--   the pure source (no geometry, no provenance — just enough for putback).
pureF :: (s -> a) -> (s -> b -> t) -> Focusing s s t a b
pureF = fromLensLike

-- | 'Focal'-level wrapper for 'overF'.
overFocal :: Focal s t a b -> (a -> b) -> s -> t
overFocal (Focal f) = overF f

-- | 'Focal'-level composition. Both residuals are existentially hidden
--   in the result — the user of a 'Focal' never sees 'c1' or 'c2'.
composeFocal :: Focal s t a b -> Focal a b x y -> Focal s t x y
composeFocal (Focal f) (Focal g) = Focal (composeF f g)
