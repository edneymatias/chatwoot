# Phase 0 Research: Multi-Stage Required Fields

No `NEEDS CLARIFICATION` markers remained in the Technical Context — this is a small, well-bounded
change inside an existing fork module with no new technology or pattern choices to make. This
document instead records the investigation findings that shape the implementation approach,
since the actual constraint being removed is enforced in more places than the spec's originating
backlog note (spec18.md) anticipated.

## Decision: Where the "one stage per attribute" constraint actually lives

**Decision**: The constraint must be relaxed in three coordinated places, not one:

1. `db/migrate/*_create_ichatr_pipeline_stage_required_fields.rb` — unique index
   `idx_ichatr_pipeline_stage_req_fields_on_acc_and_attr_def` on `(account_id, custom_attribute_definition_id)`.
2. `custom/app/models/pipeline_stage_required_field.rb` — `validates :custom_attribute_definition_id, uniqueness: { scope: :account_id, ... }`.
3. Two controller methods that proactively enforce the same rule by **destroying** any existing
   requirement for that attribute on *other* stages before creating the new one, so the DB/model
   constraint is never actually hit in normal usage:
   - `Api::V1::Accounts::PipelineStagesController#sync_required_attributes` (used by stage
     create/update, e.g. from `EditPipelineStage.vue`)
   - `Api::V1::Accounts::PipelineStageRequiredFieldsController#create` (the dedicated
     required-fields endpoint)

**Rationale**: Loosening only the DB index and model validation (the two "hard" enforcement
points) would leave the controllers' `destroy_all` steal-and-replace behavior in place, which
would keep silently removing a requirement from Stage A the moment the same attribute is
required on Stage B — the exact bug the feature is meant to fix. All three must change together.

**Alternatives considered**: Relying only on the model/DB constraint and leaving the
`destroy_all` calls in place was rejected — it would look fixed (no validation error) while still
producing the pre-existing single-stage-only behavior, silently, which is worse than the current
explicit error because it fails silently instead of loud.

## Decision: New uniqueness scope

**Decision**: Change the unique index and model validation scope from `account_id` alone to
`[account_id, pipeline_stage_id]` — i.e. keep uniqueness *within* a stage (an attribute cannot be
required twice on the same stage — FR-002) but drop the *cross-stage* uniqueness (FR-001).

**Rationale**: This is the direct, minimal encoding of "any stage may require the attribute, but
not redundantly within itself" — matches FR-001/FR-002 exactly and requires no new columns.

**Alternatives considered**: A composite index without `account_id` was rejected — `account_id`
is retained for parity with the rest of the fork's tenant-isolation convention and because
`pipeline_stage_id` alone does not need `account_id` for correctness, but keeping it costs
nothing and matches the existing index-naming/scoping convention used elsewhere in `custom/`.

## Decision: `validate_forward_stage_move_requirements` needs no code change

**Decision**: `Opportunity#validate_forward_stage_move_requirements` (and its helper
`missing_required_keys`) already evaluates only the *destination* stage's
`required_custom_attribute_definitions` and checks `attrs.key?(definition.attribute_key)` on the
opportunity's own stored custom attributes — it has no dependency on any other stage's
requirements and no dependency on the account-wide uniqueness constraint being removed.

**Rationale**: Confirmed by reading `custom/app/models/opportunity.rb`. Because a value, once
set on the opportunity's `custom_attributes` hash, is checked purely by key presence regardless
of which stage originally required it, FR-003 and FR-004 (independent per-stage evaluation,
"filled once, don't ask again") are already satisfied by existing code and only need spec-level
regression tests added, not new implementation.

**Alternatives considered**: None — no design decision needed here, this is a verification
finding, not a choice.

## Decision: Frontend admin UI needs no functional change

**Decision**: `EditPipelineStage.vue` (the only admin UI that manages
`required_custom_attribute_definition_ids` per stage) already renders every opportunity custom
attribute as a checkbox, unfiltered by whether that attribute is already required on another
stage. FR-006 / User Story 3 is already satisfied by the existing component.

**Rationale**: Confirmed by reading the component — `opportunityAttributes` comes from
`store.getters['attributes/getAttributesByModel']('opportunity_attribute')` with no exclusion
logic based on other stages' required-field state. The only reason a manager would previously
see the "already required" error was the backend rejecting/silently-reassigning the save, not
any client-side filtering.

**Alternatives considered**: None — no design decision needed, verification finding only.

## Decision: i18n message update

**Decision**: `errors.pipeline_stage_required_field.already_required` (`en.yml`, `pt_BR.yml`)
currently reads "is already required in another pipeline stage" / "já é obrigatório em outro
estágio do funil" — this must be reworded to reflect the new same-stage-only restriction (e.g.
"is already required in this pipeline stage" / "já é obrigatório neste estágio do funil").

**Rationale**: Per project i18n guidelines, English and Portuguese source strings are updated
synchronously; the existing message text is now factually wrong once cross-stage requirement is
allowed and would confuse a manager encountering the (now narrower) same-stage duplicate error.

**Alternatives considered**: None — this is a direct consequence of the scope change, not an
open design question.
