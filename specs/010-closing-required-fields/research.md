# Research: Closing Required Fields (Win/Loss)

No `NEEDS CLARIFICATION` markers remained in the spec's Technical Context by the time planning
started — the sibling `PipelineStageRequiredField` feature already establishes every pattern this
feature needs to mirror. This document records the concrete decisions made by reading that sibling
implementation directly, rather than open research.

## Decision: Data model shape

**Decision**: New model `PipelineClosingRequiredField` backed by table
`matias_pipeline_closing_required_fields` with columns `account_id`, `custom_attribute_definition_id`,
`outcome` (integer enum: `won: 0, lost: 1`), timestamps. Unique index on
`(account_id, custom_attribute_definition_id, outcome)`.

**Rationale**: Mirrors `PipelineStageRequiredField` (`custom/app/models/pipeline_stage_required_field.rb`,
table `matias_pipeline_stage_required_fields`) exactly, except:
- No `pipeline_stage_id` column — closing requirements are global per account, not per stage.
- Adds an `outcome` enum column, and the uniqueness scope includes `outcome` (not just
  `account_id` + `custom_attribute_definition_id`) so the same attribute can be required for both
  `won` and `lost` independently, per spec FR-003.

**Alternatives considered**:
- Reusing `PipelineStageRequiredField` with a nullable `pipeline_stage_id` and an `outcome` column
  bolted on — rejected because it conflates two different trigger semantics (forward-stage-move vs.
  status-change) in one table/model, contradicting the spec's explicit statement that this is "a
  distinct... mechanism" from Phase 7, and complicating the existing uniqueness constraint on
  `PipelineStageRequiredField` (out of scope to touch, per spec's Out of Scope section).
- Unifying with a generic "required field trigger" model now — rejected; spec text explicitly
  defers this to a possible future Phase 18 unification, not attempted here.

## Decision: Validation trigger and error contract

**Decision**: Add `validate :validate_closing_requirements, on: :update, if: :status_changed?` to
`Opportunity` (`custom/app/models/opportunity.rb`), alongside (not replacing) the existing
`validate :validate_forward_stage_move_requirements, on: :update, if: :pipeline_stage_id_changed?`.
Inside the new validation, only proceed when `status.to_s.in?(%w[won lost])` (i.e. skip when
reopening to `open`). On failure, populate the same `missing_required_fields` `attr_accessor` and
`errors.add(:base, ...)` shape the existing validation uses, so
`custom/app/controllers/api/v1/accounts/opportunities_controller.rb`'s existing `update` action
(which already renders `missing_required_fields` on any 422 with that attribute present) requires
**no changes**.

**Rationale**: Confirmed by reading the current `Opportunity` model and controller — the error
contract is already generic enough (`errors.add(:base, ...)` + a `missing_required_fields` reader)
to support a second, independently-triggered validation without controller changes. Reusing it
avoids inventing a second response shape the frontend would need to special-case.

**Alternatives considered**:
- A single combined validation covering both stage-move and closing requirements — rejected;
  spec FR-010 explicitly requires the two checks stay independent, and combining them risks the
  `missing_required_fields` payload silently overwriting one check's result with the other's when
  both `pipeline_stage_id` and `status` change in the same request. Keeping them as two separate
  `validate` calls means Rails' validation runner executes both and accumulates `errors` from each,
  though only the *last*-run validation's `missing_required_fields` value survives (see risk note
  below) — acceptable since this combined-request path is not reachable via the actual UI (stage
  drag and status-bar drag are separate gestures, confirmed during `/speckit-clarify`), and no
  production caller depends on both changing atomically today.

**Risk note (not a spec change, an implementation note for `/speckit-tasks`)**: Because
`missing_required_fields` is a single `attr_accessor`, if both validations fail in the same
`update` call, only one validation's structured payload will be visible to the frontend (the
`errors.add(:base, ...)` messages from both will still be present in `errors.full_messages`, just
not both structured `missing_required_fields` payloads). Given this path isn't reachable from the
UI, no design change is needed; flag it in `data-model.md` for awareness.

## Decision: Frontend wiring point

**Decision**: New `ClosingRequirementsModal.vue`, mirroring `StageTransitionRequirementsModal.vue`
prop-for-prop where applicable (`opportunity`, `outcome` instead of `destinationStageId`,
`initialMissingFields`), reusing `OpportunityRequiredFieldsForm.vue` for the actual field inputs.
Wired into `KanbanBoard.vue`'s existing `onStatusChanged` handler: wrap the current
`store.dispatch('opportunities/setStatus', ...)` call in a try/catch identical in shape to
`executeMoveCard`'s existing try/catch, opening the new modal on a 422 with `missing_required_fields`.

**Rationale**: `onStatusChanged` today (`KanbanBoard.vue:65-67`) has no error handling at all —
`setStatus` already reverts optimistic state and re-throws on error
(`store/modules/opportunities/actions.js`), so the missing piece is purely the catch-and-show-modal
step already proven out for the stage-move path.

**Alternatives considered**:
- Building a new drag-to-close status bar UI from scratch — out of scope; Phase 16 owns that UI
  surface. This feature only needs to add error handling to whatever calls `setStatus`/dispatches a
  status change, regardless of which UI trigger (status bar drag, a dropdown, etc.) initiates it.

## Decision: `setStatus` action needs to accept custom attribute values on retry

**Decision**: Extend `opportunities/setStatus` action (`store/modules/opportunities/actions.js`) to
accept optional `custom_attributes` (and reuse the existing `value` param name if a deal-value
retry is ever needed, though out of scope per spec Assumptions), mirroring how `moveCard` already
accepts `custom_attributes`/`value` for its own retry path. Do not add a new `closeOpportunity`
action — `setStatus` already does everything needed once extended.

**Rationale**: Minimizes surface area (Constitution Principle II); `setStatus` already has the
right shape (optimistic update + revert-on-error), the only gap is the missing payload field for
the retry submission.

**Alternatives considered**: A dedicated `closeOpportunity` action (as informally suggested in the
original design doc `docs/kanban/ciclo 3/10-closing-required-fields/spec19.md`) — rejected as
unnecessary duplication once `setStatus` is confirmed to already cover the same request shape
(`PATCH` with `status` + `custom_attributes`) via the shared `opportunities/update` API client call.

## Decision: Admin settings UI placement

**Decision**: New settings screen at `routes/dashboard/settings/pipelineStages/ClosingRequiredFields.vue`,
listing two attribute pickers ("Obrigatório para vitória" / "Obrigatório para derrota"), reusing the
exact checkbox-list attribute-picker markup already in `EditPipelineStage.vue`'s "Required Custom
Attributes" section. Does not depend on a not-yet-built tab-bar shell for Estágios/Fechamento —
the existing generic `components-next/tabbar/TabBar.vue` component is reusable today if a tabbed
shell is added around the existing stages `Index.vue`, but building that shell is not required by
this feature; a simple new route/settings page is sufficient and independently shippable.

**Rationale**: The original design doc assumed a "Fechamento" tab alongside "Estágios" using a
tab-bar shell "confirmed for Phase 16/Phase 14's settings evolution" — that shell does not exist in
the current codebase. Building the full tabbed settings shell is a larger, separate concern
(shared across multiple future phases) and not required to deliver this feature's value; a
standalone settings page satisfies User Story 2 independently. If/when the tabbed shell lands
(Phase 16/14), this screen can be moved into a tab without changing its internal logic.

**Alternatives considered**: Building the tab-bar shell now as a prerequisite — rejected as scope
creep beyond this feature's spec (Constitution Principle II); deferred to whichever phase actually
introduces the shared settings tab shell.
