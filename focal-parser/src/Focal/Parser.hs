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
--   A DERIVATION TERMINATES BY A PROGRESS CRITERION, not by an
--   acyclicity precondition: a step that re-enters the SAME nonterminal
--   at the SAME input position has consumed nothing and makes no
--   progress, so it fails — the deterministic family reports absence,
--   the enumerating family reports no derivation.  A re-entry at a
--   LATER position has consumed input and stays legal, so a productive
--   right-recursive grammar parses as before and a cyclic grammar
--   terminates with no result instead of diverging.
--
--   The FOREST focus extends the node focus: its residual is not a tree
--   but a FRAME LIST (nearest-first) — each frame records one ancestor's
--   kind and provenance plus the siblings left and right of the hole at
--   that level.  The selection coordinate the focus was taken at travels
--   in the residual independently of the frames, so the replacement laws
--   are stated RELATIVE TO that coordinate: 'plugForest' rebuilds from
--   the frames with the new node in the hole, and the coordinate
--   re-selects the replaced node.  A residual can ONLY be obtained from
--   'focusForest' (its constructor is not exported), so its frames are
--   consistent with its coordinate BY CONSTRUCTION and the replacement
--   laws hold over the WHOLE plug domain.  A replacement also induces a
--   parse-set change — for the replaced node's kind, the grammar's
--   alternatives minus the one the node's provenance claims — which
--   'reparseReport' COMPUTES and REPORTS, never resolves: it also
--   evaluates the node's own LOCAL structural admission ('admits' —
--   does the node's kind derive it from these children?), so the
--   outcome is decisive on the node, not merely a list of alternatives.
--   Ambiguity preservation is the report, not a choice.
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
--   >>> fmap focusResidual (focusForest (Selection [1]) (Forest "p" (Alt "pair") [Forest "n" (Alt "lit") [Forest "x" (Alt "x") []],Forest "m" (Alt "lit2") []]))
--   Just (Residual (FCtx [Frame "p" (Alt "pair") [Forest "n" (Alt "lit") [Forest "x" (Alt "x") []]] []]) (Selection [1]))
--   >>> fmap (\ff -> plugForest (focusResidual ff) (Forest "z" (Alt "zz") [])) (focusForest (Selection [1]) (Forest "p" (Alt "pair") [Forest "n" (Alt "lit") [Forest "x" (Alt "x") []],Forest "m" (Alt "lit2") []]))
--   Just (Forest "p" (Alt "pair") [Forest "n" (Alt "lit") [Forest "x" (Alt "x") []],Forest "z" (Alt "zz") []])
--   >>> fmap (\ff -> plugForest (focusResidual ff) (Forest "z" (Alt "zz") [])) (focusForest (Selection [0,0]) (Forest "p" (Alt "pair") [Forest "n" (Alt "lit") [Forest "x" (Alt "x") []],Forest "m" (Alt "lit2") []]))
--   Just (Forest "p" (Alt "pair") [Forest "n" (Alt "lit") [Forest "z" (Alt "zz") []],Forest "m" (Alt "lit2") []])
--   >>> fmap (\ff -> select (residualSel (focusResidual ff)) (plugForest (focusResidual ff) (Forest "z" (Alt "zz") []))) (focusForest (Selection [1]) (Forest "p" (Alt "pair") [Forest "n" (Alt "lit") [],Forest "m" (Alt "lit2") []]))
--   Just (Just (Forest "z" (Alt "zz") []))
--   >>> reparseReport [("p", [("pair", []), ("solo", [])])] (Forest "p" (Alt "pair") [])
--   ReparseReport "p" (Alt "pair") True ["solo"]
--   >>> reparseReport [("p", [("pair", [])])] (Forest "p" (Alt "pair") [])
--   ReparseReport "p" (Alt "pair") True []
--   >>> fmap focusResidual (focusForest (Selection [5]) (Forest "p" (Alt "pair") []))
--   Nothing
--   >>> admits [("n", [("lit", [Term "x"])])] (Forest "n" (Alt "lit") [])
--   False
--   >>> admits [("n", [("lit", [Term "x"])])] (Forest "n" (Alt "lit") [Forest "x" (Alt "x") []])
--   True
--   >>> let ge = [("e", [("empty", [])]), ("q", [("two", [NonTerm "e", Term "x"])])]
--   >>> fmap fst (parse ge ["x"] "q")
--   Just (Forest "q" (Alt "two") [Forest "e" (Alt "empty") [],Forest "x" (Alt "x") []])
--   >>> parseAll ge ["x"] "q"
--   []
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
  , Frame(..)
  , FCtx(..)
  , Residual
  , residualCtx
  , residualSel
  , ForestFocus(..)
  , focusForest
  , plugForest
  , admits
  , ReparseReport(..)
  , reparseReport
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

