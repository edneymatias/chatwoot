# Phase 1 Data Model: Scout Funnel Stage Qualification Gate

No migrations. Every entity below already exists; this feature only reads more of them (to build
the prompt) and adds one new orchestration path over the existing `Opportunity` write path. Fields
are listed only where relevant to this feature — see the models themselves for the full schema.

## Existing entities consumed

### `Scout` (`custom/app/models/scout.rb`, table `ichatr_scouts`)

Relevant existing associations/fields:
- `belongs_to :default_pipeline_stage, :qualified_stage, :unqualified_stage` (class `PipelineStage`,
  optional) — the three semantic stage roles surfaced in the prompt's stage catalog (FR-001).
- `belongs_to :handover_team, optional` — resolved by `HandoffService` when no explicit `team_id` is
  passed.
- `has_many :required_custom_attribute_definitions, through: :scout_required_fields` — the "global
  qualification requirements" surfaced separately from per-stage requirements (FR-003) and checked
  by `OpportunityStageTransitionService` before allowing entry into `qualified_stage` (FR-006).

No new fields needed on `Scout`.

### `PipelineStage` (core model, table via `pipeline_stages`)

Relevant existing associations:
- `has_many :required_custom_attribute_definitions, through: :pipeline_stage_required_fields` — the
  per-stage required attributes surfaced in the prompt (FR-002) and enforced today by
  `Custom::Concerns::OpportunityValidations#validate_forward_stage_move_requirements` (FR-007,
  unchanged).
- `position` (ordering) and `requires_deal_value?` — already used by the existing forward-move
  validation; unchanged by this feature.
- `description` (text, nullable, added by the funnel stage description editor feature) — the
  stage's operator-authored purpose text, now also surfaced in the prompt's stage catalog
  (FR-001) alongside the stage's name; omitted (not rendered) when blank.

### `PipelineStageRequiredField` / `ScoutRequiredField`

Join records to `CustomAttributeDefinition`. No changes. Both already validate
`definition.opportunity_attribute?` (or `contact_attribute?`/`opportunity_attribute?` for the Scout
one), so the definitions surfaced by this feature are guaranteed to be attributes that can actually
live in `Opportunity#custom_attributes`.

### `CustomAttributeDefinition`

Used to resolve `attribute_key` → `attribute_display_name`, `attribute_display_type`,
`attribute_values` (for `list`-type attributes), and now also `attribute_description` (text,
nullable) — the same semantic-description field already surfaced to the LLM for custom tool
parameters (spec 051) — both when building the prompt (FR-002/FR-003) and when composing a
rejection message naming missing fields (FR-006/FR-007, description not needed in the rejection
message itself, only the display name). No changes to the model; only the amount of it this
feature reads.

### `Opportunity` (`custom/app/models/opportunity.rb`)

Relevant existing state:
- `pipeline_stage_id` — the field this feature's new service assigns and saves.
- `status` (`open`/`won`/`lost`) — never written by any Scout-agent code path (FR-011); this feature
  does not add any code path that sets it.
- `custom_attributes` (jsonb) — read by both the existing model validation (FR-007) and the new
  proactive global-qualification check (FR-006).
- `missing_required_fields` (`attr_accessor`, in-memory only, not persisted) — already populated by
  `OpportunityValidations` when the model-level validation fails; `OpportunityStageTransitionService`
  reads it after a failed `save` to build the FR-007 rejection message. It does **not** need to be
  set for the FR-006 proactive global-qualification check, since that check runs before `save` is
  even attempted and builds its own message directly from the missing `ScoutRequiredField`
  definitions.

No new fields.

### `Team`

Used only as `scout.handover_team` / an explicit `team_id` passed to `HandoffService`. No changes.

## New service objects (not persisted entities, but part of this feature's design)

### `Custom::Scout::HandoffService`

Not a model — a plain Ruby service object.

- **Inputs**: `scout:`, `conversation:` (constructor); `assignee_id:`, `team_id:`, `reason:` (all
  optional, `perform`).
- **Behavior**: identical to today's private `HandoverToHuman` methods — resolve
  team (`team_id.presence || scout.handover_team_id`), assign `conversation.team_id`/`assignee_id`,
  save, call `conversation.bot_handoff!` only if the conversation is currently `pending`, create a
  private transfer note only if `reason` is present, generate contact memory only if
  `scout.feature_memory?`.
- **Callers**: `HandoverToHuman#execute` (passes through the agent-supplied `assignee_id`/`team_id`/
  `reason`) and `OpportunityStageTransitionService` (calls with no `reason` — the qualification
  event's context already lives in the prompt/conversation, per Assumptions in `spec.md`).

### `Custom::Scout::OpportunityStageTransitionService`

Not a model — a plain Ruby service object; the single mutation point for opportunity stage changes
initiated by a Scout tool.

- **Inputs**: `scout:`, `conversation:`, `opportunity:` (constructor); `stage_id:` (`call`).
- **State transitions it governs**:
  1. `stage_id` doesn't resolve to a real stage on the account → reject, no mutation (Edge Case:
     invalid stage id).
  2. Target stage is `scout.qualified_stage_id` and any `scout.required_custom_attribute_definitions`
     is missing from `opportunity.custom_attributes` → reject before `save`, no mutation, no handoff
     (FR-006).
  3. Otherwise assign `opportunity.pipeline_stage_id = stage.id` and `opportunity.save` (not `save!`)
     — this is the same atomic single-save call already used by `ManageOpportunity#update_opportunity`
     today, so any other in-memory field changes the caller already assigned (title/value/
     custom_attributes) are persisted together with the stage change, or rejected together with it,
     with no partial persistence either way.
  4. If `save` fails (existing model validation from FR-007 caught unmet per-stage requirements) →
     reject, build message from `opportunity.missing_required_fields`, no mutation persisted.
  5. If `save` succeeds and `opportunity.saved_change_to_pipeline_stage_id?` is true and the new
     stage is `scout.qualified_stage_id` → call `HandoffService` (one-time, per `/speckit-clarify`).
  6. Return a success string on any successful save, regardless of whether a handoff fired.
