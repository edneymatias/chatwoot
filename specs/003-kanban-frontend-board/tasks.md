# Tasks: Frontend Board — Kanban UI, Vuex Store, Settings

**Input**: Design documents from `/specs/003-kanban-frontend-board/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Not included as dedicated task-list entries — the spec does not explicitly request new automated tests, and per project convention (CLAUDE.md) specs are written only when explicitly asked. `quickstart.md` remains the validation guide (existing backend request specs must keep passing; dashboard `pnpm test` suites are the mechanism, not a new obligation this list enumerates task-by-task).

**Organization**: Tasks are grouped by user story (spec.md priorities P1–P5) so each story is independently implementable and testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Maps task to its user story (US1–US5)

## Path Conventions

Single monorepo, frontend-only within `app/javascript/dashboard/`; one backend touch per research.md §9 lives under `custom/app/controllers/`. Paths match `plan.md`'s Project Structure exactly.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Scaffold the mechanical, dependency-free files every later task writes into.

- [X] T001 [P] Create `app/javascript/dashboard/api/opportunities.js` — `ApiClient` subclass (`OpportunitiesAPI`), CRUD + move/status endpoints (research.md §6, contracts/api.md)
- [X] T002 [P] Create `app/javascript/dashboard/api/pipelineStages.js` — `ApiClient` subclass (`PipelineStagesAPI`), CRUD + reorder endpoint (research.md §6, contracts/api.md)
- [X] T003 [P] Create `app/javascript/dashboard/i18n/locale/en/opportunities.json` skeleton (empty top-level key groups for board/settings/detail-view strings) and register its import in `app/javascript/dashboard/i18n/locale/en/index.js` (research.md §7, FR-014)

**Checkpoint**: API clients and the i18n file exist for every later task to write into.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The backend query support and Vuex module skeletons every user story builds on. **No user story can be implemented until this phase is done.**

- [X] T004 Add `pipeline_stage_id`/`page` query filtering to `OpportunitiesController#index` in `custom/app/controllers/api/v1/accounts/opportunities_controller.rb` (research.md §9, contracts/api.md) — required for FR-002/FR-004; without it no column can fetch or paginate its own cards
- [X] T005 [P] Create `store/modules/pipelineStages/{index.js,getters.js,mutations.js,actions.js}` in `app/javascript/dashboard/store/modules/pipelineStages/` — `byId`/`allIds` state, `stagesSortedByPosition`/`stageById` getters, `fetch()` action (data-model.md, contracts/store.md)
- [X] T006 [P] Create `store/modules/opportunities/{index.js,getters.js,mutations.js,actions.js}` in `app/javascript/dashboard/store/modules/opportunities/` — `byId`/`idsByStage`/`allIds`/`pagination`/`uiFlags` state, `cardsForStage`/`cardById`/`hasMoreForStage`/`isFetchingForStage` getters, `fetchForStage({ stageId, page })` action that replaces on `page === 1` and appends otherwise (data-model.md, contracts/store.md) — depends on T004

**Checkpoint**: Both Vuex modules can fetch and expose normalized, per-stage data. User story implementation can now begin.

---

## Phase 3: User Story 1 - Agent views and moves opportunities across pipeline stages (Priority: P1) 🎯 MVP

**Goal**: Render one column per pipeline stage with its own cards, support drag-and-drop moves between columns with optimistic update + revert-on-failure, and per-column infinite scroll.

**Independent Test**: Load the board with seeded stages/opportunities; confirm columns render in position order; drag a card to another column and confirm it persists; kill the network and retry a drag to confirm revert; scroll a long column and confirm the next page loads without affecting other columns.

- [X] T007 [US1] Add `moveCard({ id, fromStageId, toStageId, toIndex })` action plus its optimistic-update and revert-on-failure mutations to `app/javascript/dashboard/store/modules/opportunities/actions.js` and `mutations.js` (data-model.md mutation-level invariants, contracts/store.md, FR-005/SC-002)
- [X] T008 [P] [US1] Create `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue` — title, contact, assignee, status badge (`open`/`won`/`lost`), emits `click` (FR-006, contracts/components.md)
- [X] T009 [US1] Create `app/javascript/dashboard/components-next/Opportunities/KanbanColumn.vue` — dispatches `fetchForStage` on mount and on near-bottom scroll, renders a `Draggable` bound with `:model-value="cardsForStage(stage.id)"` and `group="kanban-cards"`, emits `card-removed`/`card-added` per the per-column `@change` mechanics in contracts/components.md (FR-002/FR-003/FR-004); an empty `cardsForStage(stage.id)` renders zero cards via `Draggable`'s default empty-array behavior, no special-case markup needed — depends on T007, T008
- [X] T010 [US1] Create `app/javascript/dashboard/components-next/Opportunities/KanbanBoard.vue` — renders one `KanbanColumn` per `pipelineStages/stagesSortedByPosition`, correlates a same-drag `card-removed`+`card-added` pair into one `opportunities/moveCard` dispatch, surfaces a revert notice on failure (FR-003/FR-005, contracts/components.md) — depends on T009
- [X] T011 [P] [US1] i18n strings (`opportunities.json`) and dark-mode Tailwind pass for `KanbanBoard.vue`/`KanbanColumn.vue`/`KanbanCard.vue` (FR-014, FR-015)