-- | The input position of a parse state: the number of tokens consumed
--   so far — the PROGRESS MEASURE of a derivation (a step that
--   re-enters a nonterminal at the same position has made no progress).
position :: ParseState -> Int
position = length . consumed

-- | The derivation path: the ANCESTOR expansions in progress, each a
--   nonterminal kind with the input position it was expanded at.  A
--   sibling's expansion is never on the path (only an ancestor's), so
--   the same nonterminal may occur twice in one production.
type Path = [(String, Int)]

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
--
--   A kind already expanded at the SAME input position on the current
--   derivation path makes no progress and is not expanded again: that
--   derivation fails (absence), which is what keeps a cyclic grammar
--   terminating.
parseOne :: Grammar -> ParseState -> String -> Maybe (Forest, ParseState)
parseOne g st kind = parseOneAt g st kind []

-- | 'parseOne' with the derivation path threaded: the path holds the
--   ANCESTOR expansions (a nonterminal kind and the input position it
--   was expanded at), never a sibling's.  Expanding a kind already on
--   the path at the SAME position fails; the kind is pushed onto the
--   path for the expansion of its own production.
parseOneAt :: Grammar -> ParseState -> String -> Path -> Maybe (Forest, ParseState)
parseOneAt g st kind path
  | (kind, position st) `elem` path = Nothing
  | otherwise = do
      alts <- lookup kind g
      firstAlt alts
  where
    firstAlt [] = Nothing
    firstAlt ((name, syms) : as) = case deriveSeqAt g st syms path' of
      Just (kids, st') -> Just (Forest kind (Alt name) kids, st')
      Nothing          -> firstAlt as
    path' = (kind, position st) : path

-- | Derive a symbol sequence: terminals consume their token; derived
--   nonterminals recurse (depth-first, left to right).
deriveSeq :: Grammar -> ParseState -> [Sym] -> Maybe ([Forest], ParseState)
deriveSeq g st syms = deriveSeqAt g st syms []

