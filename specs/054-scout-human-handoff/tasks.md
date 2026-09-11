# Tasks: Scout Human Handoff on Manual Intervention

**Input**: Design documents from `/specs/054-scout-human-handoff/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, quickstart.md

**Tests**: RSpec tests specified for each user story under `custom/spec/models/custom/message_spec.rb`.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Rails monolith (Chatwoot)**: `custom/app/models/custom/`, `custom/spec/models/custom/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and directory structure verification

- [X] T001 [P] Verify directory structure for custom model extensions and specs in custom/app/models/custom/ and custom/spec/models/custom/

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 Create base Custom::Message prepended module skeleton with mark_pending_conversation_as_open_for_human_response in custom/app/models/custom/message.rb

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Human agent takes over a pending Scout conversation (Priority: P1) 🎯 MVP

**Goal**: Synchronously transition conversation status from `pending` to `open` when a human agent sends a public reply in a Scout-enabled inbox, preventing any queued Scout reply from firing.

**Independent Test**: In an inbox with an enabled Scout, create a pending conversation and author a public outgoing message from a human agent; verify `conversation.reload.open?` is true and queued Scout reply cannot be delivered.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T003 [P] [US1] Add RSpec unit tests for Scout human takeover on public outgoing replies, including a case asserting a Scout-authored outgoing message (sender: nil) on a pending conversation does not trigger the reopen (FR-006), in custom/spec/models/custom/message_spec.rb

### Implementation for User Story 1

- [X] T004 [US1] Implement scout_pending_conversation? predicate and synchronous conversation.open! transition in custom/app/models/custom/message.rb

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Private notes do not trigger handoff (Priority: P2)

**Goal**: Ensure private notes created by human agents do not trigger status transitions on pending Scout conversations.

**Independent Test**: In an inbox with an enabled Scout, create a pending conversation and author a private outgoing message from a human agent; verify `conversation.reload.pending?` is true.

### Tests for User Story 2 ⚠️

- [X] T005 [US2] Add RSpec unit tests verifying private notes do not reopen pending Scout conversations in custom/spec/models/custom/message_spec.rb

### Implementation for User Story 2

- [X] T006 [US2] Guard mark_pending_conversation_as_open_for_human_response against private notes in custom/app/models/custom/message.rb

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Conversations without Scout are unaffected (Priority: P3)

**Goal**: Ensure conversations without Scout (or inboxes where Scout is disabled) preserve standard status behavior unchanged without side effects.

**Independent Test**: In an inbox without Scout or with Scout disabled, create a pending conversation and author a public outgoing message from a human agent; verify status behavior matches existing non-Scout behavior.

### Tests for User Story 3 ⚠️

- [X] T007 [US3] Add RSpec unit tests verifying conversations with disabled Scout or without Scout are unaffected in custom/spec/models/custom/message_spec.rb

### Implementation for User Story 3

- [X] T008 [US3] Verify Custom::Message composes with Enterprise::Message via super without regression in custom/spec/models/custom/message_spec.rb

**Checkpoint**: All user stories should now be independently functional

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Code quality validation, test suite execution, and quickstart verification

- [X] T009 [P] Run RuboCop lint checks on custom models and specs via docker compose exec rails bundle exec rubocop custom/app/models/custom/message.rb custom/spec/models/custom/message_spec.rb
- [X] T010 [P] Run full targeted RSpec test suite covering custom models and core message specs via docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/ spec/models/message_spec.rb
- [X] T011 Validate manual verification scenarios per specs/054-scout-human-handoff/quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion (T001) - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion (T002)
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Final Phase)**: Depends on all user story phases being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - May build on US1 message hook in `custom/app/models/custom/message.rb`
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - May build on US1/US2 message hook in `custom/app/models/custom/message.rb`

### Within Each User Story

- Tests MUST be written and fail before implementation
- Models/overrides before integration validation
- Story complete before moving to next priority

### Parallel Opportunities

- T001 (Setup) can run independently
- T003 can start as soon as Foundational (T002) lands; T005 and T007 all extend the same
  `custom/spec/models/custom/message_spec.rb` file started by T003, so they run sequentially
  (T003 → T005 → T007), not in parallel, to avoid clobbering each other's edits
- T009 and T010 (RuboCop and RSpec) can run in parallel during Polish phase

---

## Parallel Example: User Story 1

```bash
# Launch test definition for User Story 1:
Task: "Add RSpec unit tests for Scout human takeover on public outgoing replies in custom/spec/models/custom/message_spec.rb"

# Implement core logic for User Story 1:
Task: "Implement scout_pending_conversation? predicate and synchronous conversation.open! transition in custom/app/models/custom/message.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001)
2. Complete Phase 2: Foundational (T002)
3. Complete Phase 3: User Story 1 (T003, T004)
4. **STOP and VALIDATE**: Test User Story 1 independently with `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/models/custom/message_spec.rb`
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Test independently → Deploy/Demo
4. Add User Story 3 → Test independently → Deploy/Demo
5. Each story adds value without breaking previous stories

---

## Notes

- `[P]` tasks = different files or parallelizable checks, no dependencies
- `[Story]` label maps task to specific user story for traceability
- Each user story is independently completable and testable
- All changes remain strictly inside `custom/` overlay per Constitution Principle I
