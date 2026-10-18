-- | The parser layer (v1: the ambiguity-free domain).
--
--   A grammar is a choice tree over a token alphabet: for each node
--   kind, an ordered list of named alternative productions (the name is
--   the alternative's PROVENANCE TAG), each a sequence of symbols — a
--   terminal (a literal token) or a nonterminal (a node kind).  The
--   parser state is the linear progress: the tokens consumed so far and
--   the remaining ones (backtracking stays out of v1).  Parsing derives
--   a forest of completed parses; every node carries the alternative
--   that produced it — CHOICE PROVENANCE is recorded, never hidden.
--
--   The parse-forest node focus is the pair of the selected node and
--   its provenance-preserving context: the SELECTION COORDINATE (a
--   path of child indices) picks one node, and the focus chains the
--   provenance of every ancestor (selected node first, root last), so
--   a replacement in a refactored forest keeps the choice records —
--   the ancestors' alternatives survive 'replaceAt' untouched, and the
--   replaced node's own provenance is the new node's.
--
--   The v1 domain is AMBIGUITY-FREE: each forest node has exactly one
--   derivation, so the selection coordinate always points at the unique
--   derivation.  The multi-derivation case is detected STATICALLY —
--   'ambiguities' reports every kind with more than one alternative
--   (potentially ambiguous; possibly never exercised by an input) —
--   and REPORTED, never resolved.
--
--   >>> import Focal.Parser
--   >>> let g = [("n", [("lit", [Term "x"])]), ("p", [("pair", [NonTerm "n", NonTerm "n"])])]
--   >>> parse g ["x", "x"] "p"
--   Just (Forest "p" (Alt "pair") [Forest "n" (Alt "lit") [Forest "x" (Alt "x") []],Forest "n" (Alt "lit") [Forest "x" (Alt "x") []]],["x","x"])
--   >>> parse g ["x"] "n"
--   Just (Forest "n" (Alt "lit") [Forest "x" (Alt "x") []],["x"])
--   >>> parse g ["y"] "n"
--   Nothing
--   >>> ambiguities g
--   []
--   >>> ambiguities [("n", [("a", [Term "x"]), ("b", [Term "y"])])]
--   [Ambiguous "n" ["a","b"]]
--   >>> parseAll g ["x", "x"] "p"
--   [Forest "p" (Alt "pair") [Forest "n" (Alt "lit") [Forest "x" (Alt "x") []],Forest "n" (Alt "lit") [Forest "x" (Alt "x") []]]]
--   >>> parseAll g ["x"] "p"
--   []
--   >>> select (Selection [1]) (Forest "p" (Alt "pair") [Forest "n" (Alt "lit") [Forest "x" (Alt "x") []],Forest "m" (Alt "lit2") []])
--   Just (Forest "m" (Alt "lit2") [])
--   >>> select (Selection [5]) (Forest "p" (Alt "pair") [Forest "n" (Alt "lit") [],Forest "m" (Alt "lit2") []])
--   Nothing
--   >>> fmap nodeAlt (select (Selection [1]) (Forest "p" (Alt "pair") [Forest "n" (Alt "lit") [Forest "x" (Alt "x") []],Forest "m" (Alt "lit2") []]))
--   Just (Alt "lit2")
--   >>> fmap (nodeAlt . focusNode) (focusAt (Selection [1]) (Forest "p" (Alt "pair") [Forest "n" (Alt "lit") [Forest "x" (Alt "x") []],Forest "m" (Alt "lit2") []]))
--   Just (Alt "lit2")
--   >>> fmap focusProv (focusAt (Selection [1]) (Forest "p" (Alt "pair") [Forest "n" (Alt "lit") [Forest "x" (Alt "x") []],Forest "m" (Alt "lit2") []]))
--   Just [Alt "pair",Alt "lit2"]
--   >>> fmap focusProv (replaceAt (Selection [1]) (Forest "p" (Alt "pair") [Forest "n" (Alt "lit") [Forest "x" (Alt "x") []],Forest "m" (Alt "lit2") []]) (Forest "z" (Alt "zz") []) >>= focusAt (Selection [1]))
--   Just [Alt "pair",Alt "zz"]
--   >>> fmap nodeAlt (replaceAt (Selection [1]) (Forest "p" (Alt "pair") [Forest "n" (Alt "lit") [Forest "x" (Alt "x") []],Forest "m" (Alt "lit2") []]) (Forest "z" (Alt "zz") []) >>= select (Selection [1]))
--   Just (Alt "zz")
module Focal.Parser
  ( Alt(..)
  , Sym(..)
  , Grammar
  , ParseState(..)
  , Forest(..)
  , Ambiguity(..)
  , parseOne
  , deriveSeq
  , deriveSym
  , parse
  , parseAll
  , deriveSeqAll
  , deriveSymAll
  , ambiguities
  , Selection(..)
  , select
  , nodeAlt
  , NodeFocus(..)
  , focusAt
  , replaceAt
  ) where

--------------------------------------------------------------------
-- Grammar: alternatives, symbols, the choice tree
--------------------------------------------------------------------

-- | A grammar alternative: one production of a node kind.
data Alt = Alt String      -- ^ the alternative's name (its provenance tag)
  deriving (Eq, Show)

-- | One production: a sequence of symbols; a symbol is a terminal
--   (a literal token) or a nonterminal (a node kind).
data Sym = Term String | NonTerm String
  deriving (Eq, Show)

-- | A grammar: for each node kind, its alternative productions (each
--   named — the name is the provenance tag).
type Grammar = [(String, [(String, [Sym])])]

--------------------------------------------------------------------
-- Parse state
--------------------------------------------------------------------

-- | Parse state: the input tokens consumed so far and the remaining
--   ones (the v1 state is linear; backtracking stays out of v1).
data ParseState = ParseState
  { consumed :: [String]
  , rest     :: [String]
  }
  deriving Eq

-- | 'ParseState' takes two unquoted list arguments.
instance Show ParseState where
  showsPrec d (ParseState c r) =
    showParen (d > 10)
      (showString "ParseState " . shows c . showChar ' ' . shows r)

--------------------------------------------------------------------
-- Parse forest with choice provenance
--------------------------------------------------------------------

-- | A parse-forest node: a kind, the alternative that derived it (the
--   provenance), and its children.
data Forest = Forest String Alt [Forest]
  deriving (Eq, Show)

-- | Ambiguity report: a node kind whose grammar has several
--   derivations (the potentially ambiguous kinds — v1 detects and
--   reports; it never resolves).  The field lists the ALTERNATIVE
--   NAMES (the provenance tags) of the kind's productions.
data Ambiguity = Ambiguous String [String]
  deriving (Eq, Show)

--------------------------------------------------------------------
-- Parsing: the deterministic derivation
--------------------------------------------------------------------

-- | Derive one node of the given kind from the state: try the kind's
--   alternatives in order; the FIRST alternative that matches wins and
--   its name is recorded as the node's provenance (deterministic
--   choice; the multi-derivation case is 'ambiguities'' business).
--   'Nothing' when the kind is unknown or no alternative matches.
parseOne :: Grammar -> ParseState -> String -> Maybe (Forest, ParseState)
parseOne g st kind = do
  alts <- lookup kind g
  firstAlt alts
  where
    firstAlt [] = Nothing
    firstAlt ((name, syms) : as) = case deriveSeq g st syms of
      Just (kids, st') -> Just (Forest kind (Alt name) kids, st')
      Nothing          -> firstAlt as

-- | Derive a symbol sequence: terminals consume their token; derived
--   nonterminals recurse (depth-first, left to right).
deriveSeq :: Grammar -> ParseState -> [Sym] -> Maybe ([Forest], ParseState)
deriveSeq _  st []     = Just ([], st)
deriveSeq g  st (s:ss) = case deriveSym g st s of
  Nothing         -> Nothing
  Just (kid, st') -> case deriveSeq g st' ss of
    Just (kids, st'') -> Just (kid : kids, st'')
    Nothing           -> Nothing

-- | Derive one symbol: a terminal consumes one token equal to its
--   name (its forest node's kind IS the token, its provenance the
--   same literal); a nonterminal recurses through 'parseOne'.
deriveSym :: Grammar -> ParseState -> Sym -> Maybe (Forest, ParseState)
deriveSym _  (ParseState _ [])     (Term _)  = Nothing
deriveSym _  (ParseState c (t:ts)) (Term n)
  | t == n    = Just (Forest t (Alt t) [], ParseState (c ++ [t]) ts)
  | otherwise = Nothing
deriveSym g  st                    (NonTerm k) = parseOne g st k

--------------------------------------------------------------------
-- Top-level parse and the ambiguity report
--------------------------------------------------------------------

-- | Parse a top-level kind: the whole input must be consumed.  The
--   result is the forest and the consumed tokens (the parse's own
--   trace of the input, in order).
parse :: Grammar -> [String] -> String -> Maybe (Forest, [String])
parse g input kind = case parseOne g (ParseState [] input) kind of
  Just (f, st) | null (rest st) -> Just (f, consumed st)
  _ -> Nothing

-- | The grammar's ambiguity report: every kind with more than one
--   alternative (the potentially ambiguous kinds — v1 detects and
--   reports; resolution is out of scope, and the v1 domain keeps to
--   unambiguous kinds).
ambiguities :: Grammar -> [Ambiguity]
ambiguities g = [ Ambiguous k (map fst alts) | (k, alts) <- g, length alts > 1 ]

--------------------------------------------------------------------
-- Selection, focus, and provenance-preserving replacement
--------------------------------------------------------------------

-- | The parse-selection coordinate: a path of child indices from the
--   forest root, selecting one node.  The provenance of the selected
--   node is the node's own (never hidden).
newtype Selection = Selection [Int]
  deriving (Eq, Show)

-- | Select a node: walk the path; 'Nothing' when an index is out of
--   range (the selection is reported as absent, never clamped).
select :: Selection -> Forest -> Maybe Forest
select (Selection [])     f          = Just f
select (Selection (i:is)) (Forest _ _ kids)
  | i < 0 || i >= length kids = Nothing
  | otherwise                 = select (Selection is) (kids !! i)

-- | A node's own provenance.
nodeAlt :: Forest -> Alt
nodeAlt (Forest _ a _) = a

-- | The node focus: the selected node plus its provenance-preserving
--   context — the parent chain with the provenance of every ancestor
--   (selected node first, root last; the replacement in a refactored
--   forest keeps the choice records).
data NodeFocus = NodeFocus
  { focusNode  :: Forest
  , focusProv  :: [Alt]        -- ^ provenance chain: selected node first, root last
  }
  deriving (Eq, Show)

-- | Focus a selection: the node and its provenance chain.
focusAt :: Selection -> Forest -> Maybe NodeFocus
focusAt sel root = go sel root []
  where
    go (Selection []) cur acc = Just (NodeFocus cur (acc ++ [nodeAlt cur]))
    go (Selection (i:is)) (Forest _ a kids) acc
      | i < 0 || i >= length kids = Nothing
      | otherwise                 = go (Selection is) (kids !! i) (acc ++ [a])

-- | Replace the selected node (keeping every ancestor's provenance):
--   the new node takes the selected node's position; the choice records
--   of the ancestors are preserved and the replaced node's own
--   provenance is the NEW node's.
replaceAt :: Selection -> Forest -> Forest -> Maybe Forest
replaceAt (Selection [])     _         new = Just new
replaceAt (Selection (i:is)) (Forest k a kids) new
  | i < 0 || i >= length kids = Nothing
  | otherwise = do
      kid' <- replaceAt (Selection is) (kids !! i) new
      Just (Forest k a [ if j == i then kid' else kid | (j, kid) <- zip [0..] kids ])

-- | Parse ALL derivations of a kind: every completed parse the
--   grammar's alternatives admit.  A derivation contributes only when
--   it consumes the WHOLE input (partial derivations are pruned at
--   every alternative boundary, so the enumeration stays exact); the
--   list is empty when nothing consumes the whole input, and (in the
--   v1 ambiguity-free domain) has at most one element when something
--   does.
parseAll :: Grammar -> [String] -> String -> [Forest]
parseAll g input kind = go (ParseState [] input) kind
  where
    -- Pruned enumeration: a derivation is kept only when it consumed
    -- the WHOLE input from this state (the empty sequence trivially
    -- does); with zero-consumption pruning in 'deriveSymAll' the
    -- recursion terminates and a surviving root is a completed parse.
    go st k = case lookup k g of
      Nothing   -> []
      Just alts -> concatMap (one st) alts
      where
        one s (name, syms) =
          [ Forest k (Alt name) kids
          | (kids, st') <- deriveSeqAll g s syms
          , null (rest st')
          ]

-- | The enumerating counterpart of 'deriveSeq': ALL ways to derive the
--   symbol sequence, each pairing its child forests with the state
--   after the sequence (partial consumption is possible — a sequence
--   may end mid-input; callers check total consumption).
deriveSeqAll :: Grammar -> ParseState -> [Sym] -> [([Forest], ParseState)]
deriveSeqAll _  st []     = [([], st)]
deriveSeqAll g  st (s:ss) =
  [ (kid : kids, st'') | (kid, st')  <- deriveSymAll g st s
                       , (kids, st'') <- deriveSeqAll g st' ss ]

-- | The enumerating counterpart of 'deriveSym': every way to derive
--   one symbol from the state (a terminal has at most one; a
--   nonterminal has one per matching alternative).  ZERO-CONSUMPTION
--   PRUNING: a nonterminal derivation that consumes no tokens is
--   dropped — this is what bounds the enumeration (each surviving
--   step consumes strictly through the remaining tokens, so the
--   recursion terminates).
deriveSymAll :: Grammar -> ParseState -> Sym -> [(Forest, ParseState)]
deriveSymAll _  (ParseState _ [])     (Term _)  = []
deriveSymAll _  (ParseState c (t:ts)) (Term n)
  | t == n    = [(Forest t (Alt t) [], ParseState (c ++ [t]) ts)]
  | otherwise = []
deriveSymAll g  st                    (NonTerm k) =
  [ (f, st') | (f, st') <- concatMap (one st) (altsOf k), grew st st' ]
  where
    altsOf kind = maybe [] id (lookup kind g)
    one s (name, syms) =
      [ (Forest k (Alt name) kids, s')
      | (kids, s') <- deriveSeqAll g s syms
      , grew s s'
      ]
    grew (ParseState c0 _) (ParseState c1 _) = length c1 > length c0
