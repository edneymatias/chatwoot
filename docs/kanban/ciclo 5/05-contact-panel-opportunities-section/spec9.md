# Phase 9: Contact Panel Opportunities Section

**Depends on**: Phase 1 (backend core — `Opportunity` model, `pipeline_stage_id`,
`custom_attributes`, `value`), Phase 24 (`assignee_id` on create/update,
existing `OpportunityBackfillModal.vue`/`OpportunityRequiredFieldsForm.vue`),
existing `opportunities` account feature flag (`Concerns::KanbanFeatureGuard`
on backend, `FEATURE_FLAGS.OPPORTUNITIES` on frontend)

## Context

Add an "Opportunities" accordion section to Chatwoot's native `ContactPanel.vue`
sidebar — the one shown to the right of an open conversation — listing the
current contact's opportunities, most recent first, mirroring the existing
"Conversas anteriores" section (`ContactConversations.vue` +
`ConversationCard.vue`). Clicking a card opens an upgraded
`OpportunityBackfillModal.vue` instead of navigating away.

This phase also upgrades `OpportunityBackfillModal.vue` itself — the same
modal already used by the kanban card's edit action — so that it becomes a
genuine "everything you'd do on the kanban board, without leaving the
conversation" shortcut: change stage, reopen a closed opportunity, edit
value, and edit every custom attribute (not just the ones required by the
current stage). Because the modal is shared, these improvements apply to
both entry points (kanban card edit action and the new contact panel
section) — this is an intentional, strictly-additive side effect, not a
forked variant.

The known complication from the original placeholder still applies:
`ContactPanel.vue`'s sidebar sections are a closed `v-if`/`v-else-if` chain
keyed on `element.name`, and available section names come from the frozen
`DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER` array in `useUISettings.js` — both
files need a direct new entry (`previous_opportunities`), same class of edit
already made for other sync'd sections.

## Backend

**FR-001**: `Api::V1::Accounts::OpportunitiesController#index` accepts an
optional `contact_id` param (same pattern as the existing
`pipeline_stage_id` filter), scoping `@opportunities` to that contact.
Ordering stays `order(created_at: :desc)` (already the default — no change
needed there). No pagination added for this filter; a single contact's
opportunity list is expected to stay small.

## Frontend — data layer

**FR-002**: `opportunities` Vuex module gets a new action `fetchForContact({
contactId })` (`GET /opportunities?contact_id=X`), storing results in the
existing `byId` map (via `ADD_MANY_OPPORTUNITIES`) plus a new
`idsByContact[contactId]` list (mirroring `idsByStage`). New getter
`cardsForContact: state => contactId => ...` (mirroring `cardsForStage`).

## Frontend — section

**FR-003**: New sidebar entry `{ name: 'previous_opportunities' }` added to
`DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER`
(`dashboard/composables/useUISettings.js`), plus a matching `AccordionItem`
branch (`v-else-if="element.name === 'previous_opportunities'"`) in
`ContactPanel.vue`, following the exact same structure as the
`previous_conversation` branch (own `AccordionItem`, own
`toggleSidebarUIState`/`isContactSidebarItemOpen` key, own i18n title key).
The whole section is gated behind
`isFeatureEnabledonAccount(accountId, FEATURE_FLAGS.OPPORTUNITIES)` — no
section, no accordion entry, for accounts without the feature enabled.

**FR-004**: New `ContactOpportunities.vue`
(`dashboard/routes/dashboard/conversation/`, paralleling
`ContactConversations.vue`), receiving `contact-id`, dispatching
`fetchForContact` on mount and whenever `contactId` changes, rendering
`cardsForContact` most-recent-first (backend order is already correct — no
client-side re-sort needed). Includes **all** opportunities regardless of
status (open, won, lost). Empty state: same inline message pattern already
used by `ContactConversations.vue` when `previousConversations.length ===
0`.

