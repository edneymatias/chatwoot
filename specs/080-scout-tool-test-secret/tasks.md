---
description: "Task list for Scout Tool Test Real Credential Reconciliation implementation"
---

# Tasks: Scout Tool "Test" Uses Real Saved Credential, Not the Masked Placeholder

**Input**: Design documents from `/specs/080-scout-tool-test-secret/`

**Prerequisites**: [`plan.md`](file:///home/matias/Projects/chatwoot/specs/080-scout-tool-test-secret/plan.md), [`spec.md`](file:///home/matias/Projects/chatwoot/specs/080-scout-tool-test-secret/spec.md), [`research.md`](file:///home/matias/Projects/chatwoot/specs/080-scout-tool-test-secret/research.md), [`data-model.md`](file:///home/matias/Projects/chatwoot/specs/080-scout-tool-test-secret/data-model.md), [`contracts/scout-tools-test-endpoint.md`](file:///home/matias/Projects/chatwoot/specs/080-scout-tool-test-secret/contracts/scout-tools-test-endpoint.md), [`quickstart.md`](file:///home/matias/Projects/chatwoot/specs/080-scout-tool-test-secret/quickstart.md)

**Tests**: Test tasks included per Constitution Principle VI (TDD non-negotiable for behavior changes). Tests run surgically per Principle IX (no global suite runs during iteration).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

---

## Format: `- [ ] [TaskID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (`[US1]`, `[US2]`, `[US3]`)
- Include exact file paths in descriptions

## Path Conventions

- **Backend (fork-exclusive `custom/` tree)**: `custom/app/models/scout_tool.rb`, `custom/app/controllers/api/v1/accounts/scout_tools_controller.rb`, `custom/spec/`
- **Frontend (fork-original components)**: `app/javascript/dashboard/components-next/Scout/pageComponents/`
- **Specs & documentation**: `specs/080-scout-tool-test-secret/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify development environment containers and initialize the test file scaffold.

- [X] T001 Verify Docker Compose stack is up and Rails/Vite containers are healthy in `docker-compose.yaml`
- [X] T002 [P] Initialize Vitest test scaffold file for ScoutToolModal in `app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutToolModal.spec.js`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core safety baseline and existing test contract verification before modifying any feature files.

**⚠️ CRITICAL**: Confirm baseline test suites pass before feature changes begin.

- [X] T003 Verify baseline test suite passes in `custom/spec/models/scout_tool_spec.rb` and `custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb`

**Checkpoint**: Foundation ready - user story implementation and test-driven cycles can begin.

---

## Phase 3: User Story 1 - Testing an already-configured tool without retyping the credential (Priority: P1) 🎯 MVP

**Goal**: An operator editing an existing saved tool can click "Test" without modifying the credential field (or clearing it to blank) and have the test request use the tool's real saved credential instead of sending the masked placeholder (`••••••••`) or failing with 401/403. If the operator enters a new credential, the test uses the newly typed credential.

**Independent Test**: Save a tool with a real credential, open it for edit, click "Test" with masked or blank credentials, and verify the outbound HTTP request carries the real decrypted credential. Type a new credential and verify the outbound HTTP request carries the newly typed credential.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T004 [P] [US1] Write failing unit tests for `ScoutTool#auth_headers_for_test` covering bearer, basic, api_key, blank/masked secret preservation, and newly typed values in `custom/spec/models/scout_tool_spec.rb`
- [X] T005 [P] [US1] Write failing request specs for `POST /api/v1/accounts/:account_id/scout_tools/test` with existing tool `id` and masked or blank credentials asserting SafeFetch receives real saved secret in `custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb` — include a scenario that also changes a non-credential field (e.g. `endpoint_url`) alongside the masked/blank credential, confirming the fallback is independent of which other fields changed (spec.md Edge Cases)
- [X] T006 [P] [US1] Write failing request spec for `POST /api/v1/accounts/:account_id/scout_tools/test` with existing tool `id` and newly typed credentials asserting SafeFetch receives the new secret in `custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb`
- [X] T007 [P] [US1] Write failing component test for `ScoutToolModal.vue` verifying `handleTest` includes `id: props.tool.id` in `testPayload` when `isEditing.value` is true in `app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutToolModal.spec.js`

### Implementation for User Story 1

- [X] T008 [US1] Implement `ScoutTool#auth_headers_for_test` in `custom/app/models/scout_tool.rb` to normalize incoming credentials and return merged secrets via `merge_preserved_secrets` without mutating or persisting the record
- [X] T009 [US1] Update `test_params` to read `id: src[:id]` and update `test` action in `custom/app/controllers/api/v1/accounts/scout_tools_controller.rb` to resolve `Current.account.scout_tools.find_by(id: tp[:id])` and reconcile credentials with `auth_headers_for_test`
- [X] T010 [US1] Update `handleTest` in `app/javascript/dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue` to conditionally include `id: props.tool.id` in `testPayload` when editing an existing tool
- [X] T011 [US1] Run targeted unit, request, and component tests to verify T004, T005, T006, and T007 now pass in `custom/spec/models/scout_tool_spec.rb`, `custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb`, and `app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutToolModal.spec.js`

**Checkpoint**: User Story 1 (MVP) is fully functional, verified by automated tests, and testable independently.

---

## Phase 4: User Story 2 - Testing a brand-new, not-yet-saved tool still requires the real credential (Priority: P2)

**Goal**: Ensure testing a brand-new unsaved tool continues to require entering the real credential as today, with zero substitution. Ensure submitting an unresolved, nonexistent, or cross-account tool ID silently falls back to literal submitted parameters without leaking credentials or revealing resource existence across accounts.

**Independent Test**: Test an unsaved tool with blank or placeholder credentials, verify no substitution occurs and behavior matches existing unsaved tool handling. Submit a test request with an ID belonging to a different account, verify no foreign credential is used and the response shape is indistinguishable from testing an unsaved tool.

### Tests for User Story 2 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T012 [P] [US2] Write failing request specs for `POST /api/v1/accounts/:account_id/scout_tools/test` with no `id` (brand-new tool) asserting literal submitted values are used without substitution in `custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb`
- [X] T013 [P] [US2] Write failing request specs for `POST /api/v1/accounts/:account_id/scout_tools/test` with nonexistent, mistyped, or cross-account `id` asserting fallback to literal submitted values without distinct error or side channel per FR-005 and FR-008 in `custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb`
- [X] T014 [P] [US2] Write failing component test for `ScoutToolModal.vue` verifying `handleTest` omits `id` from `testPayload` when `props.tool` is null in `app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutToolModal.spec.js`

### Implementation for User Story 2

- [X] T015 [US2] Ensure `Current.account.scout_tools.find_by(id: tp[:id])` resolution and fallback in `custom/app/controllers/api/v1/accounts/scout_tools_controller.rb` seamlessly handles nil, non-numeric, and cross-account IDs without raising or branching response formats
- [X] T016 [US2] Run targeted request and component specs to verify T012, T013, and T014 pass in `custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb` and `app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutToolModal.spec.js`

**Checkpoint**: User Stories 1 and 2 are functional and independently tested, with draft tools and cross-account boundaries fully guarded.

---

## Phase 5: User Story 3 - Masked credentials never leak in plain text through any read (Priority: P3)

**Goal**: Verify that saved credentials remain strictly masked in all read paths (`GET /scout_tools`, `GET /scout_tools/:id`), with zero plain text credential leakage introduced by testing or reconciliation.

**Independent Test**: Fetch the list of tools and view a single tool's details; confirm that every secret-bearing field returns only `••••••••` and that `auth_headers_for_test` never mutates persisted database state.

### Tests for User Story 3 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T017 [P] [US3] Add request specs in `custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb` asserting `GET /api/v1/accounts/:account_id/scout_tools` and `GET /api/v1/accounts/:account_id/scout_tools/:id` return strictly masked credentials (`••••••••`) and never decrypted plain text per FR-007
- [X] T018 [P] [US3] Add model spec in `custom/spec/models/scout_tool_spec.rb` asserting `auth_headers_for_test` does not alter persisted `auth_headers` or reload state in PostgreSQL, upholding the method's non-persisting side-effect contract (data-model.md `ScoutTool#auth_headers_for_test`, reused by FR-002/FR-003's reconciliation)

