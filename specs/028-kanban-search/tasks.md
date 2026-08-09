---
description: "Task list for Kanban Search and Filter"
---

# Tasks: Kanban Search and Filter

**Input**: Design documents from `/specs/028-kanban-search/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Tests are omitted per project constitution unless explicitly requested.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

*(No setup required; feature operates within existing Chatwoot structure)*

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T001 Update `app/javascript/dashboard/api/opportunities.js` to accept and serialize `filters` in `fetchAll` and `fetchForStage` payloads.
- [x] T002 Update `app/javascript/dashboard/routes/dashboard/opportunities/Index.vue` to maintain reactive local filter/sort state and pass it down as props.
- [x] T003 Update `app/javascript/dashboard/routes/dashboard/opportunities/OpportunityListView.vue` to watch the filters prop, reset pagination, and re-fetch `fetchAll` on change.
- [x] T004 Update `app/javascript/dashboard/routes/dashboard/opportunities/KanbanBoard.vue` and `app/javascript/dashboard/routes/dashboard/opportunities/KanbanColumn.vue` to thread the filters prop and include it in `fetchForStage` dispatches.

**Checkpoint**: Foundation ready - UI components are wired to pass filters to the API, though no UI inputs or backend filters exist yet.

---

## Phase 3: User Story 1 - Search Opportunities (Priority: P1) 🎯 MVP

**Goal**: Filter opportunities by title or contact name.

**Independent Test**: Can be fully tested by entering text in the search bar and verifying only matching opportunities are displayed.

### Implementation for User Story 1

- [x] T005 [P] [US1] Update `app/controllers/api/v1/accounts/opportunities_controller.rb` to extract filter logic into helpers and implement the `q` parameter (ILIKE match on title and contact name via left_joins).
- [x] T006 [P] [US1] Add a text search input to `app/javascript/dashboard/components/widgets/OpportunitiesViewBar.vue` that emits filter updates to the parent.

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently.

---

## Phase 4: User Story 2 - Filter by Assignee, Status, and Custom Attributes (Priority: P1)

**Goal**: Filter opportunities by assignee, status, and list-type custom attributes.

**Independent Test**: Can be fully tested by selecting values from the filter dropdowns and confirming the list/board correctly updates.

### Implementation for User Story 2

- [x] T007 [P] [US2] Update `app/controllers/api/v1/accounts/opportunities_controller.rb` to add `assignee_id`, `status`, and `custom_attributes` query filtering logic.
- [x] T008 [P] [US2] Add Assignee, Status, Stage (hidden in Kanban mode), and Custom Attribute single-select dropdowns to `app/javascript/dashboard/components/widgets/OpportunitiesViewBar.vue`.

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently.

---

## Phase 5: User Story 3 - Sort List View (Priority: P2)

**Goal**: Sort opportunities in the List view by value or last activity.

**Independent Test**: Can be fully tested by changing the sort dropdown in the List view and verifying the order updates accordingly.

### Implementation for User Story 3

- [x] T009 [P] [US3] Update `app/controllers/api/v1/accounts/opportunities_controller.rb` to implement `sort_by` mapping to `value` ascending/descending or `updated_at` descending.
- [x] T010 [P] [US3] Add a sort dropdown to `app/javascript/dashboard/components/widgets/OpportunitiesViewBar.vue` that is conditionally visible only in List mode, emitting sort changes.

**Checkpoint**: All user stories should now be independently functional.

---

## Phase N: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T011 Run `quickstart.md` validation steps locally to ensure end-to-end functionality across both views.
- [x] T012 Refactor `OpportunitiesController#index` if needed to ensure complexity remains within RuboCop limits per Phase 34 guidelines.
- [x] T013 Verify Enterprise (`enterprise/`) compatibility to ensure modifications to `OpportunitiesController` do not conflict with Enterprise overrides (Constitution Principle V).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Empty.
- **Foundational (Phase 2)**: Starts immediately. BLOCKS all user stories.
- **User Stories (Phase 3+)**: All depend on Foundational phase completion.
  - Can proceed sequentially (US1 → US2 → US3) or in parallel, though they touch the same controller and view files, so sequential implementation is recommended to avoid merge conflicts.
- **Polish (Final Phase)**: Depends on all desired user stories being complete.

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2).
- **User Story 2 (P1)**: Can start after Foundational (Phase 2).
- **User Story 3 (P2)**: Can start after Foundational (Phase 2).

### Parallel Opportunities

- Within each User Story, the backend controller update and the frontend component update are marked `[P]` because they modify different files (backend Ruby vs. frontend Vue) and can be developed simultaneously.

---

## Parallel Example: User Story 1

```bash
# Developer A implements the backend filtering:
Task: "T005 [P] [US1] Update app/controllers/api/v1/accounts/opportunities_controller.rb..."

# Developer B concurrently builds the frontend search UI:
Task: "T006 [P] [US1] Add a text search input to app/javascript/dashboard/components/widgets/OpportunitiesViewBar.vue..."
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
2. Complete Phase 3: User Story 1 (Search)
3. **STOP and VALIDATE**: Test User Story 1 independently via the Quickstart guide.

### Incremental Delivery

1. Complete Foundational → UI is wired for filters.
2. Add User Story 1 → Test search independently.
3. Add User Story 2 → Test dropdown filters independently.
4. Add User Story 3 → Test List view sorting.
5. Polish → Refactoring to respect complexity limits.
