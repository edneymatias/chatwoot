# Tasks: Scout Observability & Handoff Notice

**Input**: Design documents from `/specs/056-scout-observability-handoff-notice/` (`spec.md`, `plan.md`, `data-model.md`, `research.md`, `quickstart.md`)
**Constitution**: `.specify/memory/constitution.md`

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish shared translation keys used across handoff paths.

- [x] T001 Add `conversations.scout.handoff` translation keys in `config/locales/en.yml` and `config/locales/pt_BR.yml`

---

## Phase 2: Foundational (Blocking Prerequisite for User Story 2 only)

**Purpose**: Core prerequisite check for LLM instrumentation extension points before User Story 2
work begins. User Story 1 (public handoff message) has no dependency on LLM instrumentation — it
only needs Phase 1 (i18n key) — so it is **not** gated by this phase; see Dependencies below.

**⚠️ CRITICAL**: Verify the shared extension points before proceeding with User Story 2's
implementation.

- [x] T002 [US2] Confirm `Integrations::LlmInstrumentation#instrument_llm_call`/`#instrument_agent_session`/`#instrument_tool_call` are includable as-is (no signature/constant changes needed) by writing a throwaway `bundle exec rails runner` check (or a minimal spec) that includes the module in a plain object and calls each method with a stub block, asserting the `return yield unless ChatwootApp.otel_enabled?` short-circuit fires when disabled

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel.

---

## Phase 3: User Story 1 - Customer is told the conversation is being transferred (Priority: P1) 🎯 MVP

**Goal**: Ensure customers receive a public transfer message in both fail-safe handoff and explicit handoff paths before `conversation.bot_handoff!` is invoked, while preserving internal private notes.

**Independent Test**: Trigger fail-safe handoff (e.g. quota exhausted, unparseable response, or runtime error) and explicit handoff (e.g. handover tool) and verify public message `I18n.t('conversations.scout.handoff')` is dispatched to the conversation before `bot_handoff!`, and private alert/transfer notes are also recorded.

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T003 [P] [US1] Add RSpec unit tests for public transfer message on fail-safe handoff in `custom/spec/services/custom/scout/agent_runner_spec.rb` — update the existing `expect(...).to be_empty` assertions on public outgoing messages (they currently assert none are created) to instead assert the fixed `conversations.scout.handoff` message is created, assert it is created before `bot_handoff!`/status change, and add an explicit assertion that the existing private alert note is still created unchanged (FR-003)
- [x] T004 [P] [US1] Add RSpec unit tests for public transfer message on explicit handoff in `custom/spec/services/custom/scout/handoff_service_spec.rb` — cover: (a) the public message is created before `bot_handoff!` regardless of whether `reason` is present (the private note stays conditional on `reason.present?`, the public message must not be), (b) the existing private transfer note still behaves exactly as today (FR-003), and (c) extend the existing non-pending-conversation example ("does not call bot_handoff! but still updates assignments") to also assert the public message is **not** sent in that case

### Implementation for User Story 1

- [x] T005 [US1] Implement public transfer message dispatch before `bot_handoff!` in `Custom::Scout::AgentRunner#perform_fail_safe_handoff` in `custom/app/services/custom/scout/agent_runner.rb`
- [x] T006 [US1] Implement public transfer message dispatch before `bot_handoff!` in `Custom::Scout::HandoffService#perform_handoff` in `custom/app/services/custom/scout/handoff_service.rb`

**Checkpoint**: At this point, User Story 1 is fully functional and testable independently. Customers will never experience a silent handoff.

---

## Phase 4: User Story 2 - Support staff can see what happened during an automated conversation (Priority: P2)

**Goal**: Wrap Scout's main LLM call in `AgentRunner` and tool execution in `BaseTool` with `Integrations::LlmInstrumentation` so OpenTelemetry traces and tool call spans are emitted to Langfuse when `ChatwootApp.otel_enabled?` is true, and cleanly skipped when false.

**Independent Test**: Configure or mock `ChatwootApp.otel_enabled?`, execute Scout with LLM calls and tool invocations, and verify `instrument_agent_session` / `instrument_llm_call` wrap `execute_chat` and `instrument_tool_call` wraps `BaseTool#call`.

### Tests for User Story 2

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [x] T007 [P] [US2] Create RSpec unit tests for `BaseTool#call` instrumentation in `custom/spec/services/custom/scout/tools/base_tool_spec.rb` — cover: (a) a successful tool call wraps `#call` in `instrument_tool_call` with the tool name and arguments (`ChatwootApp.otel_enabled?` stubbed true), (b) **a failing tool call** (e.g. a network error raised from a `CallCustomApi`-style tool) still surfaces its error/result through `instrument_tool_call` — this is the original motivating scenario for this feature (FR-006) — and (c) with `ChatwootApp.otel_enabled?` stubbed false, `#call` still returns the tool's result correctly and `instrument_tool_call` is not invoked (FR-007)
- [x] T008 [P] [US2] Add RSpec unit tests for `AgentRunner` LLM trace/span instrumentation in `custom/spec/services/custom/scout/agent_runner_spec.rb` — cover: (a) `execute_chat` wraps `chat.ask` in `instrument_agent_session`/`instrument_llm_call` when `ChatwootApp.otel_enabled?` is true, (b) with it stubbed false, the conversation flow behaves identically to today with no instrumentation calls made (FR-007, SC-004), and (c) if the instrumentation call itself raises/errors, the conversation still completes and dispatches its reply normally (spec.md Edge Cases: "trace integration becomes unreachable mid-conversation")

