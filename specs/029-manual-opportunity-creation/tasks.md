---
description: "Task list for Manual Opportunity Creation and Conversation Start"
---

# Tasks: Manual Opportunity Creation and Conversation Start

**Input**: Design documents from `specs/029-manual-opportunity-creation/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/api.md

**Tests**: Tests are excluded per the project constitution ("Avoid writing specs unless explicitly asked").

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [x] T001 Verify project environment is running (`docker compose up -d`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T002 Add validation for `origin_conversation_id` immutability in `app/models/opportunity.rb`
- [x] T003 [P] Update `opportunity_update_params` to permit `origin_conversation_id` in `app/controllers/api/v1/accounts/opportunities_controller.rb`

**Checkpoint**: Foundation ready - backend supports linking conversations safely. User story implementation can now begin.

---

## Phase 3: User Story 1 - Create Opportunity Manually (Priority: P1) 🎯 MVP

**Goal**: Users need to create an opportunity independently of a specific kanban board column.

**Independent Test**: Can be fully tested by navigating to the Opportunities list view and clicking "add opportunity" to create an opportunity without a pre-selected stage.

### Implementation for User Story 1

- [x] T004 [P] [US1] Enable "add opportunity" button and wire it to open modal without `defaultStageId` in `app/javascript/dashboard/routes/dashboard/opportunities/OpportunitiesViewBar.vue`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently.

---

## Phase 4: User Story 2 - Start Conversation from an Opportunity (Priority: P1)

**Goal**: Users need to initiate a conversation for opportunities that have no conversation linked.

**Independent Test**: Can be tested by creating an opportunity without a conversation, hovering over it to see the action button, and starting a conversation from there.

### Implementation for User Story 2

- [x] T005 [P] [US2] Create component wrapping `ComposeConversation` with Vuex watch logic to dispatch `opportunities/update` in `app/javascript/dashboard/components/widgets/conversation/StartOpportunityConversationButton.vue`
- [x] T006 [US2] Render start conversation action for unlinked opportunities in `app/javascript/dashboard/routes/dashboard/opportunities/KanbanCard.vue`
- [x] T007 [US2] Render start conversation action for unlinked opportunities in `app/javascript/dashboard/routes/dashboard/opportunities/OpportunityListRow.vue`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T008 Run quickstart.md manual validation scenarios

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can proceed in parallel (if staffed)
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P1)**: Can start after Foundational (Phase 2) - No dependencies on US1, independently testable

### Within Each User Story

- UI components before integration
- Story complete before moving to next priority

### Parallel Opportunities

- Foundational tasks marked [P] can run in parallel (within Phase 2)
- Once Foundational phase completes, User Story 1 and User Story 2 can be developed in parallel
- Adding the action to `KanbanCard.vue` and `OpportunityListRow.vue` can run in parallel

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test User Story 1 independently
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Test independently → Deploy/Demo
4. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Avoid writing specs unless explicitly asked per project constitution
- Stop at any checkpoint to validate story independently
