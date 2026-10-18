-- | The form layer over the patch layer (v1: string-keyed model).
--
--   A form is a list of fields; each field has a widget path (its
--   position in the form tree, root to leaf), a raw string value, and a
--   validator kind.  Validation runs against a registry of per-kind
--   validators ('Validators'); the FIELD supplies the provenance — a
--   validator reports only a message, and 'validateField' attaches the
--   field's widget path at the boundary, so every 'FormError' names
--   where it came from.  The model snapshot ('ModelSnapshot') is what a
--   delta would patch: validate-then-apply is all-or-nothing — any
--   failure leaves the snapshot untouched and reports EVERY failure
--   ('validateForm'); applied fields overwrite their model key and keys
--   the form does not mention persist (re-validation preserves the rest
--   of the model).  The field residual ('FieldResidual') is what a
--   failed validation preserves — the raw input plus the ORIGINAL path
--   and kind, so the error is reproducible and the user's input is never
--   lost; 'revalidate' re-runs a residual against a different registry
--   (the form moved) and the provenance follows the field, not the
--   registry ('residuals' collects every failure's residual — the raw
--   inputs a retry would need).
--
--   >>> import Focal.Form
--   >>> pathString (WidgetPath ["form", "email"])
--   "form/email"
--   >>> fieldKey (Field (WidgetPath ["form", "email"]) "x" "email")
--   "email"
--   >>> validateField [("email", nonEmpty)] (Field (WidgetPath ["form", "email"]) "" "email")
--   Left (FormError form/email "empty")
--   >>> validateField [("email", nonEmpty)] (Field (WidgetPath ["form", "email"]) "a@b" "email")
--   Right "a@b"
--   >>> validateField [("email", nonEmpty)] (Field (WidgetPath ["f", "x"]) "" "phone")
--   Left (FormError f/x "unknown field kind: phone")
--   >>> revalidate (residualOf (Field (WidgetPath ["form", "email"]) "" "email")) [("email", nonEmpty)]
--   Left (FormError form/email "empty")
--   >>> validateForm [("email", nonEmpty)] (ModelSnapshot [("user", "u")]) [Field (WidgetPath ["form", "email"]) "a@b" "email"]
--   Right (ModelSnapshot [("email","a@b"),("user","u")])
--   >>> validateForm [("email", nonEmpty)] (ModelSnapshot [("user", "u")]) [Field (WidgetPath ["form", "email"]) "" "email", Field (WidgetPath ["form", "name"]) "n" "nonempty"]
--   Left [FormError form/email "empty",FormError form/name "unknown field kind: nonempty"]
module Focal.Form
  ( WidgetPath(..)
  , pathString
  , FormError(..)
  , Field(..)
  , Validators
  , validateField
  , ModelSnapshot(..)
  , FieldResidual(..)
  , residualOf
  , revalidate
  , validateForm
  , fieldKey
  , residuals
  , nonEmpty
  ) where

import Data.List (intercalate)

--------------------------------------------------------------------
-- Widget paths
--------------------------------------------------------------------

-- | A widget path: the field's position in the form tree, root to leaf.
newtype WidgetPath = WidgetPath [String]
  deriving Eq

-- | The slash-joined path.
pathString :: WidgetPath -> String
pathString (WidgetPath ss) = intercalate "/" ss

-- | Show as the slash-joined path.
instance Show WidgetPath where
  showsPrec _ = showString . pathString

--------------------------------------------------------------------
-- Errors with provenance
--------------------------------------------------------------------

-- | A validation error with its provenance: the widget path and the
--   message.
data FormError = FormError WidgetPath String
  deriving Eq

-- | 'FormError' takes two unquoted arguments: the path and the message.
instance Show FormError where
  showsPrec d (FormError p msg) =
    showParen (d > 10)
      (showString "FormError " . showsPrec 11 p . showChar ' ' . shows msg)

--------------------------------------------------------------------
-- Fields
--------------------------------------------------------------------

-- | A field: its widget path, the raw input, and the validator key.
data Field = Field
  { fieldPath  :: WidgetPath
  , fieldRaw   :: String
  , fieldKind  :: String
  }
  deriving Eq