### Implementation for User Story 2

- [x] T009 [US2] Implement `#call` override with `instrument_tool_call` in `Custom::Scout::Tools::BaseTool` in `custom/app/services/custom/scout/tools/base_tool.rb`
- [x] T010 [US2] Implement `instrument_agent_session` and `instrument_llm_call` in `Custom::Scout::AgentRunner#execute_chat` in `custom/app/services/custom/scout/agent_runner.rb`

**Checkpoint**: At this point, User Stories 1 AND 2 are both functional. Scout conversation turns and tool calls emit granular Langfuse spans when OTel is enabled.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Verification, code quality, full test suite validation, and regression prevention.

- [x] T011 [P] Run RuboCop lint checks on modified files across `custom/app/services/custom/scout/` and `custom/spec/services/custom/scout/`
- [x] T012 Run full RSpec test suite for Scout services in `custom/spec/services/custom/scout/`
- [x] T013 [P] Execute quickstart manual validation scenarios per `specs/056-scout-observability-handoff-notice/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately.
- **Foundational (Phase 2)**: Depends on Setup completion; only blocks User Story 2 (see below) -
  verifies LLM instrumentation extension point availability, which US1 does not use.
- **User Story 1 (Phase 3)**: Depends only on Phase 1 (needs the i18n key from T001) — does **not**
  depend on Phase 2, since it never touches `Integrations::LlmInstrumentation`.
- **User Story 2 (Phase 4)**: Depends on Phase 1 and Phase 2.
  - User Story 1 (P1) and User Story 2 (P2) can proceed sequentially in priority order (P1 → P2) or in parallel by different developers, since Phase 2 only gates US2.
- **Polish (Phase 5)**: Depends on completion of User Stories 1 and 2.

### User Story Dependencies

- **User Story 1 (P1)**: Can start as soon as Phase 1 (T001) is done - No dependencies on Phase 2 or US2.
- **User Story 2 (P2)**: Can start after Phase 2 - No dependencies on US1.

### Within Each User Story

- Tests MUST be written and fail before implementation.
- Model / tool changes before service / runner changes.
- Core dispatch implementation before integration validation.

### Parallel Opportunities

- Phase 1 (T001) and Phase 2 (T002) can run concurrently.
- US1 test tasks `T003` and `T004` can run in parallel.
- US2 test tasks `T007` and `T008` can run in parallel.
- US1 implementation (`T005`, `T006`) and US2 implementation (`T009`, `T010`) touch distinct methods/files and can be developed in parallel once tests are established.
- Polish tasks `T011` and `T013` can run in parallel.

---

## Parallel Example: User Story 1

```bash
# Launch test creation for User Story 1 together:
Task: "Add RSpec unit tests for public transfer message on fail-safe handoff in custom/spec/services/custom/scout/agent_runner_spec.rb"
Task: "Add RSpec unit tests for public transfer message on explicit handoff in custom/spec/services/custom/scout/handoff_service_spec.rb"
```

## Parallel Example: User Story 2

```bash
# Launch test creation for User Story 2 together:
Task: "Create RSpec unit tests for BaseTool#call instrumentation in custom/spec/services/custom/scout/tools/base_tool_spec.rb"
Task: "Add RSpec unit tests for AgentRunner LLM trace/span instrumentation in custom/spec/services/custom/scout/agent_runner_spec.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup: i18n keys) — Phase 2 is not required for the MVP, since it only
   verifies the LLM instrumentation extension point that User Story 1 doesn't touch.
2. Complete Phase 3 (User Story 1: tests + fail-safe & explicit handoff messages).
3. **STOP and VALIDATE**: Verify with `bundle exec rspec custom/spec/services/custom/scout/agent_runner_spec.rb custom/spec/services/custom/scout/handoff_service_spec.rb`.
4. Deploy/demo MVP (Customer transfer notice active).

### Incremental Delivery

1. Setup → i18n key ready.
2. User Story 1 → Fix customer silent-handoff gap (MVP; no dependency on Phase 2).
3. Foundational (Phase 2) + User Story 2 → Add OpenTelemetry/Langfuse tracing to AgentRunner and BaseTool.
4. Polish → Run RuboCop and full Scout test suite.

---

## Notes

- `[P]` tasks = different files, no dependencies on incomplete tasks.
- `[Story]` label maps task to specific user story for traceability.
- All tasks follow strict checklist formatting: `- [ ] [TaskID] [P?] [Story?] Description with file path`.