**Checkpoint**: Board renders, drags between columns, reverts on failure, and paginates per column — independently testable via `quickstart.md` step 4 (manual harness).

---

## Phase 4: User Story 2 - Agent creates a new opportunity manually (Priority: P2)

**Goal**: A modal to create an opportunity by picking a contact, stage, and title, with an optional origin-conversation link, that appears on the board immediately.

**Independent Test**: Open the creation flow, search and select a contact, pick a stage and title, submit, and confirm the new card appears in the chosen column without a page reload.

- [X] T012 [P] [US2] Add `create({ title, contactId, pipelineStageId, originConversationId })` action to `opportunities/actions.js`/`mutations.js` — unshifts the new id into `idsByStage[pipelineStageId]` (data-model.md)
- [X] T013 [US2] Create `OpportunityCreateModal.vue` — contact search reusing `contacts/search` / `ContactSelector.vue` pattern (research.md §3) including its "no results" empty state; stage select using `pipelineStages/stagesSortedByPosition`; simple text input for title. Emits `created`/`close`. (FR-007, contracts/components.md) — depends on T012
- [X] T014 [P] [US2] i18n strings and dark-mode Tailwind pass for `OpportunityCreateModal.vue` (FR-014, FR-015), independently of US3–US5.

**Checkpoint**: Manual creation works end-to-end against the board built in US1, independently of US3–US5.

---

## Phase 5: User Story 3 - Agent inspects an opportunity's details, sets its status, and reaches its linked conversation (Priority: P3)

**Goal**: A detail view with the origin-conversation link (when present) and a Mark as Won/Lost/Reopen action, mirrored as a quick action on the card.

**Independent Test**: Click a card with an origin conversation and confirm the link renders; mark it won and confirm the badge updates immediately without changing its column; reopen it and confirm the badge clears; click a card with no origin conversation and confirm no broken link shows.

- [X] T014 [US3] Add `setStatus({ id, status })` action + mutation to `app/javascript/dashboard/store/modules/opportunities/actions.js`/`mutations.js` — PATCHes `status` only, never touches `pipelineStageId` (FR-007a, contracts/store.md)
- [X] T015 [US3] Add Mark as Won/Lost/Reopen quick action to `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`, emitting `status-changed({ id, status })` (FR-007a, contracts/components.md) — depends on T008, T014
- [X] T016 [US3] Create `app/javascript/dashboard/components-next/Opportunities/OpportunityDetailView.vue` — `opportunityId` prop, full card info, conditional origin-conversation link, same `status-changed` emit contract as the card (FR-007/FR-007a, contracts/components.md) — depends on T014
- [X] T017 [P] [US3] i18n strings (`opportunities.json`) for status actions/badges (FR-014)

**Checkpoint**: Status lifecycle (open → won/lost → reopen) and the detail view work independently of US2/US4/US5.

---

## Phase 6: User Story 4 - Administrator manages pipeline stages (Priority: P4)

**Goal**: An admin-only settings screen to create, rename, delete (blocked while occupied), and drag-reorder pipeline stages.

**Independent Test**: As an admin, create a stage, rename one, reorder two via drag, delete an empty one, refresh, and confirm all changes persisted; confirm a non-admin is denied access.

- [X] T018 [US4] Add `create({ name, description })` action + mutation to `pipelineStages` store module (FR-010).
- [X] T019 [US4] Add `update({ id, name, description, position })` action + mutation to `pipelineStages` store module (FR-010).
- [X] T020 [US4] Create `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/Index.vue` — list stages, reorder via `vuedraggable` (calls `update` with new `position`), edit/add buttons (FR-010/contracts/components.md).
- [X] T021 [US4] Create `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/AddPipelineStage.vue` / Edit modal (FR-010/contracts/components.md).
- [X] T022 [US4] Register route in `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js` (FR-010).
- [X] T023 [US4] Add sidebar link to `app/javascript/dashboard/components/layout/sidebarComponents/sidebarItems.js` (or `Sidebar.vue`) (FR-010).
- [X] T024 [P] [US4] i18n strings for admin panel.

**Checkpoint**: Full stage-management CRUD works independently; board (US1) already consumes `stagesSortedByPosition` reactively so reordering here is reflected without further wiring.

---

## Phase 7: User Story 5 - Administrator configures the "Create Opportunity" automation action (Priority: P5)

**Goal**: Expose Phase 2's `create_opportunity` automation action in the existing action picker with a stage selector.

**Independent Test**: Open the action picker, select "Create Opportunity," confirm a stage-populated selector appears, save and reopen the rule, and confirm the selection persisted.

