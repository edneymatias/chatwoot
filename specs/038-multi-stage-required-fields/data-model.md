# Phase 1 Data Model: Multi-Stage Required Fields

No new entities are introduced. One existing entity's uniqueness rule changes.

## PipelineStageRequiredField

Table: `ichatr_pipeline_stage_required_fields` (fork-prefixed, unchanged)

| Field | Type | Notes |
|---|---|---|
| `id` | bigint | primary key |
| `account_id` | bigint | required, FK to `accounts` |
| `pipeline_stage_id` | bigint | required, FK to `ichatr_pipeline_stages` |
| `custom_attribute_definition_id` | bigint | required, FK to `custom_attribute_definitions` |
| `created_at` / `updated_at` | datetime | standard timestamps |

### Relationships (unchanged)

- `belongs_to :account`
- `belongs_to :pipeline_stage`
- `belongs_to :custom_attribute_definition`

### Uniqueness rule (changed)

- **Before**: `(account_id, custom_attribute_definition_id)` unique — an attribute could be
  required by at most one stage per account.
- **After**: `(account_id, pipeline_stage_id, custom_attribute_definition_id)` unique — an
  attribute may be required by multiple stages in the same account, but not twice on the same
  stage.

Enforced at two layers, both updated together:
- DB unique index (replaces `idx_ichatr_pipeline_stage_req_fields_on_acc_and_attr_def`).
- Model validation: `validates :custom_attribute_definition_id, uniqueness: { scope: [:account_id, :pipeline_stage_id], message: ... }`.

### Other validations (unchanged)

- `account`, `pipeline_stage`, `custom_attribute_definition` presence.
- `custom_attribute_definition.opportunity_attribute?` must be true (`definition_must_be_opportunity_attribute`).

### Write-path behavior (changed)

Both write paths currently pre-emptively `destroy_all` any existing
`PipelineStageRequiredField` row for the same `custom_attribute_definition_id` across *all*
stages in the account before creating the new one, to avoid tripping the now-relaxed uniqueness
constraint. This cross-stage destroy must be removed so a save on Stage B no longer deletes the
requirement on Stage A:

- `PipelineStagesController#sync_required_attributes` — the `.where.not(pipeline_stage_id: stage.id).destroy_all` call is removed; syncing becomes scoped entirely to `stage.pipeline_stage_required_fields` (add attrs newly selected for this stage, remove attrs deselected for this stage — never touch other stages' rows).
- `PipelineStageRequiredFieldsController#create` — the account-wide `PipelineStageRequiredField.where(account_id:, custom_attribute_definition_id:).destroy_all` call is removed; only a same-stage duplicate (rejected by the now stage-scoped uniqueness validation) is possible, returned as the standard `unprocessable_entity` error response.

## Opportunity (no schema change)

No new fields or migrations. `Opportunity#validate_forward_stage_move_requirements` continues to
read `pipeline_stage.required_custom_attribute_definitions` (i.e. the destination stage's own
required-field associations, now potentially overlapping with other stages') and check the
opportunity's own `custom_attributes` hash for key presence — this already implements "filled
once, don't ask again" per FR-004 without modification.
