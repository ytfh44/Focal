-- | The query layer (v1: projection provenance, the join witness, and
--   the view-update policy).
--
--   A table is a schema (column names) plus rows (string-keyed
--   associations; v1 keeps rows as association lists).  A projection is
--   the column selection the view keeps, and the view is the projected
--   rows: every view row carries its PROVENANCE — which source row it
--   came from (the row-identity tag in v1 is the source row index) — in
--   the row itself, so a projected row can always be traced back and the
--   tag is never hidden.
--
--   A join extends the view by one equality join against a lookup
--   relation (a key column, a value column, and rows).  A view row whose
--   key column matches gains the lookup's value column, and its JOIN
--   WITNESS records the pair (the table row it came from, the lookup row
--   it joined with); the lookup side is absent — 'Nothing', never a
--   sentinel index — when the row did not match.  The rows a join does
--   not match are its COMPLEMENT: they pass through unchanged, with no
--   value column and no witness.  The FIRST matching lookup row wins,
--   and v1 keeps a single witness slot, so the slot describes the join
--   just performed.
--
--   A view edit is put back through a POLICY: an ordered preference over
--   candidate repairs, where a candidate is a column and the value to
--   write there.  A policy produces candidates and never chooses for the
--   caller — 'putbackRow' applies it: exactly one candidate applies, and
--   zero or several are reported as 'AmbiguousPutback' with every
--   candidate in policy order (the empty list when the policy offers no
--   repair at all).  Ambiguity is REPORTED, never silently resolved.
--
--   >>> import Focal.Query
--   >>> let t = Table ["id", "name"] [[("id", "1"), ("name", "a")], [("id", "2")]]
--   >>> project (Projection ["name"]) t
--   View [ViewRow [("name","a")] 0 (JoinWitness 0 Nothing),ViewRow [] 1 (JoinWitness 1 Nothing)]
--   >>> joinView (Lookup "id" "tag" [("1", "x")]) (project (Projection ["id"]) t)
--   View [ViewRow [("id","1"),("tag","x")] 0 (JoinWitness 0 (Just 0)),ViewRow [("id","2")] 1 (JoinWitness 1 Nothing)]
--   >>> putbackRow writeBack t "name" "z"
--   PutbackOk (Candidate "name" "z")
--   >>> putbackRow (fixedPolicy [Candidate "name" "z", Candidate "id" "9"]) t "name" "z"
--   AmbiguousPutback [Candidate "name" "z",Candidate "id" "9"]
module Focal.Query
  ( Table(..)
  , Projection(..)
  , ViewRow(..)
  , View(..)
  , project
  , JoinWitness(..)
  , Lookup(..)
  , joinView
  , Candidate(..)
  , Policy
  , Putback(..)
  , putbackRow
  , RelDelta(..)
  , relPutback
  , fixedPolicy
  , writeBack
  ) where

--------------------------------------------------------------------
-- Tables, projections, and the projected rows with provenance
--------------------------------------------------------------------

-- | A table: a schema (column names) and rows (string-keyed
--   associations).  v1 keeps rows as association lists.
--
--   >>> import Focal.Query
--   >>> Table ["id", "name"] [[("id", "1"), ("name", "a")], [("id", "2")]]
--   Table ["id","name"] [[("id","1"),("name","a")],[("id","2")]]
data Table = Table
  { tableSchema :: [String]
  , tableRows   :: [[(String, String)]]
  }
  deriving Eq

-- | 'Table' takes two unquoted list arguments.
instance Show Table where
  showsPrec d (Table s r) =
    showParen (d > 10)
      (showString "Table " . showsPrec 11 s . showChar ' ' . showsPrec 11 r)

-- | A projection: the columns the view keeps, in the projection's own
--   order.
--
--   >>> import Focal.Query
--   >>> Projection ["name", "id"]
--   Projection ["name","id"]
newtype Projection = Projection [String]
  deriving (Eq, Show)

-- | A view row: the projected values plus the provenance of the source
--   row it came from (the row index) and the row's join-witness slot —
--   empty until a join records the lookup row (see 'JoinWitness').
data ViewRow = ViewRow
  { viewValues  :: [(String, String)]
  , viewSource  :: Int
  , viewWitness :: JoinWitness
  }
  deriving Eq

-- | 'ViewRow' takes three precedence 11 arguments.
instance Show ViewRow where
  showsPrec d (ViewRow v s w) =
    showParen (d > 10)
      (  showString "ViewRow " . showsPrec 11 v . showChar ' '
      . showsPrec 11 s . showChar ' ' . showsPrec 11 w
      )

-- | A view: the projected rows, each with its provenance.
--
--   >>> import Focal.Query
--   >>> View [ViewRow [("name", "a")] 0 (JoinWitness 0 Nothing)]
--   View [ViewRow [("name","a")] 0 (JoinWitness 0 Nothing)]
newtype View = View [ViewRow]
  deriving (Eq, Show)

