---
description: "Task list for Response Auditor Repair Loop Narrative Leak implementation"
---

# Tasks: Response Auditor Repair Loop Narrative Leak

**Input**: Design documents from `/specs/079-handoff-repair-narrative-leak/`

**Prerequisites**: `plan.md` (completed), `spec.md` (completed), `research.md` (completed), `data-model.md` (completed), `contracts/response_auditor.md` (completed), `quickstart.md` (completed)

**Tests**: All test tasks included per Constitution Principle VI (TDD non-negotiable for behavior changes). Tests run surgically per Principle IX (no global suite runs during iteration).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

---

## Format: `- [ ] [TaskID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (`[US1]`, `[US2]`)
- Include exact file paths in descriptions

## Path Conventions

- **Custom fork tree**: `custom/app/services/custom/scout/`, `custom/spec/services/custom/scout/`
- **Root tooling/specs**: `specs/079-handoff-repair-narrative-leak/`, `bin/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify development container environment and baseline test suite before any changes

- [X] T001 Verify Docker Compose stack is up (`docker compose up -d`) and Rails container is healthy in `docker-compose.yaml`
- [X] T002 Verify baseline test suite in `custom/spec/services/custom/scout/response_auditor_spec.rb` passes before modifications

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core safety baseline and caller contract verification before implementing user stories

**⚠️ CRITICAL**: Confirm caller contract and baseline suite pass before modifying `ResponseAuditor`

- [X] T003 [P] Verify baseline caller contract in `custom/spec/services/custom/scout/agent_runner_spec.rb` to confirm caller-side `handoff_already_flagged` threading is intact before changes

**Checkpoint**: Foundation ready - user story implementation and tests can begin

---

## Phase 3: User Story 1 - A tool-decided handoff turn is delivered exactly as the model wrote it (Priority: P1) 🎯 MVP

**Goal**: When a turn's handoff has already been deterministically decided by a successful tool call (`handoff_already_flagged: true`), deliver the model's original reply and reason untouched, skipping the claim-consistency check and repair loop entirely (FR-001, FR-002, FR-003).

**Independent Test**: Replay a turn where `handoff_already_flagged: true` is passed to `ResponseAuditor#audit`; verify it returns `{ action: :proceed, reply: response_text }` unchanged, does not call `ClaimConsistencyService#check`, does not call `chat.ask`, and preserves genuine repair behavior when `handoff_already_flagged: false` (SC-001, SC-002, SC-003).

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T004 [US1] Write failing unit tests in `custom/spec/services/custom/scout/response_auditor_spec.rb`: when `ResponseAuditor` is initialized with `handoff_already_flagged: true`, calling `#audit` returns `{ action: :proceed, reply: original_reply }` unchanged, `ClaimConsistencyService#check` is not called, and `chat.ask` is not called (FR-001, FR-002, FR-003, SC-002)
- [X] T005 [US1] Write failing edge-case unit test in `custom/spec/services/custom/scout/response_auditor_spec.rb`: verify that even if `response_text` contains unbacked claims that would otherwise trigger repair, when `handoff_already_flagged: true`, `#audit` returns the original text untouched without triggering claim check or repair (FR-001, FR-002, spec Edge Cases)

### Implementation for User Story 1

- [X] T006 [US1] Implement skip guard in `custom/app/services/custom/scout/response_auditor.rb` method `#audit`: add `return { action: :proceed, reply: response_text } if @handoff_already_flagged` after `conversation_pending?` check and before `check_claim_consistency` (FR-001, FR-002, FR-003)
- [X] T007 [US1] Verify T004 and T005 unit tests now pass in `custom/spec/services/custom/scout/response_auditor_spec.rb` with the skip guard implemented
- [X] T008 [US1] Run regression tests in `custom/spec/services/custom/scout/response_auditor_spec.rb` to verify non-flagged turns (`handoff_already_flagged: false`) still trigger claim consistency check, repair loop on unbacked claims, and mid-repair handoff detection with zero regression (FR-004, FR-005, SC-003)

**Checkpoint**: User Story 1 (MVP) is fully functional and testable independently

---

## Phase 4: User Story 2 - The repair loop's own output becomes visible in logs (Priority: P2)

**Goal**: Whenever the claim-consistency check judges a reply inconsistent and the repair loop runs, record the repair loop's full outcome (reasoning and response) in application logs at `.info` level so the path is diagnosable from logs alone (FR-006, SC-004).

**Independent Test**: Trigger a repair loop execution (unbacked claim with `handoff_already_flagged: false`) and verify that `Rails.logger.info` receives a log entry matching `[Scout][ResponseAuditor] repair reasoning: #{reasoning}` with the parsed reasoning content (SC-004).

### Tests for User Story 2 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T009 [US2] Write failing unit test in `custom/spec/services/custom/scout/response_auditor_spec.rb`: assert that when `execute_repair` runs during repair, `Rails.logger.info` receives `"[Scout][ResponseAuditor] repair reasoning: #{reasoning}"` containing the reasoning parsed from the repaired message JSON payload (FR-006, SC-004)
- [X] T010 [US2] Write failing edge-case unit test in `custom/spec/services/custom/scout/response_auditor_spec.rb`: assert that when the repaired message payload has blank reasoning or is non-JSON text, `execute_repair` logs gracefully without raising an exception (FR-006)

