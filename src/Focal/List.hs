-- | List element focus. The residual is the left and right segments
--   around the focused element, carrying positional geometry
--   (@length left == index@).
--
--   This is a direct instance of McBride's "dissection" of a container functor,
--   where the one-hole context distinguishes elements to the left of the hole
--   from elements to its right — "clowns to the left of me, jokers to the right":
--
--   * C. McBride, "Clowns to the Left of Me, Jokers to the Right (Pearl):
--     Dissecting Data Structures," /POPL '08/, pp. 287-295.
module Focal.List
  ( ListCtx
  , elementF
  , unsafeElementF
  ) where

import GHC.Stack (HasCallStack)

import Focal.Core (Focusing(..))

-- | Context for a list element focus: the elements before and after.
--
--   For @[1,2,3]@ focused on @2@:
--   @left = [1]@, @right = [3]@.
type ListCtx a = ([a], [a])

-- | Safe list element focus. Returns 'Nothing' for negative indices.
--
--   For positive indices, the returned 'Focusing' carries a partial 'splitF'
--   — if the index exceeds the list length, 'splitF' errors lazily when
--   applied to a list. This is a consequence of 'Focusing' being total;
--   the check cannot be performed at construction time without the list.
--
--   >>> elementF 1 "abc"
--   Just (Focusing ...)  -- focuses on 'b'
--
--   >>> elementF 99 "abc"
--   Nothing
elementF :: Int -> Maybe (Focusing (ListCtx a) [a] [a] a a)
elementF n
  | n < 0 = Nothing
  | otherwise = Just $ Focusing
      { splitF = \xs ->
          let (left, rest) = splitAt n xs
          in case rest of
               (x:right) -> (x, (left, right))
               [] -> error "elementF: precondition violated — index out of bounds"
      , plugF = \(left, right) y -> left ++ [y] ++ right
      }

-- | Unsafe list element focus. Throws an error if index is out of bounds.
--   Uses 'HasCallStack' so the error location is reported.
--
--   >>> overF (unsafeElementF 1) (*10) [1,2,3]
--   [1,20,3]
--
--   >>> unsafeElementF (-1)
--   *** Exception: unsafeElementF: index -1 out of bounds
--   ...
unsafeElementF :: HasCallStack => Int -> Focusing (ListCtx a) [a] [a] a a
unsafeElementF n
  | n < 0 = error $ "unsafeElementF: index " ++ show n ++ " out of bounds"
  | otherwise = Focusing
      { splitF = \xs ->
          let (left, rest) = splitAt n xs
          in case rest of
               (x:right) -> (x, (left, right))
               [] -> error $ "unsafeElementF: index " ++ show n ++ " out of bounds (length " ++ show (length xs) ++ ")"
      , plugF = \(left, right) y -> left ++ [y] ++ right
      }