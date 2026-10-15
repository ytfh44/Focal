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
  , elementAt
  , elementE
  , unsafeElementF
  , ListError(..)
  ) where

import GHC.Stack (HasCallStack)

import Focal.Core (Focusing(..))
import Focal.Partial (FocusingE(..))

-- | Context for a list element focus: the elements before and after.
--
--   For @[1,2,3]@ focused on @2@:
--   @left = [1]@, @right = [3]@.
type ListCtx a = ([a], [a])

-- | Safe list element focus. Returns 'Nothing' for negative indices; that
--   is the only construction-time check.
--
--   Declared domain: @0 <= n < length xs@. Outside it (on the list side),
--   'splitF' raises a delayed 'error': 'Focusing' has no failure channel, so
--   the bounds check cannot run at construction time. A check-at-construction
--   variant is 'elementAt'.
--
--   >>> import Focal.Core (overF)
--   >>> fmap (\f -> overF f (*10) [1,2,3]) (elementF 1)
--   Just [1,20,3]
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

-- | Checked list element focus: the bounds check runs at construction time.
--   Returns 'Nothing' unless @0 <= n < length xs@.
--
--   The returned 'Focusing' has the same declared domain as 'unsafeElementF'
--   (lists with @length > n@); applying it to a shorter list still raises the
--   same delayed 'error'.
--
--   >>> import Focal.Core (overF)
--   >>> fmap (\f -> overF f (*10) [1,2,3]) (elementAt 1 [1,2,3])
--   Just [1,20,3]
--
--   >>> fmap (\f -> overF f (*10) [1,2,3]) (elementAt 9 [1,2,3])
--   Nothing
elementAt :: Int -> [a] -> Maybe (Focusing (ListCtx a) [a] [a] a a)
elementAt n xs
  | n < 0 || n >= length xs = Nothing
  | otherwise = Just (unsafeElementF n)

-- | Unsafe list element focus. Throws an error if index is out of bounds.
--   Uses 'HasCallStack' so the error location is reported.
--
--   >>> import Focal.Core (overF)
--   >>> overF (unsafeElementF 1) (*10) [1,2,3]
--   [1,20,3]
--
--   Calling it with a negative index, or applying the returned 'Focusing'
--   outside its declared domain (@0 <= n < length@), raises an 'error'
--   ('HasCallStack' reports the call site).
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

-- | Failure channel for the list focus.
data ListError
  = NegativeIndex Int   -- ^ the index passed to 'elementE' was negative
  | PastEnd Int         -- ^ the index is past the end of the supplied list
  deriving (Eq, Show)

-- | Failure-channel list focus: the index check runs at every 'splitE'
--   against the supplied list; 'plugE' is total. Input-invariant on all lists.
--
--   >>> import Focal.Partial (overE, splitE)
--   >>> overE (elementE 1) (*10) [1,2,3]
--   Right [1,20,3]
--
--   >>> splitE (elementE 9) [1,2,3]
--   Left (PastEnd 9)
--
--   >>> splitE (elementE (-1)) [1,2,3]
--   Left (NegativeIndex (-1))
elementE :: Int -> FocusingE ListError (ListCtx a) [a] [a] a a
elementE n = FocusingE
  { splitE = \xs -> if n < 0
                      then Left (NegativeIndex n)
                      else case splitAt n xs of
                             (l, x : r) -> Right (x, (l, r))
                             _          -> Left (PastEnd n)
  , plugE  = \(l, r) b -> Right (l ++ [b] ++ r)
  }