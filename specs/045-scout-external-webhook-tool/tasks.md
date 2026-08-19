---

description: "Task list for Scout External REST/Webhook Tool implementation"
---

# Tasks: Scout External REST/Webhook Tool

**Input**: Design documents from `/specs/045-scout-external-webhook-tool/` (`spec.md`, `plan.md`, `research.md`, `data-model.md`, `quickstart.md`)

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `quickstart.md`

**Tests**: RSpec tests included as specified in `plan.md` under `custom/spec/services/custom/scout/`.

**Organization**: Tasks are grouped by user story (US1, US2, US3) to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Includes exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify foundational dependencies and structural prerequisites.

- [X] T001 Verify existing dependencies and model structures (`JSONSchemer`, `SafeFetch` in lib/safe_fetch.rb, and `ScoutTool` in custom/app/models/scout_tool.rb)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core tool skeleton, registration, and LLM-facing tool discovery that MUST be complete before user stories are implemented.

**⚠️ CRITICAL**: Foundational tasks must complete before user story implementation begins.

- [X] T002 Create CallCustomApi tool skeleton inheriting from BaseTool in custom/app/services/custom/scout/tools/call_custom_api.rb
- [X] T003 Register Custom::Scout::Tools::CallCustomApi in custom/app/services/custom/scout/agent_runner.rb
- [X] T004 Override the instance-level `description` method in CallCustomApi to render a catalog (id, name, description, parameters_schema) of the calling account's enabled ScoutTools, scoped via `account.scout_tools.where(enabled: true)`, satisfying FR-008 (see research.md §6) in custom/app/services/custom/scout/tools/call_custom_api.rb

**Checkpoint**: Tool skeleton created, registered in AgentRunner, and discoverable by the LLM via its own description - user story implementation can begin.

---

## Phase 3: User Story 1 - Scout answers a customer using a live external system (Priority: P1) 🎯 MVP

**Goal**: Enable Scouts to resolve account-scoped enabled `ScoutTool`s, validate payloads, execute outbound HTTP calls via `SafeFetch`, and return live response data within conversation turns.

**Independent Test**: Configure an enabled `ScoutTool`, invoke `call_custom_api` with a matching payload, and verify the outbound HTTP call is executed with decrypted auth headers and parsed response data is returned to the caller.

### Tests for User Story 1

- [X] T005 [P] [US1] Add RSpec unit tests for successful execution and account-scoped tool resolution in custom/spec/services/custom/scout/tools/call_custom_api_spec.rb
- [X] T006 [P] [US1] Add RSpec tests verifying CallCustomApi tool registration and its enabled-tool catalog description in custom/spec/services/custom/scout/agent_runner_spec.rb

### Implementation for User Story 1

- [X] T007 [US1] Implement account-scoped tool resolution and decrypted auth header building in custom/app/services/custom/scout/tools/call_custom_api.rb
- [X] T008 [US1] Implement HTTP request execution using SafeFetch.fetch with sensitive headers redaction and response formatting in custom/app/services/custom/scout/tools/call_custom_api.rb

**Checkpoint**: At this point, User Story 1 is fully functional as an MVP - Scouts can discover and call live external APIs within their account.

---

## Phase 4: User Story 2 - Scout recovers gracefully when the external system misbehaves (Priority: P1)

**Goal**: Ensure all failure modes (invalid payload against `parameters_schema`, timeouts, network errors, oversized responses >1 MB, 4xx/5xx statuses) return structured failure messages to the LLM and log errors via `Rails.logger.error` without crashing conversation turns.

**Independent Test**: Trigger schema validation errors, network timeouts, oversized responses, and HTTP error responses; verify structured error output strings and Rails logger error entries while ensuring `execute` never raises unhandled exceptions.

### Tests for User Story 2

- [X] T009 [P] [US2] Add RSpec unit tests for schema validation failures, timeouts, 1MB response size limits, and network errors in custom/spec/services/custom/scout/tools/call_custom_api_spec.rb

### Implementation for User Story 2

- [X] T010 [US2] Implement JSON Schema validation with JSONSchemer against parameters_schema before network calls in custom/app/services/custom/scout/tools/call_custom_api.rb
- [X] T011 [US2] Implement error rescue, Rails.logger.error logging, and structured failure response formatting in custom/app/services/custom/scout/tools/call_custom_api.rb

**Checkpoint**: At this point, User Stories 1 AND 2 work independently - external API errors are handled safely and gracefully.