### Implementation for User Story 3

- [X] T019 [US3] Verify that read formatting in `custom/app/controllers/api/v1/accounts/scout_tools_controller.rb` and masking in `custom/app/models/scout_tool.rb` satisfy T017 and T018 with zero credential leaks
- [X] T020 [US3] Run targeted specs to confirm T017 and T018 pass in `custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb` and `custom/spec/models/scout_tool_spec.rb`

**Checkpoint**: All three user stories are complete and independently verified.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Code quality, linting, hook auditing, and end-to-end quickstart scenario validation across all modified files.

- [X] T021 [P] Run RuboCop on modified backend files in `custom/app/models/scout_tool.rb`, `custom/app/controllers/api/v1/accounts/scout_tools_controller.rb`, `custom/spec/models/scout_tool_spec.rb`, and `custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb`
- [X] T022 [P] Run ESLint on modified frontend files in `app/javascript/dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue` and `app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutToolModal.spec.js`
- [X] T023 Run custom module hooks check script in `bin/sync-custom-module-hooks` to ensure all custom wiring points remain intact
- [X] T024 Run end-to-end quickstart validation test commands from `specs/080-scout-tool-test-secret/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately.
- **Foundational (Phase 2)**: Depends on Setup completion - establishes verified baseline before modifications.
- **User Story 1 (Phase 3)**: Depends on Foundational completion. Delivers core MVP functionality.
- **User Story 2 (Phase 4)**: Depends on User Story 1 completion (builds on controller parameter handling and verifies fallback/unsaved boundaries).
- **User Story 3 (Phase 5)**: Depends on User Story 1 and 2 completion (verifies read security and persistence immutability).
- **Polish (Phase 6)**: Depends on all user stories being implemented and green.

### User Story Dependencies

- **User Story 1 (P1)**: Independent of US2/US3. Establishes `ScoutTool#auth_headers_for_test` and controller `test` reconciliation.
- **User Story 2 (P2)**: Extends controller `test` handling to verify unresolved ID and unsaved tool boundaries.
- **User Story 3 (P3)**: Validates non-regression in read paths (`index`, `show`) and model persistence immutability.