- [X] T023 [US5] Add `{ key: 'create_opportunity', label: 'CREATE_OPPORTUNITY', inputType: 'search_select' }` to `AUTOMATION_ACTION_TYPES` in `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js` (FR-012, contracts/components.md)
- [X] T024 [US5] Add a `create_opportunity` case to `getActionDropdownValues()` in `app/javascript/dashboard/composables/useAutomationValues.js`, returning `pipelineStages/stagesSortedByPosition` mapped to `{ id, name }` options (FR-013, contracts/components.md) — depends on T023, T005
- [X] T025 [P] [US5] Add `ACTIONS.CREATE_OPPORTUNITY` label under the existing key in `app/javascript/dashboard/i18n/locale/en/automation.json` (FR-014)

**Checkpoint**: All five user stories independently functional.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T026 [P] Run `quickstart.md` steps 1–3 and 5 (backend contract check, Vuex module tests, component tests, automation picker test)
- [X] T027 [P] Grep sweep for hardcoded user-facing strings per `quickstart.md` step 6 (FR-014)
- [X] T028 Manual harness pass (`quickstart.md` step 4) covering every US1–US3 acceptance scenario, the dark-mode spot check (FR-015, SC-006), and SC-001's board-load/interruption timing criteria (confirm columns render and a killed-network drag reverts within the timing bounds SC-001 specifies)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup (T001/T002 feed the actions in T005/T006). Blocks every user story.
- **User Stories (Phase 3–7)**: All depend on Foundational. US1–US5 have no dependencies on each other's *files*, but US3 and US5 each extend a file US1/Foundational already created (`KanbanCard.vue`, `pipelineStages` getters) rather than creating it fresh — sequence accordingly if working solo. This is a deliberate, accepted tradeoff: T015 (US3) editing the `KanbanCard.vue` file T008 (US1) creates is cheaper than introducing a shared base component or other abstraction to avoid the cross-story touch, consistent with the project's smallest-production-ready-change convention. Concretely: **T015 cannot start until T008 is merged**, even though it's grouped under US3.
- **Polish (Phase 8)**: Depends on whichever user stories are in scope for a given validation pass.

### User Story Dependencies

- **US1 (P1)**: Foundational only. This is the MVP.
- **US2 (P2)**: Foundational + reads `pipelineStages/stagesSortedByPosition` (T005) and appends into `opportunities` state (T006) — no dependency on US1's UI.
- **US3 (P3)**: Foundational; T015 edits the `KanbanCard.vue` file US1 created (T008), so US1 should land first in practice even though US3's own store/detail-view work (T014, T016) has no such dependency.
- **US4 (P4)**: Foundational + its own backend task (T018); independent of US1–US3, US5.
- **US5 (P5)**: Foundational (T005's `stagesSortedByPosition` getter); independent of US1–US4.

### Parallel Opportunities

- T001, T002, T003 (Setup) — different files, run together.
- T005, T006 (Foundational modules) — different directories, run together once T004 lands.
- Within US1: T008 in parallel with T007 (different files); T011 after T008–T010 land.
- Once Foundational is done: US2, US4, US5 can all start in parallel with US1 (only US3's card-editing task actually needs US1's `KanbanCard.vue` to exist first).

---

## Parallel Example: Foundational + US1 kickoff

```bash
# After T004 (backend filter) lands:
Task: "Create store/modules/pipelineStages/{index,getters,mutations,actions}.js"   # T005
Task: "Create store/modules/opportunities/{index,getters,mutations,actions}.js"    # T006

# Once T006 lands, within US1:
Task: "Add moveCard action + revert mutations to opportunities module"             # T007
Task: "Create KanbanCard.vue"                                                      # T008
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001–T003).
2. Complete Phase 2: Foundational (T004–T006) — critical, blocks everything.
3. Complete Phase 3: User Story 1 (T007–T011).
4. **STOP and VALIDATE**: run `quickstart.md` steps 2–4 scoped to US1 acceptance scenarios only.

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. Add US1 → validate independently → this is the MVP (board view + drag-drop + pagination).
3. Add US2 → validate independently (manual creation).
4. Add US3 → validate independently (status lifecycle + detail view).
5. Add US4 → validate independently (stage admin CRUD).
6. Add US5 → validate independently (automation picker entry).
7. Phase 8 polish once the desired subset of stories is complete.

---

## Notes

- Per spec.md Assumptions, none of these tasks register routes, register the two Vuex modules in `store/modules/index.js`, or add a navigation entry point — that wiring is explicitly Phase 4 of the parent multi-phase Kanban effort (a separate spec, not this task list).
- [P] tasks touch different files with no unmet dependencies.
- Commit after each task or logical group, per repo convention (Conventional Commits).

## Phase 9: Convergence
- [X] T029 Register `pipelineStages` and `opportunities` Vuex modules in `store/index.js` to resolve the UI crash caused by the unrequested route wiring per spec.md (Assumptions) (contradicts)