---

## Phase 5: User Story 3 - Disabled integrations are never reachable (Priority: P2)

**Goal**: Prevent disabled (`enabled: false`) or nonexistent tools from being executed, returning a structured failure string without contacting external endpoints, and confirm disabled tools are also excluded from the catalog built in T004.

**Independent Test**: Invoke `call_custom_api` with IDs for disabled tools, nonexistent tools, or cross-account tools; confirm no HTTP request is made, a generic unavailable message is returned, and the disabled tool no longer appears in the tool's description catalog.

### Tests for User Story 3

- [X] T012 [P] [US3] Add RSpec unit tests for disabled, nonexistent, and cross-account tool invocation rejection, and for disabled tools being absent from the description catalog, in custom/spec/services/custom/scout/tools/call_custom_api_spec.rb

### Implementation for User Story 3

- [X] T013 [US3] Ensure disabled tool filtering and unified safe failure reporting for unresolvable tools in custom/app/services/custom/scout/tools/call_custom_api.rb

**Checkpoint**: All user stories (US1, US2, US3) are complete and independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Code quality, test suite execution, and end-to-end verification.

- [X] T014 [P] Run RuboCop check and auto-fix across new and modified files in custom/app/services/custom/scout/tools/call_custom_api.rb, custom/app/services/custom/scout/agent_runner.rb, and custom/spec/
- [X] T015 Execute full Scout test suite via RSpec in custom/spec/services/custom/scout/
- [X] T016 Validate manual test scenarios against quickstart guide in specs/045-scout-external-webhook-tool/quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3+)**: All depend on Foundational phase completion
  - User Story 1 (P1): Can start immediately after Foundational (Phase 2)
  - User Story 2 (P1): Can start after US1 (or parallel test writing)
  - User Story 3 (P2): Can start after US1/US2
- **Polish (Phase 6)**: Depends on completion of all desired user stories

### User Story Dependencies

- **User Story 1 (P1)**: Foundation only. Delivers the core execution loop, account scoping, and LLM-facing tool discovery.
- **User Story 2 (P1)**: Depends on US1 tool structure; adds schema validation, timeout safeguards, and error recovery.
- **User Story 3 (P2)**: Depends on US1 tool resolution; ensures disabled/missing tools are rejected safely without data leaks, and excluded from the T004 catalog.

### Within Each User Story

- Tests written first (red/green flow)
- Core lookup and validation before external network calls
- Safe error handling and response formatting wrapping execution

### Parallel Opportunities

- T005 [P] and T006 [P] can run in parallel during Phase 3
- T009 [P] test creation can be prepared in parallel with US1 implementation
- T012 [P] test creation can run in parallel with US2 implementation
- T014 [P] RuboCop check can run across modified files

---

## Parallel Example: User Story 1

```bash
# Launch test definitions in parallel:
Task: "Add RSpec unit tests for successful execution and account-scoped tool resolution in custom/spec/services/custom/scout/tools/call_custom_api_spec.rb"
Task: "Add RSpec tests verifying CallCustomApi tool registration and its enabled-tool catalog description in custom/spec/services/custom/scout/agent_runner_spec.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup verification
2. Complete Phase 2: Foundational skeleton, registration, and catalog description (T002-T004)
3. Complete Phase 3: User Story 1 (T005-T008)
4. **STOP and VALIDATE**: Verify happy path and account scoping independently

### Incremental Delivery

1. Setup + Foundational → Foundation ready (tool discoverable + callable)
2. Add US1 (Live API execution) → Test independently → MVP Ready
3. Add US2 (Schema validation + Timeout/Error recovery) → Test independently
4. Add US3 (Disabled/Missing tool rejection) → Test independently
5. Run Polish (RuboCop, full RSpec, Quickstart check) → Feature complete

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- All tasks strictly follow the `- [ ] [TaskID] [P?] [Story?] Description with file path` format
- External network requests routed strictly via `SafeFetch.fetch` with 1 MB cap and timeout bounds
- No new database tables or schema migrations required

---

## Phase 7: Convergence

- [X] T017 Update data-model.md §2's "Non-success HTTP status" row to describe the actual generic-failure-string behavior (status/reason only, no response body) implemented in CallCustomApi#execute's `rescue SafeFetch::HttpError` branch — matching research.md §5 and the Captain::Tools::HttpTool precedent — instead of the stale "surfaced as-is" wording, in specs/045-scout-external-webhook-tool/data-model.md (contradicts)