**FR-005**: New `ContactOpportunityCard.vue`
(`dashboard/components-next/Opportunities/`), showing: opportunity title,
status badge (open/won/lost — same `statusBadgeClass` logic as
`KanbanCard.vue`), creation date, current stage name, time in current stage,
and the same 3 configured card-field badges (`value`/custom-attribute
badges driven by `pipelineCardFieldConfigs`) that `KanbanCard.vue` already
computes. The badge-computation logic (`configuredFields`,
`pipelineCurrency`, `cardFieldConfigs`) is extracted from `KanbanCard.vue`
into a shared composable (e.g. `useOpportunityCardFields(opportunity)` under
`dashboard/composables/`) and reused by both `KanbanCard.vue` and
`ContactOpportunityCard.vue`, instead of duplicating that logic — this is a
small, targeted refactor scoped only to the code this phase touches.

**FR-006**: Clicking a `ContactOpportunityCard.vue` opens
`OpportunityBackfillModal.vue` for that opportunity's id (no navigation, no
route change — the conversation view underneath stays exactly as-is).

## Frontend — `OpportunityBackfillModal.vue` upgrade

**FR-007**: Field order becomes: **title** → **stage selector** (only when
`opportunity.status === 'open'`) **or reopen button** (only when
`opportunity.status !== 'open'`, same icon/label as `KanbanCard.vue`'s
reopen quick action) → **deal value** → **required custom attributes for
the destination stage** → **all remaining (optional) custom attributes**.

**FR-008**: Stage selector is a native `<select>` (matching the existing
title-input styling, same convention as `OpportunityCreateModal.vue`'s stage
select), populated from `pipelineStages/stagesSortedByPosition`, defaulting
to the opportunity's current `pipeline_stage_id`. A local `destinationStage`
computed (keyed off the selected value, not the opportunity's saved stage)
drives which custom attribute definitions count as "required" vs
"optional" — same reactive pattern `OpportunityCreateModal.vue` already
uses for its own stage select.

**FR-009**: Deal value input is now always rendered (previously gated
behind `requiresDealValue` of the *current* stage), always editable; it's
only marked required (asterisk, validated) when `destinationStage` requires
a deal value.

**FR-010**: For closed opportunities (`status !== 'open'`), the stage
selector is replaced by a plain read-only display of the current stage name
plus a **"Reabrir"** button (same icon/i18n key as `KanbanCard.vue`'s
`OPPORTUNITIES.BOARD.ACTIONS.REOPEN`). Clicking it immediately dispatches
`opportunities/updateOpportunity` with `status: 'open'` — a separate,
immediate action from the modal's main "Salvar" submit, mirroring how the
kanban card's own reopen quick action already works today. On success, the
modal's local `opportunity` status flips to `open` reactively (no
close/reopen of the modal needed), which switches the read-only stage
display back into the editable stage selector so the user can continue
editing/saving in the same sitting.

**FR-011**: "Salvar" submit payload (via
`opportunities/updateOpportunity`) now includes `pipeline_stage_id` in
addition to the existing `title`, `custom_attributes`, `value`,
`assignee_id`. Forward stage moves still go through the existing backend
validation (`validate_forward_stage_move_requirements` — missing required
fields for a forward move return a 422 with `missing_required_fields`,
already handled by the modal's existing catch block); backward moves are
unaffected (no requirement check), consistent with current model behavior.

**FR-012**: `OpportunityRequiredFieldsForm.vue` needs no changes — it
already supports `requiredCustomAttributeDefinitions` +
`optionalCustomAttributeDefinitions` as separate props; the modal only
needs to compute "optional" as *all* `opportunity_attribute` definitions
not already present in `destinationStage`'s required list.

## Out of scope

- Any new UI entry point to **create** an opportunity from the contact
  panel — creation entry points are being decided separately as part of the
  kanban board's own "+ Nova oportunidade" work (not this phase).
- Permission checks on who can change stage / reopen / edit assignee from
  this modal — consistent with the rest of the opportunities feature today.
- Notifications on stage change or reopen.
- Pagination/infinite-scroll for the contact panel's opportunity list.
- Any change to how `ContactConversations.vue` itself behaves — it's a
  reference pattern here, not touched by this phase.
