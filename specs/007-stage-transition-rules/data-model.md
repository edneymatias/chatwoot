# Data Model: Stage Transition Rules

## Opportunity (extended)

Existing model: `custom/app/models/opportunity.rb`, table `matias_opportunities`.

**New columns**:

| Column | Type | Default | Notes |
|---|---|---|---|
| `custom_attributes` | `jsonb` | `{}` | Keyed by `CustomAttributeDefinition#attribute_key` for `opportunity_attribute`-model definitions, mirroring the existing jsonb custom-attribute pattern used elsewhere in Chatwoot (e.g. `Conversation#custom_attributes`) |
| `value` | `decimal` | `nil` | The deal value; a first-class column, not a custom attribute |

**New validation** (FR-005/FR-006 of spec):

- Runs `on: :update`, `if: :pipeline_stage_id_changed?`.
- Loads `pipeline_stage_id_was`'s `position` and the new `pipeline_stage_id`'s `position`.
- If new position is **not** strictly greater than the old position (backward/lateral move): skip
  entirely, no validation.
- If new position **is** strictly greater (forward move): for each `PipelineStageRequiredField` on
  the destination stage, check `custom_attributes[definition.attribute_key]` has been explicitly
  set (key present in the hash — see "field presence" rule below); if `requires_deal_value` is
  true on the destination stage, check `value` has been explicitly set. Any that are unset add a
  structured error and populate an accessor (e.g. `missing_required_fields`) the controller reads
  to build the `422` body.

**Field presence rule** (per Clarifications session 2026-08-01): a field counts as set once the
key is present with any explicitly-assigned value, including falsy/zero-like ones (`false` for a
checkbox, `0` for a numeric/deal-value field). Only a field whose key was never written counts as
missing.

## PipelineStage (extended)

Existing model: `custom/app/models/pipeline_stage.rb`, table `matias_pipeline_stages`.

**New column**:

| Column | Type | Default | Notes |
|---|---|---|---|
| `requires_deal_value` | `boolean` | `false` | At most one stage per account may have this `true` |

**New association**: `has_many :pipeline_stage_required_fields, dependent: :destroy` and
`has_many :required_custom_attribute_definitions, through: :pipeline_stage_required_fields, source: :custom_attribute_definition`.

**New callback**: `before_save` — when `requires_deal_value` is being set to `true`, update every
other stage in the same account with `requires_deal_value: false` (single-lane exclusivity, FR-002
of spec).

## PipelineStageRequiredField (new)

New model: `custom/app/models/pipeline_stage_required_field.rb`, table
`matias_pipeline_stage_required_fields`.

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | PK |
| `account_id` | bigint | FK, not null |
| `pipeline_stage_id` | bigint | FK, not null |
| `custom_attribute_definition_id` | bigint | FK, not null |
| `created_at` / `updated_at` | timestamps | |

**Indexes**: unique index on `(account_id, custom_attribute_definition_id)` — enforces "a field is
required by at most one stage at a time" (FR-003).

**Associations**: `belongs_to :account`, `belongs_to :pipeline_stage`, `belongs_to :custom_attribute_definition`.

**Validations**: presence of all three associations; validates that
`custom_attribute_definition.attribute_model == 'opportunity_attribute'` (rejects assigning a
conversation/contact/company-model attribute as a stage requirement).

## CustomAttributeDefinition (extended — core file)

Existing model: `app/models/custom_attribute_definition.rb`.

**Change**: `enum attribute_model` gains a fourth member: `opportunity_attribute: 3`. No other
change to this model. Existing `STANDARD_ATTRIBUTES` conflict-check map has no `:opportunity` key,
so `attribute_must_not_conflict` naturally short-circuits (`standard_attributes.blank?`) for this
new model — no edit needed there.

## State / lifecycle notes

- No new state machine is introduced. `Opportunity#status` (`open`/`won`/`lost`) is unaffected by
  this feature; stage-transition validation is orthogonal to status.
- A `PipelineStageRequiredField` row's lifecycle is: created (assign), optionally deleted
  (unassign via `destroy`), or implicitly deleted-then-recreated-elsewhere when the same
  `custom_attribute_definition_id` is reassigned to a different stage (the "steals it" semantics —
  see research.md §2).
- Deleting a `PipelineStage` cascades `dependent: :destroy` to its `PipelineStageRequiredField`
  rows (mirrors the existing `has_many :opportunities, dependent: :restrict_with_error` pattern on
  `PipelineStage`, but `:destroy` here since required-field rows are pure configuration, not data
  that should block stage deletion).