-- | Project a table: keep the projection's columns, each as often as the
--   projection names it, in the projection's own order; a column the row
--   lacks is skipped, and the source index travels as the row's
--   provenance (the witness slot starts empty).
--
--   >>> import Focal.Query
--   >>> let t = Table ["id", "name"] [[("id", "1"), ("name", "a")], [("id", "2")]]
--   >>> project (Projection ["name", "id"]) t
--   View [ViewRow [("name","a"),("id","1")] 0 (JoinWitness 0 Nothing),ViewRow [("id","2")] 1 (JoinWitness 1 Nothing)]
--   >>> project (Projection ["id", "id"]) t
--   View [ViewRow [("id","1"),("id","1")] 0 (JoinWitness 0 Nothing),ViewRow [("id","2"),("id","2")] 1 (JoinWitness 1 Nothing)]
--   >>> project (Projection []) t
--   View [ViewRow [] 0 (JoinWitness 0 Nothing),ViewRow [] 1 (JoinWitness 1 Nothing)]
project :: Projection -> Table -> View
project (Projection cols) (Table _ rows) =
  View [ ViewRow [ (c, v) | c <- cols, Just v <- [lookup c r] ] i (JoinWitness i Nothing)
       | (i, r) <- zip [0..] rows ]

--------------------------------------------------------------------
-- Joins: the lookup relation and the witness
--------------------------------------------------------------------

-- | The join witness: a view row built from two source rows — the table
--   row it came from and the lookup row it joined with.  The lookup side
--   is absent (never a sentinel index) when the join did not match; the
--   table side repeats the row's own provenance so a witness reads on
--   its own.
--
--   >>> import Focal.Query
--   >>> JoinWitness 2 (Just 0)
--   JoinWitness 2 (Just 0)
data JoinWitness = JoinWitness
  { witnessTable  :: Int
  , witnessLookup :: Maybe Int
  }
  deriving Eq

-- | 'JoinWitness' takes two precedence 11 arguments.
instance Show JoinWitness where
  showsPrec d (JoinWitness t l) =
    showParen (d > 10)
      (showString "JoinWitness " . showsPrec 11 t . showChar ' ' . showsPrec 11 l)

-- | A lookup relation: a key column, a value column, and rows (v1 keeps
--   the rows as association lists).
--
--   >>> import Focal.Query
--   >>> Lookup "id" "tag" [("1", "x")]
--   Lookup "id" "tag" [("1","x")]
data Lookup = Lookup
  { lookupKey   :: String
  , lookupValue :: String
  , lookupRows  :: [(String, String)]
  }
  deriving Eq

-- | 'Lookup' takes three precedence 11 arguments.
instance Show Lookup where
  showsPrec d (Lookup k v r) =
    showParen (d > 10)
      (  showString "Lookup " . showsPrec 11 k . showChar ' '
      . showsPrec 11 v . showChar ' ' . showsPrec 11 r
      )

-- | Extend a view by an equality join against a lookup relation: a view
--   row whose key column ('lookupKey' names it) matches gains the
--   lookup's value column, and its witness records the lookup row joined
--   in.  The FIRST matching lookup row wins; the rows without a match —
--   the join's COMPLEMENT — pass through unchanged, gaining no column
--   and no witness.  v1 keeps one witness slot, so the slot describes
--   the join just performed: a join that does not match leaves it empty.
--
--   >>> import Focal.Query
--   >>> let t = Table ["id", "name"] [[("id", "1"), ("name", "a")], [("id", "2")]]
--   >>> joinView (Lookup "id" "tag" [("1", "x")]) (project (Projection ["id"]) t)
--   View [ViewRow [("id","1"),("tag","x")] 0 (JoinWitness 0 (Just 0)),ViewRow [("id","2")] 1 (JoinWitness 1 Nothing)]
--   >>> joinView (Lookup "id" "tag" [("2", "y"), ("2", "z")]) (View [ViewRow [("id", "2")] 1 (JoinWitness 1 Nothing)])
--   View [ViewRow [("id","2"),("tag","y")] 1 (JoinWitness 1 (Just 0))]
--   >>> joinView (Lookup "id" "tag" [("1", "x")]) (View [ViewRow [("name", "a")] 0 (JoinWitness 0 Nothing)])
--   View [ViewRow [("name","a")] 0 (JoinWitness 0 Nothing)]
joinView :: Lookup -> View -> View
joinView lk (View rows) = View (map one rows)
  where
    one (ViewRow vals src (JoinWitness tRow _)) =
      case lookup (lookupKey lk) vals of
        Nothing -> ViewRow vals src (JoinWitness tRow Nothing)
        Just kv -> case firstMatch kv (zip [0..] (lookupRows lk)) of
          Nothing       -> ViewRow vals src (JoinWitness tRow Nothing)
          Just (li, lv) -> ViewRow (vals ++ [(lookupValue lk, lv)]) src (JoinWitness tRow (Just li))

    -- The first lookup row whose key equals the row's key value (the
    -- lookup rows keep their positions, so the witness carries the
    -- position of the row that won).
    firstMatch _  []                       = Nothing
    firstMatch kv ((li, (k, v)) : rest)
      | k == kv   = Just (li, v)
      | otherwise = firstMatch kv rest

--------------------------------------------------------------------
-- View updates: candidates, the policy, and the putback report
--------------------------------------------------------------------

