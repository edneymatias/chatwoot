---
description: "Task list for Scout Deterministic Router and Conversation Routing State"
---

# Tasks: Scout Deterministic Router and Conversation Routing State

**Input**: Design documents from `/specs/082-scout-router-conversation-state/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: Tests are included per Constitution VI (Test-Driven Development) and the specification's acceptance scenarios.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Rails monorepo custom tree**: `custom/app/`, `custom/spec/`, `db/migrate/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Baseline refactoring and cutover of shared types before story work

- [X] T001 Rename `custom/app/services/custom/scout_v2/routing_context.rb` to `custom/app/services/custom/scout_v2/routing_snapshot.rb` and define baseline `Custom::ScoutV2::RoutingSnapshot` class
- [X] T002 [P] Update existing predicate specs to reference `Custom::ScoutV2::RoutingSnapshot` in `custom/spec/services/custom/scout_v2/predicates/evaluator_spec.rb`, `custom/spec/services/custom/scout_v2/predicates/opportunity_open_spec.rb`, and `custom/spec/services/custom/scout_v2/predicates/pending_required_fields_spec.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core database schema and base model that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 Create database migration for `ichatr_scout_conversation_states` table in `db/migrate/21260924000000_create_ichatr_scout_conversation_states.rb`
- [X] T004 Run database migration for `ichatr_scout_conversation_states` via `db/migrate/21260924000000_create_ichatr_scout_conversation_states.rb` using `docker compose exec rails bundle exec rails db:migrate`
- [X] T005 Implement base `ScoutConversationState` model with associations, validations, enum `activation_reason`, and `.for_conversation` class method in `custom/app/models/scout_conversation_state.rb`

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Turn-scoped routing context (Priority: P1) 🎯 MVP

**Goal**: Assemble one routing snapshot per turn containing conversation, contact, inbox, Scout, opportunity (with derived stage role), pending required fields, active playbook, turn-scoped transition hand-off count, and satisfied capabilities. Snapshot must be constructible directly in memory with fixed values (zero DB/LLM calls) and assembled from real records via `RoutingSnapshot::Builder`.

**Independent Test**: Construct snapshot directly in memory with chosen values and confirm every field reads back as given; assemble via Builder from real records and verify correct derivation of opportunity stage role and union of pending fields without extra queries or external calls.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T006 [P] [US1] Write unit tests for `Custom::ScoutV2::RoutingSnapshot` in `custom/spec/services/custom/scout_v2/routing_snapshot_spec.rb` verifying all 10 keyword attributes, default values, array freezing, immutability, and zero DB access
- [X] T007 [P] [US1] Write integration tests for `Custom::ScoutV2::RoutingSnapshot::Builder` in `custom/spec/services/custom/scout_v2/routing_snapshot/builder_spec.rb` verifying resolution of contact, inbox, scout, opportunity, stage role (:initial, :qualified, :unqualified, :none), pending fields union, active playbook from state, and defaults for missing associations

### Implementation for User Story 1

- [X] T008 [US1] Implement full `Custom::ScoutV2::RoutingSnapshot` immutable value object with 10 keyword attributes, default values, array freezing, and zero I/O in `custom/app/services/custom/scout_v2/routing_snapshot.rb`
- [X] T009 [US1] Implement `Custom::ScoutV2::RoutingSnapshot::Builder` in `custom/app/services/custom/scout_v2/routing_snapshot/builder.rb` resolving contact, inbox, scout, opportunity, derived stage role, pending fields union, and active playbook via catalog

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently

---

## Phase 4: User Story 2 - Deterministic playbook selection (Priority: P2)

**Goal**: Given the turn's routing snapshot and the full set of available playbooks, decide which playbook (if any) should be active, using only state (`when_state`) — never an LLM — whenever state is enough to decide. Cover priority ordering, continuity, strictly higher-priority interruption, non-strictly higher would-be winner, no-match with active playbook, no-match with no active playbook, and trigger-only exclusion.

**Independent Test**: Can be fully tested with a table of playbook sets and snapshot values mapped to the expected winning playbook and confidence, exercised entirely in memory with no database and zero language model calls.

### Tests for User Story 2 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T010 [P] [US2] Write unit tests for `Custom::ScoutV2::Router` in `custom/spec/services/custom/scout_v2/router_spec.rb` covering the full decision matrix (highest priority match wins, active continuity, strictly-higher interruption, non-strictly-higher retention, no-match retention, no-match nil result, trigger-only exclusion, and confidence 1.0 vs nil)

### Implementation for User Story 2

- [X] T011 [US2] Implement `Custom::ScoutV2::Router` and nested `Custom::ScoutV2::Router::Decision` in `custom/app/services/custom/scout_v2/router.rb` evaluating matching playbooks via `Predicates::Evaluator` and ordering by priority descending to return deterministic decision

**Checkpoint**: At this point, User Stories 1 AND 2 should both work independently

---

## Phase 5: User Story 3 - Persisted per-conversation routing state (Priority: P3)

**Goal**: Durably persist per-conversation routing history (`active_playbook`, `activated_at`, `activation_reason`), support declared transition hand-offs up to 2 per turn attempt (refusing a 3rd with `handoff_limit_reached_at` timestamp), terminal exits clearing active playbook and updating `last_exit`, reactivation leaving `last_exit` intact, and retry isolation for turn-scoped counter vs. cumulative count.

**Independent Test**: Directly exercise `ScoutConversationState` persistence methods (`record_state_activation!`, `record_transition!`, `record_terminal_exit!`), driving a conversation to its second transition hand-off within one turn attempt, verifying a third is refused with the limit-reached marker set, verifying retry isolation with fresh turn count at zero, and confirming reactivation leaves previously recorded `last_exit` untouched.

### Tests for User Story 3 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T012 [P] [US3] Write model specs for `ScoutConversationState` in `custom/spec/models/scout_conversation_state_spec.rb` covering state activation/interruption (reason :state, leaves last_exit untouched), transition hand-off (reason :transition, cumulative count increment, leaves last_exit untouched), 2-per-turn cap refusal (returns false, sets handoff_limit_reached_at, leaves active_playbook unchanged), clean 2-hand-off turn leaving marker unset, retry isolation with zero turn count, terminal exit clearing active and setting last_exit, and reactivation preserving prior last_exit

### Implementation for User Story 3

- [X] T013 [US3] Implement `record_state_activation!` in `custom/app/models/scout_conversation_state.rb` setting `active_playbook`, `activated_at = Time.current`, `activation_reason = :state`, leaving `last_exit` untouched
- [X] T014 [US3] Implement `record_transition!` in `custom/app/models/scout_conversation_state.rb` enforcing 2-per-turn cap, setting `handoff_limit_reached_at = Time.current` when turn count >= 2, otherwise setting `active_playbook`, `activated_at`, `activation_reason = :transition` and incrementing cumulative `transition_count`
- [X] T015 [US3] Implement `record_terminal_exit!` in `custom/app/models/scout_conversation_state.rb` clearing active playbook, activated_at, activation_reason and recording `last_exit = exit_name`

**Checkpoint**: All user stories should now be independently functional and integrated

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Test execution, verification, and code quality across all stories

- [X] T016 [P] Run targeted RSpec test suite covering `custom/spec/services/custom/scout_v2/**` and `custom/spec/models/scout_conversation_state_spec.rb`
- [X] T017 [P] Execute scenarios 1 to 5 from `specs/082-scout-router-conversation-state/quickstart.md` via `rails runner` to validate end-to-end functionality
- [X] T018 Run RuboCop on all new and modified files in `custom/` and `db/migrate/` ensuring zero offenses and 150-char line limit compliance

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: No dependency on Phase 1 (different files — migration + `ScoutConversationState` vs. the `RoutingSnapshot` rename); can run in parallel with Phase 1 - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Phase 2 completion
- **User Story 2 (Phase 4)**: Depends on Phase 3 (evaluates against `RoutingSnapshot`)
- **User Story 3 (Phase 5)**: Depends on Phase 2 completion (builds persistence methods on `ScoutConversationState`)
- **Polish (Phase 6)**: Depends on all user stories (Phases 3, 4, and 5) being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after US1 - Evaluates `when_state` predicates against `RoutingSnapshot`
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Extends `ScoutConversationState` with activation and exit persistence methods; integrates with US1's Builder

### Within Each User Story

- Tests MUST be written and FAIL before implementation
- Models/value objects before services
- Services before consumers
- Story complete and verified before moving to next priority

### Parallel Opportunities

- In Phase 1: `T002` can run alongside or immediately after `T001`
- In Phase 2: `T003` (migration creation) unblocks `T004` (running migration) which unblocks `T005` (base model)
- Phase 1 and Phase 2 can run in parallel — no file overlap (`T001`/`T002` touch `routing_snapshot.rb`/predicate specs; `T003`-`T005` touch the migration and `ScoutConversationState` only)
- In Phase 3: `T006` and `T007` test writing can run in parallel
- In Phase 4: `T010` test writing can run in parallel with US3 test writing if staffed
- In Phase 5: `T012` test writing can run once `T005` is complete
- In Phase 6: `T016` (RSpec suite) and `T017` (Quickstart scenarios) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch both test files for User Story 1 together:
Task: "Write unit tests for Custom::ScoutV2::RoutingSnapshot in custom/spec/services/custom/scout_v2/routing_snapshot_spec.rb"
Task: "Write integration tests for Custom::ScoutV2::RoutingSnapshot::Builder in custom/spec/services/custom/scout_v2/routing_snapshot/builder_spec.rb"
```

## Parallel Example: User Story 2 & 3 Tests

```bash
# Once Phase 2 foundation is ready, specs for independent modules can be authored in parallel:
Task: "Write unit tests for Custom::ScoutV2::Router in custom/spec/services/custom/scout_v2/router_spec.rb"
Task: "Write model specs for ScoutConversationState in custom/spec/models/scout_conversation_state_spec.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001`, `T002`)
2. Complete Phase 2: Foundational (`T003`, `T004`, `T005`)
3. Complete Phase 3: User Story 1 (`T006`, `T007`, `T008`, `T009`)
4. **STOP and VALIDATE**: Test `RoutingSnapshot` and `Builder` independently with zero LLM/network calls
5. Verify in-memory snapshot assembly works end-to-end

### Incremental Delivery

1. Setup + Foundational → Database schema and base model ready
2. Add User Story 1 → Snapshot value object + Builder ready (MVP!)
3. Add User Story 2 → Deterministic in-memory Router with decision matrix ready
4. Add User Story 3 → Durable state persistence, hand-off limit, and terminal exits ready
5. Polish & Verification → All targeted specs green, quickstart scenarios verified, RuboCop clean

### Parallel Team Strategy

With multiple developers:
1. Team completes Setup + Foundational together (`T001`–`T005`)
2. Once Foundational is done:
   - Developer A: User Story 1 (`T006`–`T009`)
   - Developer B: User Story 2 (`T010`–`T011`, consuming `RoutingSnapshot` contract)
   - Developer C: User Story 3 (`T012`–`T015`, extending `ScoutConversationState`)
3. Stories complete and integrate seamlessly

---

## Notes

- `[P]` tasks = different files, no dependencies on uncompleted work
- `[Story]` label maps task directly to spec.md user stories for complete traceability
- Every task includes an explicit file path to eliminate ambiguity
- All specs follow Constitution VII: real database fixtures/factories, zero mocks of internal AR models or services
- Zero LLM calls and zero network requests across all test suites (SC-001)
