# Phase 24: Opportunity Assignment Rules

**Depends on**: Phase 1 (backend core — `Opportunity.assignee_id`,
`belongs_to :assignee`, already permitted on create/update),
Phase 12 (opportunity-triggered automations — `create_opportunity`
automation action, `Custom::AutomationRules::ActionService`)

## Context

`Opportunity.assignee_id` already exists in the schema and API, but there
was no way to set it anywhere: the `create_opportunity` automation action
never configured it, and no UI (kanban card, create modal, edit modal)
exposed it. This phase closes both gaps with the simplest possible design:
a configurable assignee on the `create_opportunity` automation action (with
an optional "same as the conversation" mode), plus a manual assign/reassign
field on the existing opportunity create/edit modals. No rule engine,
round-robin, or pipeline-level ownership concept — those are explicitly out
of scope (see below).

**Bug found and fixed as part of this phase**: `create_opportunity`'s stage
selector (`SingleSelect`) stores `action_params` as `{ id, name }`, but
`Custom::AutomationRules::ActionService#create_opportunity` reads
`params[:pipeline_stage_id]` — a key that never existed in that shape, so
`pipeline_stage_id` was always `nil` and `Opportunity.create!` always raised
`ActiveRecord::RecordInvalid` (caught by the automation runner's generic
`rescue StandardError`, silently reported to the exception tracker). No
opportunity has ever actually been created by this action. Since this phase
already replaces that action's config UI to add the assignee field, the fix
lands in the same change.

Action ordering within a single automation rule already works as needed for
"same as the conversation": `AutomationRules::ActionService#perform` runs
actions in declared order and reloads the conversation before each one, so
an `assign_agent` action placed before `create_opportunity` in the same
rule is picked up correctly — no new mechanism needed.

## Backend

**FR-001**: `Custom::AutomationRules::ActionService#create_opportunity`
resolves `assignee_id` from `params[:assignee_id]`:
- `'same_as_conversation'` → `@conversation.assignee_id` (may be `nil`; no
  fallback when the conversation itself has no assignee).
- Any other value (an agent's user id, or blank) → used as-is.

**FR-002**: No permission checks on who can be set as assignee or who can
reassign — any agent can assign/reassign to any agent or administrator,
consistent with Chatwoot's existing conversation-assignment behavior.

**FR-003**: No notification is sent on assignment/reassignment in this
phase (tracked separately as a Ciclo 7 preview).

**FR-004**: No new endpoints — `assignee_id` is already a permitted param
on `Api::V1::Accounts::OpportunitiesController` create/update, and the
agent/admin list is already served by the existing `agents/getVerifiedAgents`
data used elsewhere in the automation UI.

## Frontend — Automation action config

**FR-005**: New `AutomationActionCreateOpportunityInput.vue`
(`dashboard/components/widgets/`), following the same pattern as the
existing `AutomationActionTeamMessageInput.vue`: receives `modelValue`
(`{ pipeline_stage_id, assignee_id }`), renders two `SingleSelect` fields
(pipeline stage, assignee), emits `update:modelValue` with the full hash on
any change.

**FR-006**: `constants.js`'s `create_opportunity` action entry changes
`inputType` from `'search_select'` to `'create_opportunity'`.
`AutomationActionInput.vue` adds a matching branch rendering the new
component instead of the generic single-select.

**FR-007**: Assignee dropdown options: `'same_as_conversation'` (labeled
"Mesmo da conversa") prepended to the existing `agents.value` list
(`agents/getVerifiedAgents` — already includes administrators), mirroring
the existing `last_responding_agent` sentinel pattern used by the
`assign_agent` action. No explicit "unassigned" option — leaving the field
empty results in `assignee_id: nil`.

**FR-008**: `useAutomationValues.js`'s `getActionDropdownValues` returns
both `pipelineStages` and the agents list for the `create_opportunity`
action type (currently only returns `pipelineStages`), so the new
component has both option sets available.

**FR-009**: Existing automation rules saved with the old, broken
`action_params` shape (`{ id, name }`) are not migrated — since that shape
never worked, opening them in the editor simply shows the new component
unconfigured (stage and assignee both unset), and the admin reconfigures
from scratch.

## Frontend — Manual assign/reassign

**FR-010**: `OpportunityBackfillModal.vue` (the existing opportunity edit
modal, reached today via the kanban card's edit action) gets a new
"Assignee" field, styled as a native `<select>` to match the modal's
existing title input — not the `SingleSelect` component used in the
automation editor. Options: "Sem dono" (empty/`nil`) plus `agents.value`.
Pre-filled from `opportunity.value.assignee_id` on mount; included as
`assignee_id` in the `opportunities/updateOpportunity` dispatch payload on
submit.

**FR-011**: `OpportunityCreateModal.vue` gets the same "Assignee" field
(same component/options as FR-010), defaulting to unassigned, included in
the creation payload. No new UI entry point to open this modal is added in
this phase — the field is ready for whenever that trigger is built.

**FR-012**: Neither manual modal offers a "same as conversation" sentinel
— that only makes sense in the automation context (triggered from a
conversation); manual assignment is a direct pick.

## Out of scope

- Any default/automatic assignment rule beyond what's configured on the
  `create_opportunity` automation action (no round-robin, no
  inherit-without-being-configured).
- Permission restrictions on assignment/reassignment.
- Notifications on assignment/reassignment — Ciclo 7 preview.
- Any concept of pipeline/stage-level team or ownership group — Ciclo 7
  preview.
- A new Kanban UI entry point to open `OpportunityCreateModal.vue`.
- Configuring `title_template` in the automation action's UI — pre-existing
  gap, unrelated to assignment, left as-is.
