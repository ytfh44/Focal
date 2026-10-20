{-# LANGUAGE DeriveGeneric #-}
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
    -- * Navigation algebra
  , pathOf
  , framesAt
  , lcaPath
    -- * Bridge to Focusing
  , fromZip
  , focusAt
  , focusAtE
  , PathError(..)
    -- * Shipped instances
  , BinTree(..)
  , BinFrame(..)
  , BinChild(..)
  , Rose(..)
  , RoseFrame(..)
  ) where

import GHC.Generics (Generic1)

import Focal.Core (Focusing(..))
import Focal.Partial (FocusingE(..))

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

  -- | Selector that produced a frame — the selector-level inverse of
  --   'descend'. For every successful descent,
  --   @descend c t == Just (_, fr)@ implies @childOf t fr == c@.
  --   The tree argument only fixes the instance: @Frame t@ is a
  --   non-injective type family, so a frame alone does not determine @t@.
  --   Total: every frame records the step that reached its subtree.
  childOf :: t -> Frame t -> Child t

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
-- Navigation algebra
-- ---------------------------------------------------------------------------

-- | Selector path of a zipper's context stack: the root-first list of
--   selectors that produced the nearest-first frame stack. For a stack
--   @[fr_n, ..., fr_1]@ (nearest first), @pathOf = map (childOf node) .
--   reverse@ where @node@ is the zipper's focus.
--
--   @
--   safeNavigate p t == Just z  ==>  pathOf z == p
--   @
pathOf :: ZipTree t => Zip t -> [Child t]
pathOf (Zip node fs) = map (childOf node) (reverse fs)

-- | Context stack reached by a path in a supplied tree: @framesAt p t@ is
--   the nearest-first frame stack along @p@, or 'Nothing' when @p@ is absent
--   from @t@.
--
--   Navigation splits over path concatenation: navigating @p ++ q@ equals
--   navigating @p@ and then @q@ from the resulting focus, and the context
--   stacks concatenate nearer-first —
--
--   @
--   safeNavigate p t == Just z  ==>
--     framesAt (p ++ q) t == (++) <$> framesAt q (current z) <*> framesAt p t
--   @
framesAt :: ZipTree t => [Child t] -> t -> Maybe [Frame t]
framesAt p t = context <$> safeNavigate p t

-- | Longest common prefix of two selector paths — the deepest shared
--   navigation prefix.
--
--   @lcaPath xs ys@ is the longest @zs@ with @xs = zs ++ xs'@ and
--   @ys = zs ++ ys'@ for some suffixes @xs'@, @ys'@.
lcaPath :: Eq c => [c] -> [c] -> [c]
lcaPath (x:xs) (y:ys) | x == y = x : lcaPath xs ys
lcaPath _      _               = []

-- ---------------------------------------------------------------------------
-- Bridge to Focusing
-- ---------------------------------------------------------------------------

-- | Convert a zipper to a 'Focusing'. The residual is the context stack.
--
--   Snapshot semantics: @splitF@ ignores its argument and returns the focus
--   and context captured in the zipper. It is input-invariant only for the
--   tree the zipper was built from, and not a general split-plug lawful
--   instance for other sources (docs/conformance.md). For the dynamic,
--   input-sensitive counterpart see 'focusAt'.
--
--   An instance embedding it (@toOptional (fromZip z)@, or @composeO@/
--   @composeF@ over it) inherits the registered PG-failing verdict — the
--   input-invariance exemption is not lifted by composition.
fromZip :: ZipTree t => Zip t -> Focusing [Frame t] t t t t
fromZip z = Focusing
  { splitF = \_ -> (current z, context z)
  , plugF  = \ctx b -> rebuild b ctx
  }

-- | Build a focus at a path. The path is validated against the supplied
--   tree at construction time ('Nothing' if it does not exist).
--
--   Unlike 'fromZip', the result is *dynamic*: @splitF@ re-navigates the
--   supplied source, so the focus is whatever sits at @path@ in the tree
--   passed to @splitF@/@plugF@. It is input-invariant on its declared
--   domain — trees in which @path@ exists. Outside the domain (a later
--   source lacking the path), @splitF@ raises a delayed 'error': 'Focusing'
--   has no failure channel.
--
--   The residual premise is that residuals are frames obtained from the same
--   tree at @path@; a hand-built context stack is outside it.
focusAt :: ZipTree t => [Child t] -> t -> Maybe (Focusing [Frame t] t t t t)
focusAt path t =
  case safeNavigate path t of
    Nothing -> Nothing
    Just _  -> Just Focusing
      { splitF = \t' ->
          case safeNavigate path t' of
            Just z  -> (current z, context z)
            Nothing -> error "focusAt: path not found in the supplied tree"
      , plugF = \ctx b -> rebuild b ctx
      }

-- ---------------------------------------------------------------------------
-- Failure-channel dynamic focus
-- ---------------------------------------------------------------------------

-- | Failure channel for dynamic path navigation: @'PathError' i@ carries the
--   0-based index of the first path step that cannot be taken.
newtype PathError = PathError Int
  deriving (Eq, Show)

-- | Failure-channel counterpart of 'focusAt'. Construction never fails:
--   @splitE@ re-navigates the supplied tree on every call and reports the
--   first step that cannot be taken as @Left ('PathError' i)@ with @i@
--   0-based; the empty path succeeds at the root of every tree. @plugE@ is
--   total, @plugE ctx b = Right (rebuild b ctx)@; no deferred 'error'.
--
--   >>> import Focal.Partial (splitE)
--   >>> let r = Rose 1 [Rose 2 [], Rose 3 [Rose 4 []]]
--   >>> fmap fst (splitE (focusAtE [1, 0]) r)
--   Right (Rose 4 [])
--   >>> splitE (focusAtE [1, 2]) r
--   Left (PathError 1)
focusAtE :: ZipTree t => [Child t] -> FocusingE PathError [Frame t] t t t t
focusAtE path = FocusingE
  { splitE = \t -> case step 0 path (rootZip t) of
      Left i  -> Left (PathError i)
      Right z -> Right (current z, context z)
  , plugE  = \ctx b -> Right (rebuild b ctx)
  }
  where
    step _ []       z = Right z
    step i (c : cs) z = case down c z of
      Nothing -> Left i
      Just z' -> step (i + 1) cs z'

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

  childOf _ (LFrame _) = GoLeft
  childOf _ (RFrame _) = GoRight

-- ---------------------------------------------------------------------------
-- Rose tree (n-ary tree)
-- ---------------------------------------------------------------------------

-- | A rose tree: a node with a label and a list of children.
--
--   This is the most common AST representation.
data Rose a = Rose a [Rose a]
  deriving (Show, Eq, Generic1)

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

  childOf _ (RoseFrame _ before _) = length before
