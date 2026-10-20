-- | The workflow layer (v1: the transition context, the rollback plan,
--   and the validation gate).
--
--   A workflow is a labelled transition system: STATES with named
--   TRANSITIONS between them, each transition a task with a name and its
--   target state.  A RUN is the trace of transitions taken — the state
--   path.  The TRANSITION CONTEXT is what a workflow focus's residual
--   carries: the prefix already taken, the transition being replaced,
--   and the suffix still planned (the surrounding state-machine
--   context).
--
--   The ROLLBACK PLAN is the compensation span for the prefix: each
--   taken transition's compensator.  Compensation is a PREORDER, not an
--   inverse category: a compensating transition says what undoes the
--   RUN's effect, and the plan composes the compensators in REVERSE run
--   order (last taken, first compensated).  A transition without a
--   declared compensator contributes nothing and is REPORTED as
--   uncompensated, never silently dropped.
--
--   The VALIDATION GATE accepts or rejects a task replacement by
--   checking the run's state path against the workflow's transitions:
--   every step must be a declared transition (name, source, and target
--   all matching) AND consecutive steps must be chained (each step's
--   source is the previous step's target).  A run may begin in any
--   state — the workflow declares no initial state in v1.  The gate is
--   STATIC STRUCTURE ONLY — it says whether the trace is declared,
--   never whether the workflow can run, and the first offending step is
--   reported with its index.
--
--   For the PG-analogue, the replacement must carry the focused
--   transition's name ('splitRun' addresses transitions by name, first
--   occurrence wins), so that a re-split of the plugged run recovers the
--   replacement.  'plugRun' is the RAW plug and does not check this: a
--   name-changing replacement is a legitimate value but outside that
--   premise.  'workflowPlug' is the validated route — it enforces the
--   name premise AND the validation gate.
--
--   >>> import Focal.Workflow
--   >>> let wf = Workflow ["draft", "review", "done"] [Transition "submit" "draft" "review", Transition "approve" "review" "done"]
--   >>> let run = Run [Transition "submit" "draft" "review", Transition "approve" "review" "done"]
--   >>> validateGate wf run
--   GateOk
--   >>> validateGate wf (Run [Transition "submit" "draft" "review", Transition "bogus" "review" "done"])
--   GateRejected 1 (Transition "bogus" "review" "done")
--   >>> validateGate wf (Run [Transition "approve" "review" "done", Transition "submit" "draft" "review"])
--   GateRejected 1 (Transition "submit" "draft" "review")
--   >>> fmap ctxPrefix (splitRun "approve" run)
--   Just [Transition "submit" "draft" "review"]
--   >>> fmap (\ctx -> plugRun ctx (Transition "reject" "review" "draft")) (splitRun "approve" run)
--   Just (Run [Transition "submit" "draft" "review",Transition "reject" "review" "draft"])
--   >>> rollbackPlan [Compensation "submit" "reopen", Compensation "approve" "revoke"] [Transition "submit" "draft" "review", Transition "approve" "review" "done"]
--   (RollbackPlan [Compensation "approve" "revoke",Compensation "submit" "reopen"],[])
--   >>> rollbackPlan [Compensation "approve" "revoke"] [Transition "submit" "draft" "review", Transition "approve" "review" "done"]
--   (RollbackPlan [Compensation "approve" "revoke"],["submit"])
module Focal.Workflow
  ( Transition(..)
  , Workflow(..)
  , Run(..)
  , TransitionContext(..)
  , splitRun
  , plugRun
  , Compensation(..)
  , RollbackPlan(..)
  , rollbackPlan
  , lookupComp
  , GateVerdict(..)
  , validateGate
  , InvalidTransition(..)
  , workflowPlug
  ) where

--------------------------------------------------------------------
-- Transitions and workflows: the labelled transition system
--------------------------------------------------------------------

-- | A transition: a named task from one state to another.
--
--   >>> import Focal.Workflow
--   >>> Transition "submit" "draft" "review"
--   Transition "submit" "draft" "review"
data Transition = Transition
  { transName :: String
  , transFrom :: String
  , transTo   :: String
  }
  deriving Eq