### Implementation for User Story 2

- [X] T011 [US2] Implement repair outcome parsing and logging in `custom/app/services/custom/scout/response_auditor.rb`: update `parse_repaired_content` and `execute_repair` to extract `reasoning` alongside `response` from the repaired message payload and emit `Rails.logger.info("[Scout][ResponseAuditor] repair reasoning: #{reasoning}")` before returning `response` (FR-006)
- [X] T012 [US2] Verify T009 and T010 unit tests now pass in `custom/spec/services/custom/scout/response_auditor_spec.rb` after implementing repair outcome logging

**Checkpoint**: User Story 2 complete — repair loop reasoning is logged and visible in application logs

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Quality checks, full suite validation, and end-to-end replay confirmation

- [X] T013 [P] Run full targeted test suite in `custom/spec/services/custom/scout/response_auditor_spec.rb` verifying all examples pass cleanly
- [X] T014 [P] Run caller contract regression suite in `custom/spec/services/custom/scout/agent_runner_spec.rb` verifying caller boundary remains intact
- [X] T015 [P] Run RuboCop on modified files `custom/app/services/custom/scout/response_auditor.rb` and `custom/spec/services/custom/scout/response_auditor_spec.rb` to verify zero offenses and 150-char line limit
- [X] T016 Run end-to-end replay smoke test via `Custom::Scout::AgentRunner` (NOT `PlaygroundRunner`, which never calls `ResponseAuditor`) against a disposable dev conversation per `quickstart.md` Step 4 to verify pricing question handoff delivery without narrative leak (SC-001)
- [X] T017 Verify custom module hooks with `bin/sync-custom-module-hooks --check` and `bin/sync-custom-module-hooks --audit` to confirm all hook wiring points present and zero feature gaps

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup (Phase 1) - verifies caller baseline before changes
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2) - delivers skip guard for tool-decided handoffs (MVP)
- **User Story 2 (Phase 4)**: Depends on Foundational (Phase 2); can proceed after Phase 3 or in parallel since it modifies a separate private method (`execute_repair`) in `response_auditor.rb`
- **Polish (Phase 5)**: Depends on User Story 1 and User Story 2 being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories; modifies `#audit` skip guard
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Modifies `#execute_repair` logging; independent of US1's skip guard

### Within Each User Story

- Tests MUST be written and fail before implementation (Constitution Principle VI)
- US1: `T004` and `T005` fail before `T006` adds skip guard; `T007` and `T008` verify tests and regression
- US2: `T009` and `T010` fail before `T011` adds logging; `T012` verifies tests pass

### Parallel Opportunities

- In Phase 2, `T003` can run in parallel with baseline checks
- In Phase 5 (Polish), `T013` (`response_auditor_spec.rb`), `T014` (`agent_runner_spec.rb`), and `T015` (RuboCop) can all execute in parallel

---

## Parallel Example: Polish & Cross-Cutting Concerns

```bash
# Run targeted specs and lint checks in parallel:
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/response_auditor_spec.rb
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/agent_runner_spec.rb
docker compose exec rails bundle exec rubocop custom/app/services/custom/scout/response_auditor.rb custom/spec/services/custom/scout/response_auditor_spec.rb
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001`, `T002`)
2. Complete Phase 2: Foundational (`T003`)
3. Complete Phase 3: User Story 1 (`T004`–`T008`) — delivers the skip guard
4. **STOP and VALIDATE**: Verify User Story 1 independently via `custom/spec/services/custom/scout/response_auditor_spec.rb`
5. MVP is deliverable — customer-facing messages and transfer notes are delivered untouched on tool-decided handoffs (FR-001, FR-002, FR-003)

### Incremental Delivery

1. Setup + Foundational (`T001`–`T003`) → Environment and baseline verified
2. User Story 1 (`T004`–`T008`) → Skip guard implemented and tested (MVP!)
3. User Story 2 (`T009`–`T012`) → Repair outcome logging implemented and tested
4. Polish & Verification (`T013`–`T017`) → Full targeted suite, caller contract, RuboCop, replay smoke test, sync hooks audit

---

## Notes

- `[P]` tasks = different files / independent processes, no dependencies on incomplete tasks
- `[Story]` label maps task to specific user story for traceability (`[US1]`, `[US2]`)
- Every task includes an explicit, exact file path
- Adheres strictly to Constitution Principles:
  - Principle I: Upstream compatibility (changes confined to `custom/` tree)
  - Principle II: Smallest production-ready change (single guard + single log line)
  - Principle III: Established conventions (150-char RuboCop, `[Scout][ResponseAuditor]` log prefix)
  - Principle VI: TDD non-negotiable (write failing tests before implementation)
  - Principle VII: Observable behavior (assert return values and logger output, no internal state mocking)
  - Principle IX: Surgical execution scope (targeted spec runs only, no global runs during iteration)
