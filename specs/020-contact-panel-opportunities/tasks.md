---

description: "Task list for Contact Panel Opportunities Section"
---

# Tasks: Contact Panel Opportunities Section

**Input**: Design documents from `/specs/020-contact-panel-opportunities/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: No dedicated test tasks are included — per this repo's `CLAUDE.md` convention ("Avoid writing specs unless explicitly asked"), no new RSpec/Vue test files are generated here. The Polish phase does include running the existing `KanbanBoard.spec.js` suite as a regression check for the shared-component refactor, since that's executing existing tests, not writing new ones.

**Organization**: Tasks are grouped by user story (spec.md P1/P2/P3) so each can be delivered and validated independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

## Phase 1: Setup

No tasks — this feature extends the existing scaffolded Rails + Vue app; no new dependencies, directories, or config are needed.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared backend/store/composable infrastructure every user story builds on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T001 [P] Add `contact_id` filter to `index` in `custom/app/controllers/api/v1/accounts/opportunities_controller.rb`, mirroring the existing `pipeline_stage_id` filter (see [contracts/contact-opportunities-filter.md](./contracts/contact-opportunities-filter.md))
- [X] T002 [P] Add `fetchForContact({ contactId })` action to `app/javascript/dashboard/store/modules/opportunities/actions.js`
- [X] T003 [P] Add `SET_IDS_BY_CONTACT` mutation (mirrors `SET_IDS_BY_STAGE`) to `app/javascript/dashboard/store/modules/opportunities/mutations.js`
- [X] T004 [P] Add `cardsForContact` getter to `app/javascript/dashboard/store/modules/opportunities/getters.js`
- [X] T005 Extract `configuredFields`/`pipelineCurrency`/`cardFieldConfigs`/`statusBadgeClass`/`isStale` logic out of `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue` into a new `useOpportunityCardFields(opportunityRef)` composable in `app/javascript/dashboard/composables/useOpportunityCardFields.js`
- [X] T006 Update `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue` to consume `useOpportunityCardFields` instead of its inline computeds (depends on T005)

**Checkpoint**: Backend filter, Vuex contact-scoped state, and the shared card-field composable are ready — user story work can begin.

---

## Phase 3: User Story 1 - See a contact's opportunities without leaving the conversation (Priority: P1) 🎯 MVP

**Goal**: Agents can expand an "Opportunities" section in the contact panel and see the current contact's opportunities, most-recent-first, with an empty state when there are none, gated by the opportunities feature flag.

**Independent Test**: Open a conversation for a contact with opportunities, expand the new section, confirm the list appears without navigating away; repeat for a contact with none (empty state) and for an account without the feature flag (no section at all).

### Implementation for User Story 1

- [X] T007 [P] [US1] Add a `previous_opportunities` entry to `DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER` in `app/javascript/dashboard/composables/useUISettings.js`
- [X] T008 [P] [US1] Create `ContactOpportunityCard.vue` (title, status badge, creation date, current stage, time-in-stage, configured-field badges — all via `useOpportunityCardFields`, including its `statusBadgeClass`/`isStale` outputs, no logic re-implemented locally) in `app/javascript/dashboard/components-next/Opportunities/ContactOpportunityCard.vue`
- [X] T009 [US1] Create `ContactOpportunities.vue` in `app/javascript/dashboard/routes/dashboard/conversation/ContactOpportunities.vue` — `contact-id` prop, dispatches `opportunities/fetchForContact` on mount and on `contactId` change (mirrors `ContactConversations.vue`'s watch guard), renders `cardsForContact` via `ContactOpportunityCard.vue`, shows `no-label-message` empty state when the list is empty (depends on T002, T003, T004, T008)
- [X] T010 [US1] Add a `v-else-if="element.name === 'previous_opportunities'"` branch to `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`, gated by the account's `FEATURE_FLAGS.OPPORTUNITIES` check (same pattern as the `linear_issues` branch), rendering `ContactOpportunities.vue` with the conversation's `contact-id` (depends on T007, T009)
- [X] T011 [P] [US1] Add i18n keys for the new accordion section title and empty-state copy to `app/javascript/dashboard/i18n/locale/en/conversation.json` (or the file housing the other sidebar section keys)

**Checkpoint**: User Story 1 is fully functional and independently testable — this alone is a shippable MVP.

---

## Phase 4: User Story 2 - Edit an opportunity from the conversation (Priority: P2)

**Goal**: Clicking an opportunity card in the contact panel opens the shared edit dialog, pre-filled, allowing stage/value/custom-attribute changes with stage-appropriate required-field enforcement (forward moves only) and a single combined save.

**Independent Test**: From the panel's list, click an open opportunity's card, change its stage to one with new required fields, confirm those fields are enforced, save, and confirm the change persists; then confirm a backward stage move is never blocked by required fields.

### Implementation for User Story 2

- [X] T012 [US2] Add a `selectedStageId` ref (defaulting to `opportunity.value.pipeline_stage_id`) and a `destinationStage` computed (via `pipelineStages/stageById`) to `app/javascript/dashboard/components-next/Opportunities/OpportunityBackfillModal.vue`, mirroring `OpportunityCreateModal.vue`'s stage-select pattern
- [X] T013 [US2] Recompute `requiredDefs`/`requiresDealValue` from `destinationStage` (instead of the opportunity's saved stage) in `OpportunityBackfillModal.vue` (depends on T012)
- [X] T014 [P] [US2] Remove the `v-if="requiresDealValue"` wrapper around the deal-value input block in `app/javascript/dashboard/components-next/Opportunities/OpportunityRequiredFieldsForm.vue` so the field always renders; use `requiresDealValue` only to control the required-marker (`*`) and validation, mirroring how `isOptional` already toggles the `*` marker for custom attribute fields (FR-012)
- [X] T015 [US2] Compute `optionalCustomAttributeDefinitions` (all `opportunity_attribute` definitions not already in `requiredDefs`) and pass it to `OpportunityRequiredFieldsForm` in `OpportunityBackfillModal.vue`, replacing the current always-empty `[]` (depends on T013)
- [X] T016 [US2] Include `pipeline_stage_id: selectedStageId.value` in the `opportunities/updateOpportunity` dispatch payload from `submit()` in `OpportunityBackfillModal.vue`, alongside the existing `title`/`custom_attributes`/`value`/`assignee_id` fields (depends on T012)
- [X] T017 [US2] Wire `ContactOpportunityCard.vue` click to open `OpportunityBackfillModal.vue` for that opportunity, with `ContactOpportunities.vue` owning the "currently open modal's opportunity id" local state (`app/javascript/dashboard/routes/dashboard/conversation/ContactOpportunities.vue`, `app/javascript/dashboard/components-next/Opportunities/ContactOpportunityCard.vue`)
- [X] T018 [P] [US2] Add i18n keys for the stage-select label and the deal-value-always-editable copy to the opportunities i18n locale file(s) in `app/javascript/dashboard/i18n/locale/en/`

**Checkpoint**: User Stories 1 and 2 both work independently — editing is available both from the kanban board and the new contact panel entry point.

---

## Phase 5: User Story 3 - Reopen a closed opportunity from the conversation (Priority: P3)

**Goal**: For a won/lost opportunity, the dialog shows a read-only stage plus a reopen action; clicking it flips status to open and reveals the editable stage selector in place, without closing the dialog.

**Independent Test**: Open the dialog for a closed opportunity, confirm only a read-only stage and reopen action are shown, click reopen, and confirm the dialog switches to the editable stage selector immediately without being closed/reopened.

### Implementation for User Story 3

- [X] T019 [US3] Render a read-only stage display and a reopen button (instead of the stage `<select>`) in `OpportunityBackfillModal.vue` when `opportunity.value.status !== 'open'` (depends on T012)
- [X] T020 [US3] Wire the reopen button to directly dispatch `opportunities/updateOpportunity({ id: props.opportunityId, status: 'open' })` in `OpportunityBackfillModal.vue`, relying on the store-backed `opportunity` computed to reactively reveal the stage selector once the mutation lands (depends on T019)
- [X] T021 [P] [US3] Add i18n keys for the reopen action label to the opportunities i18n locale file(s) in `app/javascript/dashboard/i18n/locale/en/`

**Checkpoint**: All three user stories are independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T022 [P] Run the [quickstart.md](./quickstart.md) validation scenarios end-to-end against the dev stack
- [X] T023 [P] Run the existing `KanbanBoard.spec.js` suite (`docker compose exec vite pnpm test`) to confirm the `useOpportunityCardFields` extraction introduced no regression
- [X] T024 Run `docker compose exec vite pnpm eslint:fix` and `docker compose exec rails bundle exec rubocop -a` across all touched files

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational (Phase 2)**: No dependencies — start immediately. BLOCKS all user stories.
- **User Story 1 (Phase 3)**: Depends on Phase 2 (T002–T005). No dependency on US2/US3.
- **User Story 2 (Phase 4)**: Depends on Phase 2 (T005/T006 for shared composable, not directly required) and on US1's `ContactOpportunityCard.vue`/`ContactOpportunities.vue` (T008, T009) existing as the entry point for T017 — the modal changes themselves (T012–T016) and the `OpportunityRequiredFieldsForm.vue` fix (T014, no dependency on T012/T013) only depend on Phase 2 and are independently testable via the kanban board's existing entry point even before US1 ships.
- **User Story 3 (Phase 5)**: Depends on T012 (Phase 4) for the `selectedStageId`/`destinationStage` scaffolding the reopen flow reveals.
- **Polish (Phase 6)**: Depends on all desired user stories being complete.

### Parallel Opportunities

- T001–T004 (Phase 2) can all run in parallel — different files, no cross-dependencies.
- T007, T008, T011 (US1) can run in parallel; T009 depends on T008, T010 depends on T007+T009.
- T014 (US2) can run in parallel with T012/T013 — it edits `OpportunityRequiredFieldsForm.vue`, not `OpportunityBackfillModal.vue`, and has no dependency on the stage-selection scaffolding.
- T018 (US2) and T021 (US3) can run in parallel with their respective story's other tasks — pure i18n additions.
- T022 and T023 (Polish) can run in parallel.

---

## Parallel Example: Phase 2 (Foundational)

```bash
Task: "Add contact_id filter to custom/app/controllers/api/v1/accounts/opportunities_controller.rb"
Task: "Add fetchForContact action to app/javascript/dashboard/store/modules/opportunities/actions.js"
Task: "Add SET_IDS_BY_CONTACT mutation to app/javascript/dashboard/store/modules/opportunities/mutations.js"
Task: "Add cardsForContact getter to app/javascript/dashboard/store/modules/opportunities/getters.js"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational
2. Complete Phase 3: User Story 1
3. **STOP and VALIDATE**: Confirm the read-only opportunities section works per its Independent Test
4. Demo/ship if ready — this alone satisfies spec.md's stated core value