-- | 'Transition' takes three precedence 11 arguments.
instance Show Transition where
  showsPrec d (Transition n f t) =
    showParen (d > 10)
      (  showString "Transition " . showsPrec 11 n . showChar ' '
      . showsPrec 11 f . showChar ' ' . showsPrec 11 t
      )

-- | A workflow: its states and its declared transitions (a labelled
--   transition system; static structure only — no liveness claims).
--
--   >>> import Focal.Workflow
--   >>> Workflow ["draft", "review"] [Transition "submit" "draft" "review"]
--   Workflow ["draft","review"] [Transition "submit" "draft" "review"]
data Workflow = Workflow
  { wfStates      :: [String]
  , wfTransitions :: [Transition]
  }
  deriving Eq

-- | 'Workflow' takes two unquoted list arguments.
instance Show Workflow where
  showsPrec d (Workflow s ts) =
    showParen (d > 10)
      (showString "Workflow " . showsPrec 11 s . showChar ' ' . showsPrec 11 ts)

-- | A run: the transitions taken, in order (the trace).
--
--   >>> import Focal.Workflow
--   >>> Run [Transition "submit" "draft" "review"]
--   Run [Transition "submit" "draft" "review"]
newtype Run = Run [Transition]
  deriving (Eq, Show)

--------------------------------------------------------------------
-- The transition context: what a workflow focus's residual carries
--------------------------------------------------------------------

-- | The transition context: what a workflow focus's residual carries —
--   the prefix already taken, the transition being replaced, and the
--   suffix still planned (the surrounding state-machine context).
--
--   >>> import Focal.Workflow
--   >>> TransitionContext [Transition "submit" "draft" "review"] (Transition "approve" "review" "done") []
--   TransitionContext [Transition "submit" "draft" "review"] (Transition "approve" "review" "done") []
data TransitionContext = TransitionContext
  { ctxPrefix :: [Transition]
  , ctxFocus  :: Transition
  , ctxSuffix :: [Transition]
  }
  deriving Eq

-- | 'TransitionContext' takes three precedence 11 arguments.
instance Show TransitionContext where
  showsPrec d (TransitionContext pre foc post) =
    showParen (d > 10)
      (  showString "TransitionContext " . showsPrec 11 pre . showChar ' '
      . showsPrec 11 foc . showChar ' ' . showsPrec 11 post
      )

-- | Split a run at its first occurrence of a transition with the given
--   name: the transition context (prefix / focus / suffix) or
--   'Nothing' when the run does not contain one (the zero-candidate
--   case for a task replacement — reported, never guessed).
--
--   >>> import Focal.Workflow
--   >>> let run = Run [Transition "submit" "draft" "review", Transition "approve" "review" "done"]
--   >>> splitRun "approve" run
--   Just (TransitionContext [Transition "submit" "draft" "review"] (Transition "approve" "review" "done") [])
--   >>> splitRun "bogus" run
--   Nothing
splitRun :: String -> Run -> Maybe TransitionContext
splitRun name (Run ts) = go [] ts
  where
    go _ [] = Nothing
    go pre (t : post)
      | transName t == name = Just (TransitionContext pre t post)
      | otherwise           = go (pre ++ [t]) post

-- | Plug a replacement into the context: the run rebuilt with the focus
--   replaced (the prefix and suffix are untouched).
--
--   For the PG-analogue to hold the replacement must carry the focused
--   transition's name: 'splitRun' addresses transitions by name (first
--   occurrence wins), so a name-changing replacement re-splits at a
--   different transition.  A name-changing replacement is a legitimate
--   value but outside that premise; 'workflowPlug' is the validated
--   route.
--
--   >>> import Focal.Workflow
--   >>> let ctx = TransitionContext [Transition "submit" "draft" "review"] (Transition "approve" "review" "done") []
--   >>> plugRun ctx (Transition "reject" "review" "draft")
--   Run [Transition "submit" "draft" "review",Transition "reject" "review" "draft"]
plugRun :: TransitionContext -> Transition -> Run
plugRun ctx t = Run (ctxPrefix ctx ++ [t] ++ ctxSuffix ctx)