-- | 'Field' takes three unquoted arguments.
instance Show Field where
  showsPrec d (Field p raw kind) =
    showParen (d > 10)
      (  showString "Field "
      . showsPrec 11 p . showChar ' ' . shows raw . showChar ' ' . shows kind
      )

-- | The validation context: the per-kind validators in force (the
--   registry a form's fields are checked against).  A validator reports
--   only a message on failure — the path is the field's business.
type Validators = [(String, String -> Either String String)]

-- | Validate one field: look up its kind, run the validator; an
--   unknown kind is a provenance-carrying error at the field's path.
--   The FIELD supplies the path (provenance at the boundary).
validateField :: Validators -> Field -> Either FormError String
validateField vs (Field p raw kind) =
  case lookup kind vs of
    Nothing -> Left (FormError p ("unknown field kind: " ++ kind))
    Just v  -> either (Left . FormError p) Right (v raw)

--------------------------------------------------------------------
-- Model snapshots
--------------------------------------------------------------------

-- | A model snapshot: the field values at validation time (v1: an
--   association list; the snapshot is what a delta would patch).
newtype ModelSnapshot = ModelSnapshot [(String, String)]
  deriving Eq

instance Show ModelSnapshot where
  showsPrec d (ModelSnapshot kvs) =
    showParen (d > 10) (showString "ModelSnapshot " . shows kvs)

-- | The model key of a field: the last segment of its widget path.
fieldKey :: Field -> String
fieldKey (Field (WidgetPath ps) _ _) = case reverse ps of
  (name : _) -> name
  []         -> ""

--------------------------------------------------------------------
-- Validate-then-apply
--------------------------------------------------------------------

-- | Validate-then-apply: every field must validate (all-or-nothing);
--   failures report every error and leave the snapshot untouched.
--   Applied fields overwrite their model key; untouched keys persist
--   (re-validation preserves the rest of the model).
validateForm :: Validators -> ModelSnapshot -> [Field] -> Either [FormError] ModelSnapshot
validateForm vs (ModelSnapshot kvs) fields =
  case [ e | f <- fields, Left e <- [validateField vs f] ] of
    errs@(_ : _) -> Left errs
    []           ->
      let updates = [ (fieldKey f, fieldRaw f) | f <- fields ]
          kept    = [ kv | kv@(k, _) <- kvs, k `notElem` map fst updates ]
      in  Right (ModelSnapshot (updates ++ kept))

--------------------------------------------------------------------
-- Field residuals
--------------------------------------------------------------------

-- | The field residual: what a failed validation preserves — the raw
--   input, its path, and its kind, so the error is reproducible and the
--   user's input is never lost.
data FieldResidual = FieldResidual
  { residualPath :: WidgetPath
  , residualRaw  :: String
  , residualKind :: String
  }
  deriving Eq

-- | 'FieldResidual' takes three unquoted arguments.
instance Show FieldResidual where
  showsPrec d (FieldResidual p raw kind) =
    showParen (d > 10)
      (  showString "FieldResidual "
      . showsPrec 11 p . showChar ' ' . shows raw . showChar ' ' . shows kind
      )

-- | The residual of a failed field validation.
residualOf :: Field -> FieldResidual
residualOf (Field p raw kind) = FieldResidual p raw kind

-- | Re-validation on transport: re-run a residual against a registry —
--   the provenance is the ORIGINAL path (the error follows the field).
revalidate :: FieldResidual -> Validators -> Either FormError String
revalidate (FieldResidual p raw kind) vs =
  case lookup kind vs of
    Nothing -> Left (FormError p ("unknown field kind: " ++ kind))
    Just v  -> either (Left . FormError p) Right (v raw)

-- | Every failure's residual (the raw inputs a retry would need).
residuals :: Validators -> [Field] -> [FieldResidual]
residuals vs fields = [ residualOf f | f <- fields, isFailure f ]
  where
    isFailure f = case validateField vs f of
      Left _  -> True
      Right _ -> False

--------------------------------------------------------------------
-- The example validator
--------------------------------------------------------------------

-- | The demo validator used in the examples: rejects the empty string.
nonEmpty :: String -> Either String String
nonEmpty "" = Left "empty"
nonEmpty s  = Right s
