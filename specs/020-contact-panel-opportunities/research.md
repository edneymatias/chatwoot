# Research: Contact Panel Opportunities Section

No `NEEDS CLARIFICATION` markers remain in the Technical Context — every dependency is an existing in-repo pattern. This document records the concrete decisions made by studying those existing patterns before design.

## 1. Backend contact filter

**Decision**: Add `@opportunities = @opportunities.where(contact_id: params[:contact_id]) if params[:contact_id].present?` to `OpportunitiesController#index`, alongside the existing `pipeline_stage_id` filter. No pagination branch for this filter.

**Rationale**: Mirrors the exact pattern already used for `pipeline_stage_id` in the same action; `order(created_at: :desc)` is already the default, satisfying "most-recent-first" with no change.

**Alternatives considered**: A dedicated `contact_opportunities` endpoint/action — rejected, adds a second index action for what is a one-line filter, inconsistent with how `pipeline_stage_id` was handled.

## 2. Vuex: fetch + store contact opportunities

**Decision**: New action `fetchForContact({ contactId })` calling `opportunitiesAPI.get({ contact_id: contactId })`, committing results through the existing `ADD_MANY_OPPORTUNITIES` mutation (shared `byId` map) plus a new `SET_IDS_BY_CONTACT` mutation writing `state.idsByContact[contactId]`. New getter `cardsForContact: state => contactId => (state.idsByContact[contactId] || []).map(id => state.byId[id]).filter(Boolean)`.

**Rationale**: Directly mirrors the existing `fetchForStage`/`idsByStage`/`cardsForStage` trio — same shape, same shared `byId` cache, no duplicate normalization logic. Because `byId` is shared, an opportunity edited via the kanban board or the contact panel updates in both places for free.

**Alternatives considered**: A separate `contactOpportunities` Vuex module — rejected as needless duplication; the `opportunities` module already exists specifically to hold this data.

## 3. Card-field badge logic extraction

**Decision**: New composable `useOpportunityCardFields(opportunityRef)` under `dashboard/composables/`, moving `configuredFields`/`pipelineCurrency`/`cardFieldConfigs` **and** `statusBadgeClass`/`isStale` computeds verbatim out of `KanbanCard.vue`. `KanbanCard.vue` and the new `ContactOpportunityCard.vue` both call it with their respective `opportunity` prop (as a computed/ref).

**Rationale**: Spec FR-005 requires the same 3 configured card-field badges in both places, and FR-007 requires the same status badge and time-in-stage display in both places too — extracting all of it (not just the 3 card-field badges) avoids re-implementing `statusBadgeClass`/`isStale` a second time in `ContactOpportunityCard.vue`, which would otherwise drift from `KanbanCard.vue`'s behavior. A composable is the idiomatic Vue 3 way to share this reactive computed logic across two components without a shared parent, and this repo already uses the composable pattern extensively (`useUISettings`, `useAccount`).

**Alternatives considered**: Duplicating the computed logic in the new card component — rejected, spec explicitly calls this out as in-scope, targeted refactor; duplication would drift the two cards apart over time.

## 4. New sidebar section wiring

**Decision**: Add `{ name: 'previous_opportunities' }` to `DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER` in `useUISettings.js`, and a new `v-else-if="element.name === 'previous_opportunities'"` branch in `ContactPanel.vue`'s existing `Draggable` item chain, with its own `isContactSidebarItemOpen('is_previous_opportunities_open')` / `toggleSidebarUIState('is_previous_opportunities_open', ...)` key pair. The branch is wrapped in the account's `FEATURE_FLAGS.OPPORTUNITIES` check (same `isCloudFeatureEnabled`/`isFeatureEnabledonAccount` composable already used for `linear_issues`).

**Rationale**: This is the exact, established pattern for every other synced sidebar section in this file (`linear_issues`, `shopify_orders`) — both files are closed, upstream-owned structures per the project constitution, so the only compatible edit is an additive entry in the existing shape, not a refactor.

**Alternatives considered**: A generic plugin/registry mechanism for sidebar sections — rejected as out of scope; no other section in this codebase uses one, and introducing it here would touch far more of the upstream file than this feature needs.

## 5. `ContactOpportunities.vue` component shape

