# Tasks: Custom Date Attribute Filtering & Kanban Drag-to-Pan Navigation

**Input**: Design documents from `/specs/035-date-filter-kanban-pan/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- All descriptions include exact file paths

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify development stack and test baseline

- [x] T001 Verify backend and frontend test runners in `custom/app/controllers/api/v1/accounts/opportunities_controller.rb` and `app/javascript/dashboard/components-next/Opportunities/KanbanBoard.vue`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core filter operator definitions that enable date custom attribute filtering

- [x] T002 [P] Configure custom date operators (`equal_to`, `not_equal_to`, `is_greater_than`, `is_less_than`, `days_before`, `is_present`, `is_not_present`) in `app/javascript/dashboard/components-next/filter/operators.js`
- [x] T003 [P] Ensure custom attributes of type `date` map to `customDateOperators` in `app/javascript/dashboard/components-next/filter/helper/filterHelper.js`

**Checkpoint**: Filter definitions ready for date comparison queries

---

## Phase 3: User Story 1 - Filter Opportunities by Custom Date Attribute Comparisons (Priority: P1) 🎯 MVP

**Goal**: Enable accurate relational filtering (`>`, `<`, `=`, `!=`, `days_before`, presence) for custom date attributes on opportunities in both Kanban board and List views.

**Independent Test**: Apply filter `data_agendamento > 2026-08-01` and verify opportunities with `2026-08-13` are returned; test `<`, `=`, `!=`, and `days_before` queries.

### Implementation for User Story 1

- [x] T004 [US1] Implement safe PostgreSQL date regex casting and comparison query builder in `custom/app/controllers/api/v1/accounts/opportunities_controller.rb`
- [x] T005 [US1] Support `is_greater_than`, `is_less_than`, `equal_to`, `not_equal_to`, and `days_before` operators for custom attributes in `custom/app/controllers/api/v1/accounts/opportunities_controller.rb`
- [x] T006 [US1] Add regression RSpec tests for custom date attribute filtering in `spec/controllers/api/v1/accounts/opportunities_controller_spec.rb`

**Checkpoint**: User Story 1 is fully functional and testable independently in both Kanban and List views.

---

## Phase 4: User Story 2 - Desktop Click-and-Drag Pan Navigation & Hidden Scrollbar (Priority: P2)

**Goal**: Allow users to click and drag on empty areas of the Kanban board to scroll horizontally across lanes smoothly with immediate stop on release, and visually hide the native horizontal scrollbar.

**Independent Test**: Drag horizontally across lanes on desktop with the mouse, verify smooth translation and immediate stop on mouse up, ensure card drag-and-drop is unaffected, and verify the bottom horizontal scrollbar is hidden.

### Implementation for User Story 2

- [x] T007 [P] [US2] Visually hide the native horizontal scrollbar on the board container using Tailwind utilities `[scrollbar-width:none] [-ms-overflow-style:none] [&::-webkit-scrollbar]:hidden` in `app/javascript/dashboard/components-next/Opportunities/KanbanBoard.vue`
- [x] T008 [US2] Implement mouse pan handlers (`onMouseDown`, `onMouseMove`, `onMouseUp`, `onMouseLeave`) with interactive element isolation in `app/javascript/dashboard/components-next/Opportunities/KanbanBoard.vue`
- [x] T009 [US2] Ensure drag threshold prevents click hijacking on buttons, links, and cards in `app/javascript/dashboard/components-next/Opportunities/KanbanBoard.vue`
- [x] T010 [US2] Add unit tests for board drag-to-pan event behavior in `app/javascript/dashboard/components-next/Opportunities/specs/KanbanBoard.spec.js`

**Checkpoint**: User Stories 1 AND 2 work together independently.

---

## Phase 5: User Story 3 - Mobile / Touch Drag-to-Pan Navigation (Priority: P3)

**Goal**: Support touch-and-swipe horizontal navigation on touch devices while preserving card interactions.

**Independent Test**: On a mobile touch screen or emulator, touch and swipe across lanes to pan horizontally.

### Implementation for User Story 3

- [x] T011 [US3] Verify and enhance touch event handling for horizontal swiping on mobile viewports in `app/javascript/dashboard/components-next/Opportunities/KanbanBoard.vue`

**Checkpoint**: All user stories functional across desktop and mobile devices.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Validation, linting, and final verification

- [x] T012 [P] Verify synchronous translations in `app/javascript/dashboard/i18n/locale/en/opportunities.json` and `app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json`
- [x] T013 Run full backend and frontend test suites (`bundle exec rspec`, `pnpm test`)
- [x] T014 Run linters (`bundle exec rubocop -a`, `pnpm eslint`)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Can start immediately
- **Foundational (Phase 2)**: Prerequisite for User Story 1 frontend filtering
- **User Stories (Phase 3+)**:
  - **User Story 1 (P1)**: Backend date evaluation & frontend operator support (MVP)
  - **User Story 2 (P2)**: Kanban pan navigation & hidden scrollbar
  - **User Story 3 (P3)**: Mobile touch verification
- **Polish (Phase 6)**: Final linting and end-to-end verification

### Parallel Opportunities

- T002 and T003 can be executed in parallel (frontend filter operators)
- T007 (Tailwind scrollbar hiding) can be executed in parallel with backend tasks
- T010 and T012 can run in parallel during polish phase

---

## Implementation Strategy

### MVP First (User Story 1 Only)
1. Complete Foundational (T002, T003)
2. Complete Backend date filtering (T004, T005, T006)
3. Validate date queries with `>` and `<` in browser and specs

### Incremental Delivery
1. Deliver MVP (Date comparison filter bugfix)
2. Deliver User Story 2 (Desktop Drag-to-Pan & Hidden Scrollbar)
3. Deliver User Story 3 (Mobile Touch verification)
4. Deliver Polish (Linters, test suites, i18n)
