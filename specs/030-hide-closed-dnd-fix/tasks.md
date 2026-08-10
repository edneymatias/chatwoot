---
description: "Task list for Hide Closed Opportunities by Default, and Fix Win/Loss Drag-and-Drop Bug"
---

# Tasks: Hide Closed Opportunities by Default, and Fix Win/Loss Drag-and-Drop Bug

**Input**: Design documents from `specs/030-hide-closed-dnd-fix/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/opportunities-index.md

**Tests**: A backend request spec is required for User Story 1/2 (the spec explicitly calls this
out under "Testing / specs affected"). No frontend spec is added, per project convention (specs
only written when explicitly requested) and because no existing frontend spec covers the
`KanbanStatusBar`/`KanbanColumn` drag interaction to extend.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

---

## Phase 1: Setup

- [x] T001 Verify project environment is running (`docker compose up -d`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The single backend default-status change that User Story 1 and User Story 2 both
rely on. Must land before either story can be verified.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T002 Add default `status: 'open'` scoping to `apply_filters` in
      `custom/app/controllers/api/v1/accounts/opportunities_controller.rb`, mirroring
      `ConversationFinder::DEFAULT_STATUS` (`app/finders/conversation_finder.rb:4,162-166`):
      skip the default when `params[:status] == 'all'`; apply `params[:status] ||
      DEFAULT_STATUS` when `params[:status]` is blank and no `payload` condition targets
      `status`; leave `payload`-based status conditions (already handled at lines 77-120) as the
      overriding mechanism when present. Define `DEFAULT_STATUS = 'open'.freeze` as a controller
      constant.

**Checkpoint**: Foundation ready - the index endpoint now defaults to open-only. User story
verification can now begin.

---

## Phase 3: User Story 1 - Board shows only active deals by default (Priority: P1) 🎯 MVP

**Goal**: Kanban board and List view show only open opportunities when no filter is applied.

**Independent Test**: Create opportunities with open/won/lost statuses, open the Kanban board and
List view with no filters applied, and confirm only open opportunities are visible.

### Tests for User Story 1

- [x] T003 [P] [US1] Add request spec case asserting `GET
      /api/v1/accounts/{account.id}/opportunities` with no status param excludes won/lost
      opportunities, in `spec/requests/api/v1/accounts/opportunities_controller_spec.rb`
      (extends the existing `GET /api/v1/accounts/{account.id}/opportunities` describe block
      starting at line 24)

### Implementation for User Story 1

- [x] T004 [US1] Manually verify `KanbanColumn.vue`'s `fetchForStage` dispatch
      (`app/javascript/dashboard/components-next/Opportunities/KanbanColumn.vue:48-55`) and
      `OpportunityListView.vue`'s default fetch call already omit a status param and therefore
      inherit the new backend default with no code change required (per spec FR-001); no file
      edit expected — confirm via `quickstart.md` step 1-2, and confirm no visual indicator (badge,
      label, etc.) appears anywhere on the unfiltered board/list to mark the default as active (per
      spec FR-005)

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently.

---

## Phase 4: User Story 2 - Closed deals remain discoverable via filters (Priority: P2)

**Goal**: Users can still see won/lost opportunities by using the existing status filter.

**Independent Test**: Apply the existing status filter (`won`, `lost`, or all statuses) on the
Kanban board or List view and confirm the matching opportunities appear.

### Tests for User Story 2

- [x] T005 [US2] Add request spec cases asserting `status=all` and an explicit
      `status=won`/`status=lost` param each override the new default and return the expected
      opportunities, in `spec/requests/api/v1/accounts/opportunities_controller_spec.rb`

### Implementation for User Story 2

- [x] T006 [US2] Manually verify `OpportunitiesFilter.vue`'s existing `status` multiSelect filter
      (`app/javascript/dashboard/components-next/filter/OpportunitiesFilter.vue`) already
      produces a `payload` condition that overrides the new default per FR-003; no file edit
      expected — confirm via `quickstart.md` steps 3-4

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently.

---

## Phase 5: User Story 3 - Contact profile still shows full opportunity history (Priority: P2)

**Goal**: A contact's opportunity history panel continues to show opportunities of every status.

**Independent Test**: Open a contact's profile panel with open/won/lost opportunities and confirm
all of them are listed.

### Implementation for User Story 3

- [x] T007 [US3] Add `status: 'all'` to the `opportunitiesAPI.get(...)` params in the
      `fetchForContact` action in
      `app/javascript/dashboard/store/modules/opportunities/actions.js:68-70`

**Checkpoint**: At this point, User Stories 1, 2, AND 3 should all work independently.

---

## Phase 6: User Story 4 - Dropping a card on the won/lost zone changes only its status (Priority: P1)

**Goal**: Dragging a card onto the won/lost drop zone changes only `status`, never
`pipeline_stage_id`, by eliminating the drag-target bounding-rect overlap between the status bar
and the pipeline stage columns.

**Independent Test**: Drag a card from any pipeline stage column onto the won/lost drop zone and
confirm afterward that only `status` changed and `pipeline_stage_id` is unchanged.

### Implementation for User Story 4

- [x] T008 [US4] Reserve dedicated layout space for the won/lost drop zones instead of floating
      them as a `position: absolute` overlay, in
      `app/javascript/dashboard/components-next/Opportunities/KanbanStatusBar.vue:53-54`
      (replace the `absolute bottom-6 left-1/2 transform -translate-x-1/2 ... z-50` wrapper
      classes with in-flow layout classes appropriate to being rendered as a normal flex child)
- [x] T009 [US4] Adjust `KanbanBoard.vue`'s template so the columns' scroll container
      (`app/javascript/dashboard/components-next/Opportunities/KanbanBoard.vue:220`, `class="flex
      flex-grow overflow-x-auto p-4 gap-4"`) and the `KanbanStatusBar` render as non-overlapping
      flex siblings while `isCardDragging` is true, so their `Draggable` lists (both
      `group="kanban-cards"`) no longer share overlapping bounding rects (depends on T008)