-- | A candidate repair: the column to write and the value to write
--   there.
--
--   >>> import Focal.Query
--   >>> Candidate "name" "z"
--   Candidate "name" "z"
data Candidate = Candidate
  { candColumn :: String
  , candValue  :: String
  }
  deriving Eq

-- | 'Candidate' takes two precedence 11 arguments.
instance Show Candidate where
  showsPrec d (Candidate c v) =
    showParen (d > 10)
      (showString "Candidate " . showsPrec 11 c . showChar ' ' . showsPrec 11 v)

-- | A view-update policy: for a table and a view edit (the edited column
--   and the new value), the candidate repairs in PREFERENCE ORDER.  A
--   policy produces candidates — it never chooses for the caller;
--   'putbackRow' is what reports the choice.
type Policy = Table -> String -> String -> [Candidate]

-- | The putback result: the one repair that applies, or the ambiguity
--   report — every candidate in policy order, the list empty when the
--   policy offers no repair, i.e. the edit cannot be placed at all.
data Putback
  = PutbackOk Candidate
  | AmbiguousPutback [Candidate]
  deriving (Eq, Show)

-- | Put a view edit back under a policy: exactly one candidate applies;
--   zero or several are reported as 'AmbiguousPutback' — every candidate
--   in policy order, the empty list when the policy offers none.
--   Ambiguity is reported, never silently resolved.  The policy's
--   candidate list is the plug domain, and the verdicts are relative to
--   that policy by construction.
--
--   >>> import Focal.Query
--   >>> let t = Table ["id", "name"] [[("id", "1"), ("name", "a")]]
--   >>> putbackRow writeBack t "name" "z"
--   PutbackOk (Candidate "name" "z")
--   >>> putbackRow (fixedPolicy [Candidate "name" "z"]) t "name" "z"
--   PutbackOk (Candidate "name" "z")
--   >>> putbackRow (fixedPolicy [Candidate "name" "z", Candidate "id" "9"]) t "name" "z"
--   AmbiguousPutback [Candidate "name" "z",Candidate "id" "9"]
--   >>> putbackRow (fixedPolicy []) t "name" "z"
--   AmbiguousPutback []
putbackRow :: Policy -> Table -> String -> String -> Putback
putbackRow policy tbl col new = case policy tbl col new of
  []  -> AmbiguousPutback []
  [c] -> PutbackOk c
  cs  -> AmbiguousPutback cs

-- | The fixed policy: the candidates in the given order, whatever the
--   table and the edit (the ordered preference made literal).
--
--   >>> import Focal.Query
--   >>> fixedPolicy [Candidate "name" "z"] (Table [] []) "name" "z"
--   [Candidate "name" "z"]
fixedPolicy :: [Candidate] -> Policy
fixedPolicy cs _ _ _ = cs

-- | The straightforward policy: write the new value to the edited column
--   itself.
--
--   >>> import Focal.Query
--   >>> writeBack (Table [] []) "name" "z"
--   [Candidate "name" "z"]
writeBack :: Policy
writeBack _ col new = [Candidate col new]

--------------------------------------------------------------------
-- Relational putback: the delta and its provenance
--------------------------------------------------------------------

-- | A relational delta: which source row changed, which column, and the
--   new value (the provenance of the edit, relation-level).
--
--   >>> import Focal.Query
--   >>> RelDelta 0 "name" "z"
--   RelDelta 0 "name" "z"
data RelDelta = RelDelta
  { deltaRow    :: Int
  , deltaColumn :: String
  , deltaValue  :: String
  }
  deriving Eq

-- | 'RelDelta' takes three precedence 11 arguments.
instance Show RelDelta where
  showsPrec d (RelDelta r c v) =
    showParen (d > 10)
      (  showString "RelDelta " . showsPrec 11 r . showChar ' '
      . showsPrec 11 c . showChar ' ' . showsPrec 11 v
      )

-- | Relational putback: place a view-row edit through the policy.  A
--   single candidate becomes the relation-level delta (at the row whose
--   provenance the view row carries); zero or several candidates report
--   the ambiguity with the full ordered list (never resolved).
--
--   >>> import Focal.Query
--   >>> let t = Table ["id", "name"] [[("id", "1"), ("name", "a")]]
--   >>> let vr = case project (Projection ["name"]) t of { View (r : _) -> r; View [] -> ViewRow [] 0 (JoinWitness 0 Nothing) }
--   >>> relPutback writeBack t vr "name" "z"
--   Right (RelDelta 0 "name" "z")
--   >>> relPutback (fixedPolicy [Candidate "name" "z", Candidate "id" "9"]) t vr "name" "z"
--   Left [Candidate "name" "z",Candidate "id" "9"]
--   >>> relPutback (fixedPolicy []) t vr "name" "z"
--   Left []
relPutback :: Policy -> Table -> ViewRow -> String -> String
           -> Either [Candidate] RelDelta
relPutback policy tbl vr col new =
  case policy tbl col new of
    [c] -> Right (RelDelta (viewSource vr) (candColumn c) (candValue c))
    cs  -> Left cs