**Decision**: New component parallel to `ContactConversations.vue` — receives `contact-id` prop, dispatches `opportunities/fetchForContact` in `onMounted` and in a `watch` on `contactId` (guarding `newId !== oldId`, same guard `ContactConversations.vue` uses for `contactConversations/get`), renders `cardsForContact(contactId)` via `ContactOpportunityCard.vue`, and shows the same `no-label-message` empty-state pattern when the list is empty.

**Rationale**: `ContactConversations.vue` is explicitly named in the spec as the reference pattern; matching its structure (prop shape, watch guard, empty-state markup class) keeps the new section visually and behaviorally consistent with zero new conventions introduced.

## 6. Opening the edit dialog from a card click

**Decision**: `ContactOpportunityCard.vue` emits a click event with the opportunity id up to `ContactOpportunities.vue`, which holds local state for "currently open modal's opportunity id" and conditionally renders `<OpportunityBackfillModal :opportunity-id="..." @close="..." />` — the same ownership pattern the kanban board already uses to open this modal from its own card's edit action.

**Rationale**: Reuses the modal exactly as designed (`opportunityId` prop, `close`/`updated` events) with no new modal-opening abstraction.

## 7. `OpportunityBackfillModal.vue` upgrade — stage selection & required fields

**Decision**: Add a local `selectedStageId` ref (defaulting to `opportunity.value.pipeline_stage_id`) and a `destinationStage` computed off it via `pipelineStages/stageById` — the same reactive pattern `OpportunityCreateModal.vue` already uses for its own stage select. `requiredDefs`/`requiresDealValue` are recomputed from `destinationStage` instead of `currentStage`. "Optional" custom attributes passed to `OpportunityRequiredFieldsForm` become every `opportunity_attribute` definition (`attributes/getAttributesByModel('opportunity_attribute')`) not already in `requiredDefs`.

**Rationale**: `OpportunityCreateModal.vue` already solves "required fields follow the selected stage, not a fixed stage" for the create flow — the backfill modal adopts the identical computed shape rather than inventing a new one. `OpportunityRequiredFieldsForm.vue` already accepts an `optionalCustomAttributeDefinitions` prop (currently always passed `[]` by the backfill modal) — FR-012 in the source doc confirms no changes are needed to that child component, only to what the parent computes and passes in.

**Alternatives considered**: Keeping required-fields logic keyed on the opportunity's saved stage and only validating on submit — rejected, this is exactly the stale-required-fields bug FR-010 exists to avoid (a user selecting a new stage must see that stage's requirements immediately, not just the old stage's).

## 8. Closed-opportunity reopen flow inside the modal

**Decision**: When `opportunity.value.status !== 'open'`, render a read-only stage name plus a reopen button in place of the `<select>`. The button's click handler directly calls `store.dispatch('opportunities/updateOpportunity', { id: props.opportunityId, status: 'open' })` (not the modal's own `submit()`), and on success does nothing further — because `opportunity` is a Vuex-backed computed (`store.state.opportunities.byId[props.opportunityId]`), the store update alone flips `opportunity.value.status` reactively, which flips the template's `v-if="opportunity.status === 'open'"` and reveals the stage `<select>` without any local component state to manage.

**Rationale**: The existing `KanbanCard.vue` `statusChanged` quick action already performs this same "reopen = direct status update" behavior at the board level; reusing `opportunities/updateOpportunity` (already used by the modal's main submit) keeps a single write path instead of introducing a second action. Because the modal reads `opportunity` from the shared Vuex `byId` map rather than local component state seeded once on mount, the reactivity requirement in FR-014 ("switches to editable stage selector without closing/reopening the dialog") falls out for free — no manual "did we just reopen" flag is needed.

**Alternatives considered**: A local `isReopening`/`localStatus` ref bridging the gap until the dialog is closed — rejected as unnecessary; the computed-from-store `opportunity` already provides live reactivity once the mutation lands.

## 9. Save payload

**Decision**: `submit()` includes `pipeline_stage_id: selectedStageId.value` in the `opportunities/updateOpportunity` dispatch payload, alongside the existing `title`, `custom_attributes`, `value`, `assignee_id`. The existing 422/`missing_required_fields` catch block already present in the modal is reused unchanged — it already handles the shape the backend returns for `validate_forward_stage_move_requirements` failures.

**Rationale**: Backend model validation (`Opportunity#validate_forward_stage_move_requirements`) already differentiates forward vs. backward moves by comparing stage `position` — no frontend-side "is this forward?" branching is needed; the client can always send the selected stage and let the model decide whether to enforce requirements.