### Incremental Delivery

1. Foundational → User Story 1 (view, MVP) → validate
2. User Story 2 (edit) → validate → ships the edit-in-place shortcut
3. User Story 3 (reopen) → validate → completes the full spec scope

---

## Notes

- [P] tasks touch different files with no dependency on incomplete tasks in this list.
- No backend or frontend test files are added per this repo's "avoid writing specs unless explicitly asked" convention; T023 runs the pre-existing suite as a regression check only.
- Every task stays inside the file set already identified in [plan.md](./plan.md)'s Project Structure section — no new top-level directories, no `enterprise/` involvement.

## Phase 7: Convergence

- [X] T025 Fix `OpportunityBackfillModal.vue`'s `validateForm()` to only enforce destination-stage required fields on forward moves (compare `destinationStage.position` against the opportunity's currently-saved stage position, mirroring the backend's `position <=` skip in `custom/app/models/opportunity.rb`), so backward moves are not blocked client-side per FR-011 (contradicts)
- [X] T026 Add a distinct, always-visible creation-date field to `ContactOpportunityCard.vue`, separate from the existing time-in-stage/time-since-creation badge, per FR-007 / US1/AC1 (partial)
- [X] T027 Show an explicit status indicator for open opportunities in `ContactOpportunityCard.vue` (currently the status badge only renders for non-open statuses), so all three statuses in US1/AC1's example are visibly distinguishable in the mixed contact-panel list per FR-007 / US1/AC1 (partial)

## Phase 8: Convergence

- [X] T028 Replace the always-editable status `<select>` for closed opportunities in `OpportunityBackfillModal.vue` with a read-only stage display plus a distinct reopen button that immediately dispatches `opportunities/updateOpportunity({ id: props.opportunityId, status: 'open' })` on click (independent of `submit()`), reactively revealing the editable stage selector once the mutation lands, per FR-013 / FR-014 / US3-AC2 (contradicts)
- [X] T029 Add a separate, always-visible creation-date field to `ContactOpportunityCard.vue`, distinct from the existing time-in-stage/time-since-creation badge produced by `useOpportunityCardFields`, per FR-007 / T026 (partial)