-- | 'deriveSeq' with the derivation path threaded: the path is the
--   ANCESTOR expansions of the sequence, so each sibling symbol is
--   expanded with the same path (a sibling is not an ancestor).
deriveSeqAt :: Grammar -> ParseState -> [Sym] -> Path -> Maybe ([Forest], ParseState)
deriveSeqAt _  st []     _path = Just ([], st)
deriveSeqAt g  st (s:ss) path = case deriveSymAt g st s path of
  Nothing         -> Nothing
  Just (kid, st') -> case deriveSeqAt g st' ss path of
    Just (kids, st'') -> Just (kid : kids, st'')
    Nothing           -> Nothing

-- | Derive one symbol: a terminal consumes one token equal to its
--   name (its forest node's kind IS the token, its provenance the
--   same literal); a nonterminal recurses through 'parseOne'.
deriveSym :: Grammar -> ParseState -> Sym -> Maybe (Forest, ParseState)
deriveSym g st sym = deriveSymAt g st sym []

-- | 'deriveSym' with the derivation path threaded: a nonterminal
--   already expanded at the SAME input position on the path fails (no
--   progress); one expanded at a LATER position is legal (input was
--   consumed).
deriveSymAt :: Grammar -> ParseState -> Sym -> Path -> Maybe (Forest, ParseState)
deriveSymAt _  (ParseState _ [])     (Term _)  _path = Nothing
deriveSymAt _  (ParseState c (t:ts)) (Term n) _path
  | t == n    = Just (Forest t (Alt t) [], ParseState (c ++ [t]) ts)
  | otherwise = Nothing
deriveSymAt g  st                    (NonTerm k) path = parseOneAt g st k path

--------------------------------------------------------------------
-- Top-level parse and the ambiguity report
--------------------------------------------------------------------

-- | Parse a top-level kind: the whole input must be consumed.  The
--   result is the forest and the consumed tokens (the parse's own
--   trace of the input, in order).  A derivation that re-enters a
--   nonterminal at the SAME input position makes no progress and fails,
--   so a cyclic grammar yields no parse (absence) instead of
--   diverging.
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
--   (root first, selected node last; the replacement in a refactored
--   forest keeps the choice records).
data NodeFocus = NodeFocus
  { focusNode  :: Forest
  , focusProv  :: [Alt]        -- ^ provenance chain: root first, selected node last
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
--   grammar's alternatives admit (a derivation contributes only when
--   it consumes the WHOLE input — partial derivations are pruned at
--   every alternative boundary).  The enumeration is exact for
--   grammars whose nonterminals are non-nullable (no alternative
--   derives the empty token sequence); the zero-consumption prune is
--   what bounds the enumeration — a nullable derivation is dropped
--   rather than looping, so 'parseAll' may return fewer results than
--   'parse' admits in exactly that case.  The recursion is bounded by
--   the progress criterion as well: a derivation that re-enters a
--   nonterminal at the SAME input position makes no progress and
--   contributes no derivation, so a cyclic grammar enumerates nothing
--   instead of diverging.  Several alternatives may match the
--   same input, so a kind with more than one derivation yields one
--   forest per derivation, in grammar order (enumerated, never
--   silently resolved).
parseAll :: Grammar -> [String] -> String -> [Forest]
parseAll g input kind = go (ParseState [] input) kind []
  where
    -- Pruned enumeration: a derivation is kept only when it consumed
    -- the WHOLE input from this state (the empty sequence trivially
    -- does); with zero-consumption pruning in 'deriveSymAll' the
    -- recursion terminates and a surviving root is a completed parse.
    go st k path = case lookup k g of
      Nothing   -> []
      Just alts -> concatMap (one st path) alts
      where
        one s p (name, syms) =
          [ Forest k (Alt name) kids
          | (kids, st') <- deriveSeqAllAt g s syms ((k, position s) : p)
          , null (rest st')
          ]

-- | The enumerating counterpart of 'deriveSeq': ALL ways to derive the
--   symbol sequence, each pairing its child forests with the state
--   after the sequence (partial consumption is possible — a sequence
--   may end mid-input; callers check total consumption).
deriveSeqAll :: Grammar -> ParseState -> [Sym] -> [([Forest], ParseState)]
deriveSeqAll g st syms = deriveSeqAllAt g st syms []

-- | 'deriveSeqAll' with the derivation path threaded: the path is the
--   ANCESTOR expansions of the sequence, so each sibling symbol is
--   expanded with the same path (a sibling is not an ancestor).
deriveSeqAllAt :: Grammar -> ParseState -> [Sym] -> Path -> [([Forest], ParseState)]
deriveSeqAllAt _  st []     _path = [([], st)]
deriveSeqAllAt g  st (s:ss) path =
  [ (kid : kids, st'') | (kid, st')  <- deriveSymAllAt g st s path
                       , (kids, st'') <- deriveSeqAllAt g st' ss path ]

-- | The enumerating counterpart of 'deriveSym': every way to derive
--   one symbol from the state (a terminal has at most one; a
--   nonterminal has one per matching alternative).  ZERO-CONSUMPTION
--   PRUNING: a nonterminal derivation that consumes no tokens is
--   dropped — this is what bounds the enumeration (each surviving
--   step consumes strictly through the remaining tokens; a nullable
--   derivation is dropped, not looped, so the enumeration is exact
--   exactly on the non-nullable fragment).
deriveSymAll :: Grammar -> ParseState -> Sym -> [(Forest, ParseState)]
deriveSymAll g st sym = deriveSymAllAt g st sym []

-- | 'deriveSymAll' with the derivation path threaded: a nonterminal
--   already expanded at the SAME input position on the path has no
--   derivations (no progress); one expanded at a LATER position is
--   legal (input was consumed).
deriveSymAllAt :: Grammar -> ParseState -> Sym -> Path -> [(Forest, ParseState)]
deriveSymAllAt _  (ParseState _ [])     (Term _)  _path = []
deriveSymAllAt _  (ParseState c (t:ts)) (Term n) _path
  | t == n    = [(Forest t (Alt t) [], ParseState (c ++ [t]) ts)]
  | otherwise = []
deriveSymAllAt g  st                    (NonTerm k) path
  | (k, position st) `elem` path = []
  | otherwise =
    [ (f, st') | (f, st') <- concatMap (one st) (altsOf k), grew st st' ]
  where
    altsOf kind = maybe [] id (lookup kind g)
    one s (name, syms) =
      [ (Forest k (Alt name) kids, s')
      | (kids, s') <- deriveSeqAllAt g s syms ((k, position s) : path)
      , grew s s'
      ]
    grew (ParseState c0 _) (ParseState c1 _) = length c1 > length c0

--------------------------------------------------------------------
-- Forest focus: the frame-list residual, replacement, and the
-- parse-set report (ambiguity preservation, never resolution)
--------------------------------------------------------------------

-- | One frame of a forest context: the ancestor's kind and provenance,
--   and the siblings left/right of the hole at that level.
data Frame = Frame
  { frameKind  :: String
  , frameAlt   :: Alt
  , frameLeft  :: [Forest]
  , frameRight :: [Forest]
  }
  deriving Eq

-- | 'Frame' takes four precedence 11 arguments.
instance Show Frame where
  showsPrec d (Frame k a l r) =
    showParen (d > 10)
      (  showString "Frame " . showsPrec 11 k . showChar ' ' . showsPrec 11 a
      . showChar ' ' . showsPrec 11 l . showChar ' ' . showsPrec 11 r
      )

-- | A forest context: the frames from the hole up to the root
--   (nearest-first).  The residual is NOT a tree — it is this frame
--   list; every ancestor's provenance travels in its frame, so choice
--   records survive by construction.
newtype FCtx = FCtx [Frame]
  deriving (Eq, Show)

-- | The residual of a forest focus: the frame-list context and the
--   selection coordinate the focus was taken at.  A residual can ONLY
--   be obtained from 'focusForest' (its constructor is not exported),
--   so its frames are consistent with its coordinate BY CONSTRUCTION
--   and the replacement laws hold over the WHOLE plug domain.
--   'plugForest' ignores 'residualSel'.
data Residual = Residual FCtx Selection
  deriving Eq

-- | The residual's frame-list context.
residualCtx :: Residual -> FCtx
residualCtx (Residual c _) = c

-- | The residual's selection coordinate — the coordinate the focus was
--   taken at, which re-selects the plugged node.
residualSel :: Residual -> Selection
residualSel (Residual _ s) = s

-- | 'Residual' takes two precedence 11 arguments.
instance Show Residual where
  showsPrec d (Residual c s) =
    showParen (d > 10)
      (showString "Residual " . showsPrec 11 c . showChar ' ' . showsPrec 11 s)

-- | The forest focus: the selected node and its residual — the context
--   plus the selection coordinate (the replacement laws are stated
--   relative to this coordinate).
data ForestFocus = ForestFocus
  { focused       :: Forest
  , focusResidual :: Residual
  }
  deriving Eq

-- | 'ForestFocus' takes two precedence 11 arguments.
instance Show ForestFocus where
  showsPrec d (ForestFocus f r) =
    showParen (d > 10)
      (showString "ForestFocus " . showsPrec 11 f . showChar ' ' . showsPrec 11 r)

-- | Focus a selection: 'Nothing' when the path is out of range (the
--   coordinate is reported as absent, never clamped).  The frames are
--   collected nearest-first (each level's frame is prepended as we
--   descend, so the deepest frame lands first) with the siblings split
--   around each hole.
focusForest :: Selection -> Forest -> Maybe ForestFocus
focusForest sel root = do
  (node, frames) <- go sel root []
  Just (ForestFocus node (Residual (FCtx frames) sel))
  where
    go (Selection [])     cur acc = Just (cur, acc)
    go (Selection (i:is)) (Forest k a kids) acc
      | i < 0 || i >= length kids = Nothing
      | otherwise =
          go (Selection is) (kids !! i)
             (Frame k a (take i kids) (drop (i + 1) kids) : acc)

-- | Plug a replacement into the residual: rebuild from the frames
--   (siblings and provenance) with the new node in the hole.  Total:
--   the frame list is ordered nearest-first, so folding it left
--   rebuilds outward from the hole — the nearest frame wraps the new
--   node first and the root frame wraps last.  'plugForest' ignores
--   'residualSel'; the residual can ONLY be obtained from
--   'focusForest', so its frames are consistent with its coordinate by
--   construction and the replacement laws hold over the whole plug
--   domain.
plugForest :: Residual -> Forest -> Forest
plugForest (Residual (FCtx frames) _) new = foldl rebuild new frames
  where
    rebuild acc (Frame k a lft rgt) = Forest k a (lft ++ [acc] ++ rgt)

-- | Local structural admission: does the node's own provenance derive
--   it?  The node's kind must declare a production under its
--   alternative name, and that production's symbols must match the
--   children — a terminal consumes a child whose kind is the literal
--   token; a nonterminal recurses.  This is the LOCAL check (children
--   only): the residual position is not re-derived in v1.
admits :: Grammar -> Forest -> Bool
admits g (Forest k (Alt name) kids) =
  case lookup k g of
    Nothing   -> False
    Just alts -> case lookup name alts of
      Nothing   -> False
      Just syms -> matches syms kids
  where
    matches [] [] = True
    matches (Term t : ss) (Forest ck _ _ : cs) = ck == t && matches ss cs
    matches (NonTerm n : ss) (kid@(Forest ck _ _) : cs) =
      ck == n && admits g kid && matches ss cs
    matches _ _ = False

-- | The replacement report: the parse-set change a replacement induces,
--   as the replaced node's local admission plus the grammar's other
--   alternatives for its kind — the outcome is computed and reported,
--   never resolved (ambiguity preservation is this report, not a
--   choice).
data ReparseReport = ReparseReport
  { reparseKind     :: String
  , reparseAlt      :: Alt
  , reparseAdmitted :: Bool
  , reparseOther    :: [String]
  }
  deriving Eq

-- | 'ReparseReport' takes four precedence 11 arguments.
instance Show ReparseReport where
  showsPrec d (ReparseReport k a adm other) =
    showParen (d > 10)
      (  showString "ReparseReport "
      . showsPrec 11 k . showChar ' ' . showsPrec 11 a
      . showChar ' ' . showsPrec 11 adm . showChar ' ' . showsPrec 11 other
      )

-- | Compute the reparse report for the node standing at a residual's
--   selection after replacement: the node's LOCAL structural admission
--   ('admits') is computed and reported alongside the kind's other
--   alternative names, so the replacement-induced parse-set change is
--   never hidden.  The other names are listed in grammar order; the
--   admission is local to the node (the residual position is not
--   re-derived in v1), and an unknown kind admits nothing and has no
--   alternatives, so its report lists none.
reparseReport :: Grammar -> Forest -> ReparseReport
reparseReport g f@(Forest k a@(Alt name) _) =
  let alts = maybe [] (map fst) (lookup k g)
  in  ReparseReport k a (admits g f) [ other | other <- alts, other /= name ]