--------------------------------------------------------------------
-- The rollback plan: the compensation span of a prefix
--------------------------------------------------------------------

-- | A compensation: what undoes a taken transition's effect (a name —
--   a preorder, not an inverse: compensation says what undoes the
--   effect, not what reverses the transition).
--
--   >>> import Focal.Workflow
--   >>> Compensation "submit" "reopen"
--   Compensation "submit" "reopen"
data Compensation = Compensation
  { compFor   :: String   -- ^ the transition it compensates (by name)
  , compName  :: String   -- ^ the compensating task (by name)
  }
  deriving Eq

-- | 'Compensation' takes two precedence 11 arguments.
instance Show Compensation where
  showsPrec d (Compensation f n) =
    showParen (d > 10)
      (showString "Compensation " . showsPrec 11 f . showChar ' ' . showsPrec 11 n)

-- | A rollback plan: the compensators for a prefix, in REVERSE run
--   order (last taken, first compensated — the span composition).
--
--   >>> import Focal.Workflow
--   >>> RollbackPlan [Compensation "submit" "reopen"]
--   RollbackPlan [Compensation "submit" "reopen"]
newtype RollbackPlan = RollbackPlan [Compensation]
  deriving (Eq, Show)

-- | Plan the rollback of a prefix: every taken transition's declared
--   compensator, in reverse order; a transition without a declared
--   compensator contributes nothing and is reported as uncompensated.
--
--   >>> import Focal.Workflow
--   >>> rollbackPlan [Compensation "submit" "reopen", Compensation "approve" "revoke"] [Transition "submit" "draft" "review", Transition "approve" "review" "done"]
--   (RollbackPlan [Compensation "approve" "revoke",Compensation "submit" "reopen"],[])
--   >>> rollbackPlan [Compensation "approve" "revoke"] [Transition "submit" "draft" "review", Transition "approve" "review" "done"]
--   (RollbackPlan [Compensation "approve" "revoke"],["submit"])
--   >>> rollbackPlan [] []
--   (RollbackPlan [],[])
rollbackPlan :: [Compensation] -> [Transition] -> (RollbackPlan, [String])
rollbackPlan comps prefix = go [] [] (reverse prefix)
  where
    go acc missing [] = (RollbackPlan (reverse acc), reverse missing)
    go acc missing (t : rest) =
      case lookupComp (transName t) comps of
        Nothing -> go acc (transName t : missing) rest
        Just c  -> go (c : acc) missing rest

-- | The declared compensator for a transition name, if any.
--
--   >>> import Focal.Workflow
--   >>> lookupComp "approve" [Compensation "submit" "reopen", Compensation "approve" "revoke"]
--   Just (Compensation "approve" "revoke")
--   >>> lookupComp "bogus" [Compensation "submit" "reopen"]
--   Nothing
lookupComp :: String -> [Compensation] -> Maybe Compensation
lookupComp _ [] = Nothing
lookupComp n (c : cs)
  | compFor c == n = Just c
  | otherwise      = lookupComp n cs

--------------------------------------------------------------------
-- The validation gate: accepting a run against the declared transitions
--------------------------------------------------------------------

-- | The validation verdict of the gate: the first step that does not
--   correspond to a declared transition of the workflow, if any (the
--   gate accepts a run exactly when every step is declared and
--   consecutive steps are chained; static structure only).
--
--   >>> import Focal.Workflow
--   >>> GateOk
--   GateOk
--   >>> GateRejected 1 (Transition "bogus" "review" "done")
--   GateRejected 1 (Transition "bogus" "review" "done")
data GateVerdict
  = GateOk
  | GateRejected Int Transition   -- ^ the step index and the offending transition
  deriving (Eq, Show)