**Checkpoint**: All four user stories should now be independently functional.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final validation across all stories

- [x] T010 Run `quickstart.md` manual validation scenarios end-to-end (default scoping, filter
      override, contact panel exception, and drag-and-drop from multiple pipeline stage columns)
- [x] T011 Run `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec
      spec/requests/api/v1/accounts/opportunities_controller_spec.rb`
- [x] T012 Run `docker compose exec vite pnpm eslint` and `docker compose exec rails bundle exec
      rubocop -a` on changed files

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS User Story 1 and User Story 2
  (both rely on the same default-status change in `apply_filters`)
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2)
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2); independent of User Story 1
- **User Story 3 (Phase 5)**: Independent of Foundational, US1, and US2 - touches only
  `fetchForContact`, a separate code path
- **User Story 4 (Phase 6)**: Fully independent of Phases 2-5 - touches only
  `KanbanStatusBar.vue`/`KanbanBoard.vue` layout, unrelated files
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### Within Each User Story

- T003/T005 (request spec cases) can be written alongside or immediately after T002, since they
  assert on the same endpoint change
- T008 before T009 (the status bar's own layout must change before the board's container is
  adjusted to match)

### Parallel Opportunities

- T003 and T005 both add `it` blocks to the same spec file, so they're sequenced (not `[P]`) to
  avoid concurrent-edit conflicts, even though the blocks themselves are independent
- User Story 3 (T007) and User Story 4 (T008, T009) can be implemented in parallel with each
  other and with Phases 2-4, since none share a file
- T012 lint tasks can run in parallel across Ruby and JS toolchains

---

## Parallel Example: Foundational + User Story 1/2 tests

```bash
# After T002 lands, both story-specific spec additions can be written together:
Task: "Add request spec case for default status exclusion in spec/requests/api/v1/accounts/opportunities_controller_spec.rb"
Task: "Add request spec cases for status=all/explicit status override in spec/requests/api/v1/accounts/opportunities_controller_spec.rb"
```

## Parallel Example: User Story 3 + User Story 4

```bash
# These touch entirely different files and can proceed independently of each other
# and of the backend Foundational phase:
Task: "Add status: 'all' to fetchForContact in app/javascript/dashboard/store/modules/opportunities/actions.js"
Task: "Reserve layout space for won/lost drop zones in KanbanStatusBar.vue and KanbanBoard.vue"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks US1 and US2)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test User Story 1 independently via `quickstart.md`
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → default-open scoping live at the API layer
2. Add User Story 1 → verify board/list default → Deploy/Demo (MVP!)
3. Add User Story 2 → verify filter override still works → Deploy/Demo
4. Add User Story 3 → verify contact panel exception → Deploy/Demo
5. Add User Story 4 → verify drag-and-drop no longer corrupts pipeline stage → Deploy/Demo
6. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files/blocks, no dependencies
- [Story] label maps task to specific user story for traceability
- User Story 4 is entirely independent of the other three (different files, different bug class)
  and can be implemented and shipped first, last, or in parallel with no risk of conflict
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
