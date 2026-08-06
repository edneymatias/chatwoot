---

description: "Task list for feature implementation"
---

# Tasks: Opportunity Assignment Rules

**Input**: Design documents from `/specs/019-opportunity-assignment-rules/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Not explicitly requested for this feature (per project convention: avoid writing specs unless explicitly asked). The one exception is extending existing backend coverage for the method whose behavior changes — see Polish phase.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- File paths are exact and relative to the repository root.

## Phase 1: Setup

No setup tasks required. This feature adds no new dependencies, packages, or scaffolding — it extends existing Rails/Vue files already present in `custom/` and `app/javascript/dashboard/`.

## Phase 2: Foundational

No blocking cross-story prerequisites. `Opportunity.assignee_id` / `belongs_to :assignee` and the `assignee_id` permitted param on `OpportunitiesController` already exist (confirmed in [data-model.md](./data-model.md)) — each user story below is independently additive on top of that existing field. User stories can be implemented in any order.

---

## Phase 3: User Story 1 - Auto-assign opportunities created by automation (Priority: P1) 🎯 MVP

**Goal**: The `create_opportunity` automation action supports configuring an assignee (a specific agent/administrator, or "same as the conversation"), and the pre-existing bug that silently prevented this action from ever creating an opportunity is fixed as part of shipping the new config UI.

**Independent Test**: Configure an automation rule's `create_opportunity` action with a pipeline stage and an assignee (try both a specific agent and "same as the conversation"), trigger the rule, and confirm the opportunity is created in the right stage and owned by the expected person — including the no-conversation-assignee case (opportunity created unassigned, no error).

### Implementation for User Story 1

- [X] T001 [US1] Add assignee resolution to `create_opportunity` in `custom/app/services/custom/automation_rules/action_service.rb`: resolve `params[:assignee_id] == 'same_as_conversation'` to `@conversation.assignee_id` (may be `nil`), otherwise use `params[:assignee_id]` as-is, and pass `assignee_id:` into the existing `Opportunity.create!` call. See [contracts/create-opportunity-automation-action.md](./contracts/create-opportunity-automation-action.md) for the exact behavior contract.
- [X] T002 [P] [US1] Add the "same as the conversation" label key (e.g. `AUTOMATION.ACTION.CREATE_OPPORTUNITY_SAME_AS_CONVERSATION`, mirroring the existing `AUTOMATION.LAST_RESPONDING_AGENT` key) to `app/javascript/dashboard/i18n/locale/en/automation.json`.
- [X] T003 [P] [US1] Create `app/javascript/dashboard/components/widgets/AutomationActionCreateOpportunityInput.vue`, following `AutomationActionTeamMessageInput.vue's` pattern: props `modelValue` (`{ pipeline_stage_id, assignee_id }`), `pipelineStages` (array), `agents` (array, already including the `'same_as_conversation'` sentinel option), renders two `SingleSelect` fields, emits `update:modelValue` with the merged object on any change.
- [X] T004 [US1] In `getActionDropdownValues` (`app/javascript/dashboard/composables/useAutomationValues.js`), special-case `type === 'create_opportunity'` to return `{ pipelineStages: pipelineStages.value, agents: [{ id: 'same_as_conversation', name: t('AUTOMATION.ACTION.CREATE_OPPORTUNITY_SAME_AS_CONVERSATION') }, ...agents.value] }` instead of the generic single-array `getActionOptions` result. Depends on T002 for the label key.
- [X] T005 [US1] Remove the now-dead `create_opportunity: pipelineStages` entry from the `actionsMap` in `getActionOptions` (`app/javascript/dashboard/helper/automationHelper.js`), since `create_opportunity` dropdown data is now sourced via T004's object shape, not this generic single-array path.
- [X] T006 [US1] In `app/javascript/dashboard/components/widgets/AutomationActionInput.vue`, add a template branch rendering `AutomationActionCreateOpportunityInput` when `inputType === 'create_opportunity'`, passing `:pipeline-stages="dropdownValues.pipelineStages"` and `:agents="dropdownValues.agents"` (register the component in the `components` object). Depends on T003 and T004.
- [X] T007 [US1] In `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js`, change the single canonical `create_opportunity` action-type entry's `inputType` from `'search_select'` to `'create_opportunity'` (around line 824, `{ key: 'create_opportunity', label: 'CREATE_OPPORTUNITY', inputType: 'search_select' }`). The 5 per-event-type action-list entries (lines ~156, ~294, ~444, ~584, ~702) are bare `{ key, name }` pairs with no `inputType` field — `inputType` is resolved centrally by key lookup, so they need no change. Depends on T006.

**Checkpoint**: User Story 1 is fully functional and independently testable — automation-created opportunities are actually created (bug fixed) and correctly assigned.

---

## Phase 4: User Story 2 - Manually reassign an opportunity's owner (Priority: P2)

**Goal**: Any agent or administrator can change (or clear) an existing opportunity's assignee from its edit view.

**Independent Test**: Open an existing opportunity's edit modal, set/change/clear the assignee, save, and confirm the change persists and is reflected on reopening — independent of anything from User Story 1.

### Implementation for User Story 2

