# Phase 7: Stage Transition Rules

**Depends on**: Phase 1 (backend core), Phase 3 (Pipeline Stages settings screen), Phase 6
(card info enrichment)
**Feeds**: nothing yet

## Context

The original placeholder for this phase flagged two open questions: whether "required
fields" should live on the conversation or the opportunity, and whether validation should
happen frontend-side (pre-drag) or backend-side (reject the `PATCH`). A research note added
during the Phase 5 brainstorm investigated reusing Chatwoot's native Custom Attributes infra
for Opportunity-level fields and found it feasible with two small core-file touches. This
phase's brainstorm settles both questions and the full shape of the feature.

**Why Opportunity-level, not conversation-level:** not every opportunity has an origin
conversation (an opportunity can be created directly, without a chat), so conversation
custom attributes can't be the source of truth for lead-qualification fields that must exist
on every opportunity.

**Enforcement model, decided by comparing against Pipedrive/HubSpot/Salesforce Path
conventions:**
- A lane's required fields are enforced only on **forward** moves into that lane (position
  increasing). Backward moves are always free — no validation, no popup. This matches every
  CRM surveyed: required-field gates exist to qualify a deal before it advances, not to
  police a regression.
- When a card moves forward, fields belonging to **earlier** lanes (by position, excluding
  the destination) are shown but **optional** — pre-filled if already set, editable, but
  non-blocking. Only the destination lane's own required fields block the move. This is the
  Salesforce Path model: skipping a lane is a legitimate action (e.g. a returning customer
  who doesn't need "Discovery"), and retroactively demanding data for a lane the deal never
  conceptually passed through adds friction without matching the deal's actual history.
- **Creation is exempt from enforcement**, but the creation form is stage-aware: selecting a
  starting lane in the creation modal renders that lane's required fields inline (using the
  same shared field-rendering component transitions use), so a deal created straight into a
  later lane is still naturally guided to fill them — just without a hard block. This diverges
  from Pipedrive/HubSpot (which enforce uniformly on creation too) to keep the lightweight
  creation modal from turning into a full deal-edit form, while still surfacing the fields.
- A field (custom attribute or the deal value) can be required by **at most one lane at a
  time** — assigning it to a new lane un-assigns it from wherever it was before. There is no
  "sticky/required forever after this stage" concept; this matches the destination-only
  enforcement model (a field required to pass Lane 2 is already filled by the time a card
  reaches Lane 3, so re-requiring it there would be redundant).
- Because both backward moves and lane reconfiguration can leave a card sitting in a stage
  with unmet current requirements, cards get a persistent, manually-triggerable **"complete
  fields" action** independent of any drag — the only way to backfill in those cases.

**Deal value** (`value`) is a new first-class column on `Opportunity`, not a custom
attribute — it did not exist on the model at all before this phase. It participates in the
same lane-requirement mechanism as custom attributes (a lane can be configured to require it)
but is represented as a dedicated boolean flag on `PipelineStage`, not a
`CustomAttributeDefinition` row.

**Explicitly out of scope, decided during brainstorm:** letting automation rules pre-fill
opportunity custom attributes on creation. Chatwoot has no "set a custom attribute" automation
or macro action for any model today (conversation or contact included) — this would be a new
action category from scratch, not a small addition riding on existing infra, and belongs to a
separate phase under `ciclo 1/02-automation-integration` if pursued.

## Functional Requirements

### Data model

**FR-001**: `matias_opportunities` gains two columns via a new migration: `custom_attributes`
(`jsonb`, `default: {}`) and `value` (`decimal`).

**FR-002**: `matias_pipeline_stages` gains a `requires_deal_value` (`boolean`, `default:
false`) column. `PipelineStage` MUST enforce single-lane exclusivity for this flag: a
`before_save` callback that, when `requires_deal_value` is being set to `true`, unsets it on
every other stage in the same account.

**FR-003**: A new table `matias_pipeline_stage_required_fields` is added (`account_id`,
`pipeline_stage_id`, `custom_attribute_definition_id`, timestamps), with a unique index on
`(account_id, custom_attribute_definition_id)` enforcing that a custom attribute is required
by at most one lane. A new `PipelineStageRequiredField` model belongs to `pipeline_stage`,
`custom_attribute_definition`, and `account`, and validates that the referenced
`custom_attribute_definition.attribute_model` is `opportunity_attribute`.

**FR-004**: `CustomAttributeDefinition#attribute_model` enum gains `opportunity_attribute: 3`
(backend), and the frontend `ATTRIBUTE_MODELS` constant in
`app/javascript/dashboard/routes/dashboard/settings/attributes/constants.js` gains
`{ id: 3, key: 'OPPORTUNITY' }`. These remain the only two upstream/core touches required by
this feature — everything else lives in this fork's own tables.

### Backend validation & API

**FR-005**: `Opportunity` gains a model validation that runs only `on: :update` and only
`if: :pipeline_stage_id_changed?`. It compares the position of the previous stage
(`pipeline_stage_id_was`) against the new stage's position; if the new position is not
strictly greater (i.e. not a forward move), the validation is skipped entirely.

**FR-006**: For a forward move, the validation loads the destination stage's
`PipelineStageRequiredField`s and `requires_deal_value` flag, and checks that every required
`custom_attribute_definition.attribute_key` has a present value in `custom_attributes`, and
that `value` is present if required. Missing fields add structured errors (not just message
strings) so the controller can build a machine-readable response.

**FR-007**: `OpportunitiesController#update` and `#create` params permit `value` and
`custom_attributes` (as an open hash, following the existing jsonb custom-attribute param
pattern used elsewhere in Chatwoot).