-- | Run the validation gate: a run is accepted when every transition is
--   declared (name, source, and target all matching) AND consecutive
--   transitions are chained (each step's source is the previous step's
--   target).  A run may begin in any state — the workflow declares no
--   initial state in v1.  The first offending step is reported with its
--   index (never silently dropped).
--
--   >>> import Focal.Workflow
--   >>> let wf = Workflow ["draft", "review", "done"] [Transition "submit" "draft" "review", Transition "approve" "review" "done"]
--   >>> validateGate wf (Run [Transition "submit" "draft" "review", Transition "approve" "review" "done"])
--   GateOk
--   >>> validateGate wf (Run [Transition "submit" "draft" "review", Transition "bogus" "review" "done"])
--   GateRejected 1 (Transition "bogus" "review" "done")
--   >>> validateGate wf (Run [])
--   GateOk
--   >>> validateGate wf (Run [Transition "draft" "done" "review"])
--   GateRejected 0 (Transition "draft" "done" "review")
validateGate :: Workflow -> Run -> GateVerdict
validateGate wf (Run ts) = go 0 Nothing ts
  where
    go _ _ [] = GateOk
    go i prev (t : rest)
      | declared t && chained prev t = go (i + 1) (Just t) rest
      | otherwise                    = GateRejected i t
    declared t = elem t (wfTransitions wf)
    chained Nothing  _ = True
    chained (Just p) t = transTo p == transFrom t

--------------------------------------------------------------------
-- The workflow plug: replacing the current task of a context
--------------------------------------------------------------------

-- | The rejection of a task replacement: which step of the proposed
--   run is invalid, and the transition standing there (the gate's
--   report, never a silent drop).
--
--   >>> import Focal.Workflow
--   >>> InvalidTransition 0 (Transition "rework" "review" "draft")
--   InvalidTransition 0 (Transition "rework" "review" "draft")
data InvalidTransition = InvalidTransition
  { invalidStep  :: Int
  , invalidTrans :: Transition
  }
  deriving Eq

-- | 'InvalidTransition' takes two precedence 11 arguments.
instance Show InvalidTransition where
  showsPrec d (InvalidTransition i t) =
    showParen (d > 10)
      (showString "InvalidTransition " . showsPrec 11 i . showChar ' ' . showsPrec 11 t)

-- | Replace the current task of a context: the proposed run (the
--   context with the replacement plugged in) is accepted only when the
--   replacement carries the FOCUSED transition's name AND the validation
--   gate accepts the proposed run.  The name premise comes first: it is
--   the premise the PG-analogue needs, because 'splitRun' addresses
--   transitions by name (first occurrence wins), so a replacement under
--   another name is not the transition the split names.  A
--   name-changing replacement is rejected at the focus's index (the
--   length of the context's prefix) with the offered transition; an
--   invalid run reports the offending step.  Either way the context is
--   left untouched.
--
--   >>> import Focal.Workflow
--   >>> let wf = Workflow ["draft", "review", "done"] [Transition "submit" "draft" "review", Transition "approve" "review" "done"]
--   >>> let ctx = TransitionContext [] (Transition "submit" "draft" "review") [Transition "approve" "review" "done"]
--   >>> workflowPlug wf ctx (Transition "submit" "draft" "review")
--   Right (Run [Transition "submit" "draft" "review",Transition "approve" "review" "done"])
--   >>> workflowPlug wf ctx (Transition "rework" "review" "draft")
--   Left (InvalidTransition 0 (Transition "rework" "review" "draft"))
--   >>> let ctx2 = TransitionContext [Transition "submit" "draft" "review"] (Transition "approve" "review" "done") []
--   >>> workflowPlug wf ctx2 (Transition "rework" "review" "draft")
--   Left (InvalidTransition 1 (Transition "rework" "review" "draft"))
workflowPlug :: Workflow -> TransitionContext -> Transition
             -> Either InvalidTransition Run
workflowPlug wf ctx new
  | transName new /= transName (ctxFocus ctx) =
      Left (InvalidTransition (length (ctxPrefix ctx)) new)
  | otherwise =
      let run = plugRun ctx new
       in case validateGate wf run of
            GateOk           -> Right run
            GateRejected i t -> Left (InvalidTransition i t)
