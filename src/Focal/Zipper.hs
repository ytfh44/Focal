{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}

-- | Tree zipper framework.
--
--   A zipper is a focus on a subtree coupled with a "derivative stack"
--   of frames that record how to rebuild upward. This is the intensional
--   specialization of 'Focusing' where the residual IS a frame stack.
--
--   The notion of zipper-based navigation originates from Huet's functional
--   pearl on zippers, and is formalized as a datatype derivative by McBride:
--
--   * G. Huet, "Functional Pearl: The Zipper," /J. Functional Programming/, 1997.
--   * C. McBride, "Clowns to the Left of Me, Jokers to the Right (Pearl):
--     Dissecting Data Structures," /POPL '08/, pp. 287-295.
--
--   Conventions:
--
--   * The context stack is ordered /nearest frame first/ (focus-to-root).
--   * 'descend' returns @(child, frame)@ where the frame remembers how
--     to go back UP from child to parent.
--   * 'ascend' consumes a frame to rebuild the parent from the child.
module Focal.Zipper
  ( -- * The zipper class
    ZipTree(..)
    -- * Zipper type
  , Zip(..)
  , rebuild
    -- * Navigation
  , rootZip
  , up
  , down
  , safeNavigate
    -- * Bridge to Focusing
  , fromZip
  , safeFocusAt
  , unsafeFocusAt
    -- * Shipped instances
  , BinTree(..)
  , BinFrame(..)
  , BinChild(..)
  , Rose(..)
  , RoseFrame(..)
  ) where

import GHC.Stack (HasCallStack)

import Focal.Core (Focusing(..))

-- ---------------------------------------------------------------------------
-- Core class
-- ---------------------------------------------------------------------------

-- | Class for tree types that support zipper-based navigation.
--
--   A lawful instance must satisfy the zipper roundtrip law:
--
--   @
--   descend c t == Just (child, frame)  ==>  ascend frame child == t
--   @
class ZipTree t where
  -- | The type of a single context frame. A frame records enough
  --   information to rebuild the parent node from a replacement child.
  type Frame t

  -- | The type used to select a child.
  type Child t
  type Child t = Int

  -- | Descend from a node to a selected child, producing a frame that
  --   remembers how to go back up.
  descend :: Child t -> t -> Maybe (t, Frame t)

  -- | Ascend from a child to its parent using a frame.
  ascend :: Frame t -> t -> t

-- ---------------------------------------------------------------------------
-- Zipper data type
-- ---------------------------------------------------------------------------

-- | A zipper: a focused subtree together with the context stack
--   needed to rebuild the whole tree.
--
--   @context@ is ordered /nearest frame first/ (focus-to-root).
--   An empty context means the focus is the root.
data Zip t = Zip
  { current :: !t
    -- ^ The focused subtree.
  , context :: [Frame t]
    -- ^ Context stack, nearest frame first.
  }

-- | Rebuild the full tree from a focus and a context stack.
--
--   @rebuild focus [frame_n, ..., frame_1]@ applies frames
--   from nearest to farthest (fold from the right).
rebuild :: ZipTree t => t -> [Frame t] -> t
rebuild = foldl (flip ascend)

-- ---------------------------------------------------------------------------
-- Navigation
-- ---------------------------------------------------------------------------

-- | Create a zipper focused on the root.
rootZip :: t -> Zip t
rootZip t = Zip t []

-- | Move up one level in the zipper.
--   Returns 'Nothing' if already at the root.
up :: ZipTree t => Zip t -> Maybe (Zip t)
up (Zip _ [])     = Nothing
up (Zip a (f:fs)) = Just $ Zip (ascend f a) fs

-- | Move down to a specific child.
down :: ZipTree t => Child t -> Zip t -> Maybe (Zip t)
down c (Zip t fs) = do
  (child, frame) <- descend c t
  pure $ Zip child (frame : fs)

-- | Navigate to a position given by a path (list of child selections),
--   returning the resulting zipper or 'Nothing' if any step fails.
safeNavigate :: ZipTree t => [Child t] -> t -> Maybe (Zip t)
safeNavigate path t = go path (rootZip t)
  where
    go []     z = Just z
    go (c:cs) z = down c z >>= go cs

-- ---------------------------------------------------------------------------
-- Bridge to Focusing
-- ---------------------------------------------------------------------------

-- | Convert a zipper to a 'Focusing'. The residual is the context stack.
--
--   Note: @splitF@ ignores its argument because the focus is already
--   determined by the zipper.
fromZip :: ZipTree t => Zip t -> Focusing [Frame t] t t t t
fromZip z = Focusing
  { splitF = \_ -> (current z, context z)
  , plugF  = \ctx b -> rebuild b ctx
  }

-- | Create a 'Focusing' for a given path, returning 'Nothing' if the path
--   does not exist in the tree.
safeFocusAt :: ZipTree t => [Child t] -> t -> Maybe (Focusing [Frame t] t t t t)
safeFocusAt path t = fromZip <$> safeNavigate path t

-- | Unsafe version of 'safeFocusAt'. Throws an error if the path is invalid.
unsafeFocusAt :: (ZipTree t, HasCallStack, Show (Child t)) => [Child t] -> t -> Focusing [Frame t] t t t t
unsafeFocusAt path t =
  case safeNavigate path t of
    Just z  -> fromZip z
    Nothing -> error $ "unsafeFocusAt: invalid path " ++ show path

-- ---------------------------------------------------------------------------
-- Binary tree
-- ---------------------------------------------------------------------------

-- | A simple binary tree.
data BinTree a
  = Leaf a
  | Node (BinTree a) (BinTree a)
  deriving (Show, Eq)

-- | Binary tree context frame: remembers the sibling.
data BinFrame a
  = LFrame (BinTree a)   -- ^ Went left; right sibling stored.
  | RFrame (BinTree a)   -- ^ Went right; left sibling stored.
  deriving (Show, Eq)

-- | Child selector for binary trees.
data BinChild = GoLeft | GoRight
  deriving (Show, Eq)

instance ZipTree (BinTree a) where
  type Frame (BinTree a) = BinFrame a
  type Child (BinTree a) = BinChild

  descend GoLeft  (Node l r) = Just (l, LFrame r)
  descend GoRight (Node l r) = Just (r, RFrame l)
  descend _       _           = Nothing

  ascend (LFrame r) l = Node l r
  ascend (RFrame l) r = Node l r

-- ---------------------------------------------------------------------------
-- Rose tree (n-ary tree)
-- ---------------------------------------------------------------------------

-- | A rose tree: a node with a label and a list of children.
--
--   This is the most common AST representation.
data Rose a = Rose a [Rose a]
  deriving (Show, Eq)

-- | Rose tree context frame: the parent label, siblings before the focus,
--   and siblings after the focus.
data RoseFrame a = RoseFrame
  { parentLabel :: !a
  , leftSibs    :: [Rose a]
  , rightSibs   :: [Rose a]
  } deriving (Show, Eq)

instance ZipTree (Rose a) where
  type Frame (Rose a) = RoseFrame a

  descend idx (Rose x kids)
    | idx >= 0, idx < length kids =
        case splitAt idx kids of
          (before, selected:after) -> Just (selected, RoseFrame x before after)
          _                        -> Nothing
    | otherwise = Nothing

  ascend (RoseFrame x before after) child =
    Rose x (before ++ [child] ++ after)