**FR-008**: On a validation failure caused specifically by missing required fields,
`OpportunitiesController#update` returns `422` with a structured body:
```json
{
  "error": "...",
  "missing_required_fields": {
    "custom_attribute_keys": ["budget", "decision_maker"],
    "requires_value": true
  }
}
```
This is the defensive fallback path (direct API calls, stale frontend state, race conditions)
— the primary UX flow (FR-013) avoids hitting it under normal conditions.

**FR-009**: `PipelineStagesController#index` (and `#show` if applicable) embeds each stage's
lane-requirement config in its JSON: `requires_deal_value` and
`required_custom_attribute_definitions` (id, `attribute_key`, `attribute_display_name`,
`attribute_display_type`). This reuses the existing lane-fetch call the board already makes on
mount — no additional request is introduced for board rendering.

**FR-010**: `PipelineStagesController#update` permits `requires_deal_value` in its params.

**FR-011**: A new `Api::V1::Accounts::PipelineStageRequiredFieldsController` supports
`create` (assign a custom attribute definition to a lane — deletes any existing row for that
`custom_attribute_definition_id` first, then creates the new one, implementing the
reassignment-steals-it semantics from FR-003 atomically) and `destroy` (unassign).

### Frontend

**FR-012**: A new shared component, `OpportunityRequiredFieldsForm.vue`, renders a list of
required field definitions (blocking, asterisked) and a list of optional/earlier-lane field
definitions (pre-filled if set, non-blocking), reusing the existing per-display-type input
components in `components-next/CustomAttributes/` (`CheckboxAttribute`, `DateAttribute`,
`ListAttribute`, `OtherAttribute`) rather than introducing new per-type inputs. It emits a
`submit` event with the merged `{ custom_attributes, value }` payload; the host component
decides what to do with it.

**FR-013**: `KanbanBoard.vue`'s move-dispatch logic (`dispatchMoveIfComplete`) gains a
proactive client-side check before calling `opportunities/moveCard`: it looks up the
destination stage's required fields (from the `pipelineStages` store, already loaded via
FR-009) against the dragged opportunity's current `custom_attributes`/`value` (already in the
`opportunities` store — no extra fetch). If satisfied, behavior is unchanged. If not, a new
`StageTransitionRequirementsModal.vue` opens instead of dispatching the move, passing the
destination stage's required fields and the union of all earlier stages' fields (by position)
as optional context. On submit it dispatches `moveCard` with the merged attributes bundled
into the same request. On cancel, the move is aborted and the card's visual position reverts
to match unmutated store state.

**FR-014**: `OpportunityCreateModal.vue` becomes stage-aware: changing the selected stage
re-renders `OpportunityRequiredFieldsForm` inline (required fields only, no earlier-lane
fields — there is no history on creation) below the existing basic fields. Submission is
blocked until required fields are filled, same as the existing title/contact requirement.

**FR-015**: `KanbanCard.vue` gains a "complete fields" action, shown when the card's current
stage has required fields not yet satisfied (computed client-side, no extra request). It opens
`OpportunityRequiredFieldsForm` in a lightweight modal (required-only, no earlier-lane
fields, since the card is already in this stage) and submits via a plain
`opportunities/update` — no stage change involved.

**FR-016**: `EditPipelineStage.vue` (and `AddPipelineStage.vue` if applicable) gain a section
for configuring lane requirements: a checklist of `opportunity_attribute`-model custom
attribute definitions (fetched via the existing `customAttributes` store, filtered
client-side) to assign/unassign to this lane, and a `requires_deal_value` toggle.

## Out of Scope (this phase)

- Automation rules pre-filling opportunity custom attributes on creation (see Context — no
  "set a custom attribute" automation/macro action exists for any model yet; separate phase).
- Any validation on backward moves.
- Enforcing required fields at opportunity creation time (inline rendering only, non-blocking
  beyond the existing title/contact requirements).
- A "sticky" required-forever-after concept for the deal value or any custom attribute.
- Allowing a single field to be required by more than one lane simultaneously.
- Retroactive handling of opportunities whose current stage's requirements changed after the
  fact beyond what the manual "complete fields" card action (FR-015) already covers.

## Completion Criteria

Verify inside the `rails`/`vite` containers as appropriate.

1. A custom attribute definition can be created with `attribute_model: opportunity_attribute`
   from the Attributes settings screen.
2. A pipeline stage can be configured (via `EditPipelineStage.vue`) to require one or more
   opportunity custom attributes and/or the deal value; assigning a field already required by
   another lane moves it, verified by re-opening that other lane's config.
3. Dragging a card forward into a lane with unmet required fields opens
   `StageTransitionRequirementsModal` before any request is sent; required fields block
   submission, earlier-lane fields are shown pre-filled but optional.
4. Dragging a card forward into a lane whose requirements are already satisfied moves it
   immediately, no popup.
5. Dragging a card backward never opens the popup and never validates, regardless of missing
   fields.
6. Attempting the underlying `PATCH` directly (bypassing the frontend) against a forward move
   with missing required fields returns `422` with the `missing_required_fields` structure
   from FR-008.
7. Creating an opportunity directly into a stage with required fields does not block
   submission, but the creation form renders that stage's required fields inline.
8. A card sitting in a stage with unmet current-stage requirements (e.g. after a backward move
   or a lane reconfiguration) shows the "complete fields" action; using it updates the
   opportunity without changing its stage.
9. `pnpm eslint` and `bundle exec rubocop` pass for touched files.