### Within Each User Story

- Tests written first and observed failing before implementation (Constitution Principle VI).
- Model methods implemented before controller endpoint wiring.
- Backend endpoint updated before frontend payload integration.
- Targeted specs verified green before proceeding to next story.

### Parallel Opportunities

- **Phase 1**: T002 can run in parallel with environment verification.
- **Phase 3**:
  - Test tasks T004, T005, T006, and T007 can all be written in parallel.
  - Model implementation (T008) and frontend update (T010) touch different stacks and can be authored in parallel once tests exist.
- **Phase 4**:
  - Test tasks T012, T013, and T014 can be written in parallel.
- **Phase 5**:
  - Test tasks T017 and T018 can be written in parallel.
- **Phase 6**:
  - RuboCop (T021) and ESLint (T022) can run in parallel across Rails and Vite containers.

---

## Parallel Example: User Story 1

```bash
# Write failing test suite for User Story 1 in parallel:
Task T004: Unit tests in custom/spec/models/scout_tool_spec.rb
Task T005: Request specs in custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb
Task T007: Component tests in app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutToolModal.spec.js

# Implement model and frontend components in parallel:
Task T008: Implement auth_headers_for_test in custom/app/models/scout_tool.rb
Task T010: Update handleTest payload in app/javascript/dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`docker-compose.yaml` check, test scaffold).
2. Complete Phase 2: Foundational (baseline specs pass).
3. Complete Phase 3: User Story 1 (TDD cycle: T004–T007 fail, T008–T010 implemented, T011 passes).
4. **STOP and VALIDATE**: Verify User Story 1 independently with targeted RSpec and Vitest commands.
5. At this point, the primary problem (operator unable to test saved tools) is fully solved.

### Incremental Delivery

1. Setup + Foundational → baseline established.
2. User Story 1 → saved tool credential reconciliation working (MVP!).
3. User Story 2 → unsaved tool and foreign-ID fallback boundary guarded.
4. User Story 3 → read-masking and database immutability verified.
5. Polish → RuboCop, ESLint, sync hooks, and quickstart end-to-end suite passing.

---

## Notes

- `[P]` tasks = different files, no dependencies.
- `[Story]` label maps each task to its user story (`[US1]`, `[US2]`, `[US3]`).
- TDD is strictly enforced: write tests first, observe failure, then implement.
- Testing is strictly scoped per Constitution Principle IX: run only targeted test files during iteration.
