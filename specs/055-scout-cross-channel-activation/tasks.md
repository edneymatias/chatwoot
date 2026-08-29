# Tasks: Scout Cross-Channel Activation

**Input**: Design documents from `/specs/055-scout-cross-channel-activation/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, quickstart.md

**Tests**: RSpec tests included as defined in plan.md (`custom/spec/listeners/custom/scout_listener_spec.rb`, `custom/spec/models/custom/inbox_spec.rb`, and `custom/spec/models/custom/message_spec.rb`).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- Rails backend with custom overlay: `custom/app/`, `custom/spec/`, `app/`, `spec/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify development environment and test baseline

- [X] T001 Verify existing custom spec suite runs cleanly via `custom/spec/`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Confirm module prepend and concern inclusion hooks

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T002 Verify `Inbox.prepend_mod_with('Inbox')` and `Inbox.include_mod_with('Concerns::Inbox')` extension points in `app/models/inbox.rb`

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Scout engages new conversations on non-WhatsApp channels (Priority: P1) 🎯 MVP

**Goal**: Allow Scout to engage incoming public messages on any channel type, and ensure new conversations on Scout-enabled inboxes start as `pending`.

**Independent Test**: Connect an enabled Scout to a non-WhatsApp inbox (e.g. `Channel::WebWidget`), create a new conversation, verify status is `pending`, and verify an incoming public message triggers `Custom::Scout::ProcessMessageJob.enqueue_debounced`.

### Tests for User Story 1

- [X] T003 [P] [US1] Create unit spec for `Custom::Inbox#active_bot?` with enabled Scout on non-WhatsApp inboxes in `custom/spec/models/custom/inbox_spec.rb`
- [X] T004 [P] [US1] Update `Custom::ScoutListener` spec to assert debounced job enqueue on non-WhatsApp inboxes in `custom/spec/listeners/custom/scout_listener_spec.rb`

### Implementation for User Story 1

- [X] T005 [P] [US1] Implement `Custom::Inbox` module overriding `active_bot?` (`super || scout_active?`) in `custom/app/models/custom/inbox.rb`
- [X] T006 [US1] Remove WhatsApp channel type restriction from `Custom::ScoutListener#message_created` in `custom/app/listeners/custom/scout_listener.rb`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently.

---

## Phase 4: User Story 2 - Non-Scout inboxes are unaffected (Priority: P2)

**Goal**: Inboxes without Scout, with disabled Scout, or with legacy bots/Captain continue standard behavior without interference from Scout activation.

**Independent Test**: Verify `Inbox#active_bot?` returns false and conversations start `open` when Scout is missing or disabled, while legacy bots/Captain still activate bot handling.

### Tests for User Story 2

- [X] T007 [P] [US2] Add test cases for disabled Scout, no Scout, and legacy bot / Captain delegation in `custom/spec/models/custom/inbox_spec.rb`
- [X] T008 [P] [US2] Add test cases for disabled Scout, private messages, and non-pending conversations across channels in `custom/spec/listeners/custom/scout_listener_spec.rb`

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently.

---

## Phase 5: User Story 3 - Human handoff keeps working across all channels (Priority: P3)

**Goal**: Verify that human agent replies on non-WhatsApp Scout-pending conversations transition the conversation status from `pending` to `open`.

**Independent Test**: Send a human agent public outgoing message on a pending non-WhatsApp Scout conversation and verify it transitions to `open`.

### Tests for User Story 3

- [X] T009 [US3] Add cross-channel human handoff test coverage for non-WhatsApp inboxes in `custom/spec/models/custom/message_spec.rb`

**Checkpoint**: All user stories should now be independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Validation and lint checks across all stories

- [X] T010 [P] Run quickstart test scenarios per `specs/055-scout-cross-channel-activation/quickstart.md`, including its "Automated verification" full `custom/spec/` sweep — this is the regression check for FR-005/SC-002 (no change to existing WhatsApp campaign/referral-attribution behavior)
- [X] T011 Run RuboCop on modified and new files per repo standards in `custom/app/` and `custom/spec/`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User stories can then proceed in parallel (if staffed)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Final Phase)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Tests and verifies boundary conditions of US1 implementation
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Tests regression safety of existing handoff behavior across channels

### Within Each User Story

- Tests written first, ensure failure before implementation (TDD flow)
- Model logic before listener/consumer logic
- Story complete before moving to next priority

### Parallel Opportunities

- T003, T004, and T005 can be drafted in parallel
- T007 and T008 can be written in parallel
- T010 can run in parallel with polish documentation/reviews

---

## Parallel Example: User Story 1

```bash
# Launch all tests for User Story 1 together:
Task: "Create unit spec for Custom::Inbox#active_bot? with enabled Scout on non-WhatsApp inboxes in custom/spec/models/custom/inbox_spec.rb"
Task: "Update Custom::ScoutListener spec to assert debounced job enqueue on non-WhatsApp inboxes in custom/spec/listeners/custom/scout_listener_spec.rb"

# Launch model implementation:
Task: "Implement Custom::Inbox module overriding active_bot? in custom/app/models/custom/inbox.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL - blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Test User Story 1 independently with `bundle exec rspec custom/spec/listeners/custom/scout_listener_spec.rb custom/spec/models/custom/inbox_spec.rb`
5. Deploy/demo if ready

### Incremental Delivery

1. Complete Setup + Foundational → Foundation ready
2. Add User Story 1 → Test independently → Deploy/Demo (MVP!)
3. Add User Story 2 → Test negative/delegation cases → Verify zero regressions
4. Add User Story 3 → Verify cross-channel human handoff
5. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable
- Strict adherence to repository conventions (compact module style, RuboCop rules, no edits to core/enterprise files)
- Forward-only behavior: existing `open` conversations are not modified retroactively
