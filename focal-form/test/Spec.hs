module Main (main) where

import Test.QuickCheck (Property, conjoin)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.QuickCheck (testProperty, (===))

import Focal.Form
  ( Field(..)
  , FieldResidual(..)
  , FormError(..)
  , ModelSnapshot(..)
  , PutbackResult(..)
  , WidgetPath(..)
  , nonEmpty
  , putback
  , revalidate
  , residualOf
  , residuals
  , validateForm
  )

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests = testGroup "focal-form — form putback"
  [ testGroup "Validate-then-apply"
      [ testProperty "valid edit applies by key" prop_fm_putback_ok
      , testProperty "invalid edit reports error with residual" prop_fm_putback_error
      , testProperty "the edit overwrites its key" prop_fm_putback_overwrites
      , testProperty "revalidation keeps the original provenance" prop_fm_revalidate_provenance
      , testProperty "form validation is all-or-nothing" prop_fm_validate_form_allornothing
      , testProperty "a normalizing validator's adopted value reaches the model" prop_fm_adopts_value
      , testProperty "colliding model keys are rejected" prop_fm_duplicate_key
      , testProperty "every failure is reported" prop_fm_validate_form_every_failure
      , testProperty "a collision preserves the colliding field's residual" prop_fm_residuals_duplicate
      ]
  ]

--------------------------------------------------------------------
-- Properties — form putback (the domain is finite and enumerable)
--------------------------------------------------------------------

-- | A valid field edit validates and applies to the snapshot by key:
--   the edited key is overwritten, the untouched key persists.
prop_fm_putback_ok :: Property
prop_fm_putback_ok =
  putback vs0 snap0 (Field pEmail "a@b" "email")
    === PutbackOk (ModelSnapshot [("email", "a@b"), ("user", "u")])
  where
    vs0    = [("email", nonEmpty)]
    snap0  = ModelSnapshot [("user", "u")]
    pEmail = WidgetPath ["form", "email"]

-- | An invalid field edit reports the error together with the failed
--   input's residual (the raw input a retry needs) — and nothing is
--   applied to the snapshot.
prop_fm_putback_error :: Property
prop_fm_putback_error =
  putback vs0 snap0 (Field pEmail "" "email")
    === PutbackError (FormError pEmail "empty") (residualOf (Field pEmail "" "email"))
  where
    vs0    = [("email", nonEmpty)]
    snap0  = ModelSnapshot [("user", "u")]
    pEmail = WidgetPath ["form", "email"]

-- | The edit overwrites its own model key; keys it does not mention
--   persist — here the edit is the only key, so the snapshot is just
--   the update (same ordering as 'validateForm': update, then kept).
prop_fm_putback_overwrites :: Property
prop_fm_putback_overwrites =
  putback vs0 snap0 (Field pUser "u2" "name")
    === PutbackOk (ModelSnapshot [("user", "u2")])
  where
    vs0   = [("name", nonEmpty)]
    snap0 = ModelSnapshot [("user", "u")]
    pUser = WidgetPath ["user"]

-- | Provenance survives transport: re-validating a failed input's
--   residual reports the error at the ORIGINAL path (the error follows
--   the field, not the registry).
prop_fm_revalidate_provenance :: Property
prop_fm_revalidate_provenance =
  revalidate (residualOf (Field pEmail "" "email")) vs0
    === Left (FormError pEmail "empty")
  where
    vs0    = [("email", nonEmpty)]
    pEmail = WidgetPath ["form", "email"]

-- | Validate-then-apply is all-or-nothing: one failure leaves the
--   snapshot untouched and reports every failing field's error, in
--   field order (the valid field contributes nothing).
prop_fm_validate_form_allornothing :: Property
prop_fm_validate_form_allornothing =
  validateForm vs0 snap0 [Field pEmail "" "email", Field pName "n" "name"]
    === Left [FormError pEmail "empty"]
  where
    vs0    = [("email", nonEmpty), ("name", nonEmpty)]
    snap0  = ModelSnapshot []
    pEmail = WidgetPath ["form", "email"]
    pName  = WidgetPath ["form", "name"]

-- | Adoption: a normalizing validator's value (its 'Right' result) is
--   what the model stores — the raw input never reaches the model.
--   The policy holds in both write paths: the single-field putback and
--   the all-or-nothing form validation.
prop_fm_adopts_value :: Property
prop_fm_adopts_value = conjoin
  [ putback vs0 snap0 (Field pEmail " a b " "email")
      === PutbackOk (ModelSnapshot [("email", "ab")])
  , validateForm vs0 snap0 [Field pEmail " a b " "email"]
      === Right (ModelSnapshot [("email", "ab")])
  ]
  where
    trim :: String -> Either String String
    trim s = Right (filter (/= ' ') s)

    vs0    = [("email", trim)]
    snap0  = ModelSnapshot []
    pEmail = WidgetPath ["form", "email"]

-- | Colliding model keys are rejected.  A model key is the last segment of
--   the widget path, so these two fields would write the same key; the
--   collision is a validation failure reported at the colliding field
--   (the later one, since the earlier one is the value that would apply)
--   and the snapshot is not built.  Without the check the last writer
--   would win silently, so this witness fails for that implementation.
prop_fm_duplicate_key :: Property
prop_fm_duplicate_key =
  validateForm [("id", nonEmpty)] (ModelSnapshot [])
    [ Field (WidgetPath ["a", "x"]) "1" "id"
    , Field (WidgetPath ["b", "x"]) "2" "id"
    ]
    === Left [FormError (WidgetPath ["b", "x"]) "duplicate model key: x"]

-- | EVERY failure is reported: a form with both an invalid field and a
--   duplicate model key reports the validation failure first, then the
--   collision.  An implementation that returns as soon as the
--   validation errors are known drops the collision, so this witness
--   fails for that one.
prop_fm_validate_form_every_failure :: Property
prop_fm_validate_form_every_failure =
  validateForm vs0 (ModelSnapshot [])
    [ Field pA "" "email"
    , Field pB "2" "email"
    ]
    === Left [ FormError pA "empty"
             , FormError pB "duplicate model key: x"
             ]
  where
    vs0 = [("email", nonEmpty)]
    pA  = WidgetPath ["a", "x"]
    pB  = WidgetPath ["b", "x"]

-- | A duplicate model key is a failure of the LATER field, so that
--   field's residual is preserved like any other failure's (the raw
--   input a retry needs, at the original path and kind).  An
--   implementation that collects only the validation failures returns
--   the empty list here, so this witness fails for that one.
prop_fm_residuals_duplicate :: Property
prop_fm_residuals_duplicate =
  residuals vs0 [ Field pA "1" "email", Field pB "2" "email" ]
    === [FieldResidual pB "2" "email"]
  where
    vs0 = [("email", nonEmpty)]
    pA  = WidgetPath ["a", "x"]
    pB  = WidgetPath ["b", "x"]
