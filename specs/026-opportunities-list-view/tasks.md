---
description: "Task list for Kanban List View implementation"
---

# Tasks: Kanban List View

**Input**: Design documents from `/specs/026-opportunities-list-view/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Create skeleton Vue component files for `OpportunitiesViewBar.vue`, `OpportunityListView.vue`, and `OpportunityListRow.vue` in `app/javascript/dashboard/routes/dashboard/opportunities/components/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core Vuex state infrastructure that MUST be complete before the UI can fetch or display the flat list.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T002 [P] Update state to include `allIds`, `pagination.all`, and `isFetchingAll` in `app/javascript/dashboard/store/modules/opportunities/state.js`
- [x] T003 [P] Add `allCards`, `hasMoreAll`, and `isFetchingAll` getters in `app/javascript/dashboard/store/modules/opportunities/getters.js`
- [x] T004 [P] Add `SET_IS_FETCHING_ALL` and `SET_ALL_CARDS` mutations in `app/javascript/dashboard/store/modules/opportunities/mutations.js`
- [x] T005 Implement `fetchAll` action without a stage filter in `app/javascript/dashboard/store/modules/opportunities/actions.js`

**Checkpoint**: Foundation ready - Vuex is now capable of managing the flat list state independently of Kanban stages.

---

## Phase 3: User Story 1 - Toggle between List and Kanban views (Priority: P1) 🎯 MVP

**Goal**: Allow users to toggle between a list view and a Kanban board, saving their preference.

**Independent Test**: Can be tested by clicking the list and Kanban icons on the view bar and verifying layout changes and persistence across reloads.

### Implementation for User Story 1

- [x] T006 [US1] Implement toggle buttons and the disabled "add opportunity" button in `app/javascript/dashboard/routes/dashboard/opportunities/components/OpportunitiesViewBar.vue`
- [x] T007 [US1] Integrate `OpportunitiesViewBar` and `viewMode` (with `localStorage` persistence) into `app/javascript/dashboard/routes/dashboard/opportunities/Index.vue`

**Checkpoint**: At this point, the view bar is visible and the view mode toggles, but the list view itself will be empty or a placeholder.

---

## Phase 4: User Story 2 - View opportunities in a dense list (Priority: P1)

**Goal**: See all opportunities across all stages in a single, dense list with infinite scroll.

**Independent Test**: Switch to list view and verify rows display correct data, and scrolling to the bottom loads more rows. Clicking a row with a conversation should open the drawer.

### Implementation for User Story 2

- [x] T008 [P] [US2] Implement row display (title, contact, assignee, stage, value, status, timestamp) in `app/javascript/dashboard/routes/dashboard/opportunities/components/OpportunityListRow.vue`
- [x] T009 [US2] Implement infinite scroll calling the `fetchAll` action and rendering rows in `app/javascript/dashboard/routes/dashboard/opportunities/components/OpportunityListView.vue`
- [x] T010 [US2] Connect `OpportunityListView.vue` rendering and wire the conversation drawer click event in `app/javascript/dashboard/routes/dashboard/opportunities/Index.vue`

**Checkpoint**: List view now renders real data, supports infinite scroll, and opens the conversation drawer.

---

## Phase 5: User Story 3 - View pipeline aggregates (Priority: P2)

**Goal**: See total lead count and total value of all opportunities in the view bar.

**Independent Test**: Check the view bar in either view and ensure the totals match the sum of all columns.

### Implementation for User Story 3

- [x] T011 [US3] Compute and display total lead count and currency-formatted value from `pipelineStages` in `app/javascript/dashboard/routes/dashboard/opportunities/components/OpportunitiesViewBar.vue`

**Checkpoint**: Pipeline aggregates are visible and accurate.

---

## Phase N: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and final validation.

- [x] T012 Run quickstart.md validation to verify view toggle, persistence, infinite scroll, and read-only constraints work perfectly end-to-end.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - US1 (Phase 3) must be done before US2 (Phase 4) because US2's list view needs the toggle from US1 to be accessible.
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2)
- **User Story 2 (P1)**: Can start after User Story 1 (needs the toggle to access the view)
- **User Story 3 (P2)**: Can start any time after User Story 1 (needs the view bar component)

### Parallel Opportunities

- All Foundational getters, mutations, and state updates (T002, T003, T004) can run in parallel.
- US3 (T011) can run in parallel with US2 (T008, T009) once the view bar exists from US1.

---

## Implementation Strategy

### Incremental Delivery

1. Complete Setup + Foundational (Vuex updates).
2. Add User Story 1 → Adds the View Bar and toggle state (MVP).
3. Add User Story 2 → Wires up the actual list view with data.
4. Add User Story 3 → Adds the aggregate summary to the View Bar.
5. Final Validation.

## Phase 6: Convergence

- [x] T013 Disable the "add opportunity" button and add a "Coming soon" tooltip in `OpportunitiesViewBar.vue` per FR-005 (missing)
- [x] T014 Implement infinite scrolling to automatically load more opportunities as the user scrolls in `OpportunityListView.vue` per FR-010 (contradicts)

## Phase 7: Convergence

- [x] T015 Disable the "add opportunity" button and add a "Coming soon" tooltip in `OpportunitiesViewBar.vue` per FR-005 (missing)
