# Phase 0 Research: Opportunity Assignment Rules

No `NEEDS CLARIFICATION` markers remain in the Technical Context — this feature extends well-understood, already-in-repo patterns established by prior kanban phases. The items below record the findings from reading the existing code that the plan's decisions rest on, not open unknowns.

## Decision: Where the assignee gets resolved for automation-created opportunities

**Decision**: Resolve `assignee_id` inside `Custom::AutomationRules::ActionService#create_opportunity`, reading `params[:assignee_id]`. If the value is the sentinel `'same_as_conversation'`, use `@conversation.assignee_id` (which may be `nil`); otherwise use the value as-is (a user id, or blank/`nil`).

**Rationale**: `@conversation` is already available in this service (used elsewhere for `contact`, `account`, `display_id`), and `AutomationRules::ActionService#perform` already reloads the conversation before each action runs, so an `assign_agent` action placed earlier in the same rule is picked up correctly with no new mechanism.

**Alternatives considered**: A separate "resolver" object/service for the sentinel value — rejected as unnecessary indirection for a single conditional (Constitution Principle II: smallest change, no premature abstraction).

## Decision: Fixing the `pipeline_stage_id` bug in the same change

**Decision**: The `create_opportunity` action's config UI currently stores `action_params` as `{ id, name }` (via the generic `search_select` `SingleSelect` input), but the backend reads `params[:pipeline_stage_id]` — a key that has never existed in that shape. `Opportunity.create!` has therefore always raised `ActiveRecord::RecordInvalid`, silently swallowed by the automation runner's generic `rescue StandardError`. Since this phase already replaces the action's config UI (to add the assignee field), the new UI emits `{ pipeline_stage_id, assignee_id }` directly, closing the mismatch as a side effect.

**Rationale**: Landing the fix separately would require two coordinated frontend/backend config-shape changes instead of one; bundling avoids an intermediate broken state and matches the spec's explicit call-out of this bug as in-scope.

**Alternatives considered**: Patch only the backend to also read `params[:id]` as a fallback — rejected as a permanent shim for a shape that should not exist going forward, and it wouldn't fix the config UI's inability to also carry an assignee.

## Decision: Automation action UI component pattern

**Decision**: Follow `AutomationActionTeamMessageInput.vue` exactly — a small component receiving `modelValue` (here `{ pipeline_stage_id, assignee_id }`), rendering two `SingleSelect` fields, emitting the merged object on `update:modelValue`. Wired in via a new `inputType: 'create_opportunity'` branch in `AutomationActionInput.vue`, mirroring the existing `team_message` branch.

**Rationale**: This is the only existing precedent in the codebase for an automation action needing more than one config field; reusing it keeps the change minimal and consistent (Constitution Principle III).

**Alternatives considered**: Extending the generic `search_select` input to accept multiple fields — rejected, would complicate a component used by every other single-field action.

## Decision: Manual assignee field styling (create/edit modals)

**Decision**: Use a native `<select>` in both `OpportunityCreateModal.vue` and `OpportunityBackfillModal.vue`, matching each modal's existing plain-HTML form controls (both already use native `<input>`/`<select>` for title/stage, not the `SingleSelect` dropdown component used in the automation editor).

**Rationale**: Consistency with the immediate surrounding markup in each file beats introducing a second dropdown paradigm into the same form.

**Alternatives considered**: `SingleSelect` component for visual parity with automation editor — rejected, breaks visual/structural consistency within each modal.

## Decision: `create` store action needs to forward `assignee_id`

**Decision**: `store/modules/opportunities/actions.js`'s `create` action currently destructures and forwards an explicit whitelist of fields (`title`, `contactId`, `pipelineStageId`, `originConversationId`, `custom_attributes`, `value`) into the API payload — it does not currently pass through an assignee. This whitelist must be extended with `assigneeId` → `assignee_id` for `OpportunityCreateModal.vue`'s new field to have any effect. `updateOpportunity`, by contrast, already spreads `...data` straight through to the API, so `OpportunityBackfillModal.vue`'s new field needs no store-layer change.

**Rationale**: Found by reading the actual action implementations rather than assuming symmetry between `create` and `updateOpportunity` — they use different payload-construction strategies.

**Alternatives considered**: None — this is a required fix for the feature to work, not a choice.