- [X] T008 [US2] Add an "Assignee" field to `app/javascript/dashboard/components-next/Opportunities/OpportunityBackfillModal.vue`: a native `<select>` (matching the modal's existing plain-input styling, not `SingleSelect`), options "Sem dono" (empty/`nil`, add this and an "Assignee" label i18n key to `app/javascript/dashboard/i18n/locale/en/opportunities.json`) plus the account's agents (sourced via `store.getters['agents/getVerifiedAgents']`), pre-filled from `opportunity.value.assignee_id` in the existing `onMounted` hook, and included as `assignee_id` in the `opportunities/updateOpportunity` dispatch payload in `submit()`. See [contracts/opportunity-assignee-field.md](./contracts/opportunity-assignee-field.md) — `updateOpportunity` already forwards the full payload, no store change needed.

**Checkpoint**: User Story 2 is fully functional and independently testable — manual reassignment works regardless of whether User Story 1 has been implemented.

---

## Phase 5: User Story 3 - Set an owner while creating an opportunity (Priority: P3)

**Goal**: A user creating an opportunity can pick its owner at creation time, defaulting to unassigned.

**Independent Test**: Open the opportunity creation form, pick an assignee (or leave it unset), submit, and confirm the created opportunity's owner matches — independent of User Stories 1 and 2.

### Implementation for User Story 3

- [X] T009 [US3] Extend the `create` action in `app/javascript/dashboard/store/modules/opportunities/actions.js` to accept `assigneeId` in its destructured payload and forward it as `assignee_id` in the `opportunitiesAPI.create({ opportunity: { ... } })` call. Required per [contracts/opportunity-assignee-field.md](./contracts/opportunity-assignee-field.md) — this action currently whitelists fields and silently drops any assignee.
- [X] T010 [US3] Add an "Assignee" field to `app/javascript/dashboard/components-next/Opportunities/OpportunityCreateModal.vue`: same native `<select>` component/options as T008 ("Sem dono" default plus `agents.value`, sourced via `store.getters['agents/getVerifiedAgents']`, reusing the i18n keys added in T008 or adding them if implemented before US2), included as `assigneeId` in the `opportunities/create` dispatch payload in `submit()`. Depends on T009.

**Checkpoint**: User Story 3 is fully functional and independently testable — creation-time assignment works regardless of User Stories 1/2.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T011 [P] Extend `spec/services/automation_rules/action_service_spec.rb`'s `#perform with create_opportunity action` coverage for: assignee resolved from a specific id, `'same_as_conversation'` resolving to the conversation's current assignee, `'same_as_conversation'` with no conversation assignee leaving the opportunity unassigned, and blank/absent `assignee_id`.
- [X] T012 [P] Run `docker compose exec rails bundle exec rubocop -a custom/app/services/custom/automation_rules/action_service.rb` and `docker compose exec vite pnpm eslint:fix` on all touched `.vue`/`.js` files.
- [X] T013 Walk through every scenario in [quickstart.md](./quickstart.md) (all 3 user stories plus the regression checks: old-shape automation rules, action-ordering with `assign_agent`, no notifications sent) against the running dev stack.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup / Foundational**: None — no tasks in these phases.
- **User Stories (Phase 3-5)**: Fully independent of each other; may be implemented and delivered in any order or in parallel.
- **Polish (Phase 6)**: Depends on all desired user stories being complete.

### User Story Dependencies

- **User Story 1 (P1)**: No dependency on US2/US3.
- **User Story 2 (P2)**: No dependency on US1/US3.
- **User Story 3 (P3)**: No dependency on US1/US2 (T010 depends only on T009, both within US3).

### Within Each User Story

- US1: T001 (backend) is independent of the frontend chain; T002 → T004 → T006 → T007 is a strict sequence, T003 can run in parallel with T002/T004, T005 can run any time after the `create_opportunity` actionsMap entry is no longer needed (after T004).
- US2: single task (T008).
- US3: T009 before T010.

### Parallel Opportunities

- T001, T002, T003 can start in parallel (different files, no interdependency).
- T008 (US2) and T009 (US3) can run in parallel with any US1 task and with each other — different files entirely.
- T011 and T012 (Polish) can run in parallel.

---

## Parallel Example: Kicking off all three stories at once

```bash
# With Foundational phase empty, all three stories can start immediately:
Task: "US1 — Add assignee resolution to create_opportunity in custom/app/services/custom/automation_rules/action_service.rb"
Task: "US2 — Add Assignee field to OpportunityBackfillModal.vue"
Task: "US3 — Extend opportunities/create Vuex action to forward assigneeId"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 3 (US1): T001-T007.
2. **STOP and VALIDATE**: Run quickstart.md Scenario 1 — confirm automation-created opportunities are now actually created and correctly assigned.
3. This alone fixes the standing bug (0% → 100% opportunity creation success for this action) and delivers automation-driven assignment.

### Incremental Delivery

1. US1 (P1) → validate → this is the MVP and the highest-value slice (bug fix + primary assignment path).
2. US2 (P2) → validate → manual reassignment now available.
3. US3 (P3) → validate → creation-time assignment now available.
4. Polish (T011-T013) → final regression pass via quickstart.md.

---

## Notes

- [P] tasks touch different files with no dependency on an incomplete task.
- [Story] labels map every user-story-phase task to its spec.md priority for traceability.
- No test-first (TDD) tasks are included per project convention (`CLAUDE.md`: avoid writing specs unless explicitly asked); T011 extends existing coverage for the one method whose behavior changes, rather than introducing a new spec file.
- Commit after each task or logical group (e.g., after T001, after the T002-T007 frontend chain, after T008, after T009-T010).
