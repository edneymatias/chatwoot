# Tasks: Scout Structured Response Reliability

**Input**: Design documents from `/specs/057-scout-structured-response-reliability/` (`spec.md`, `plan.md`, `data-model.md`, `research.md`, `quickstart.md`)
**Constitution**: `.specify/memory/constitution.md`

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the schema class both user stories build on.

- [X] T001 Create `Custom::Scout::ResponseSchema < RubyLLM::Schema` (`string :reasoning`, `string :response`, both required) in `custom/app/services/custom/scout/response_schema.rb`, mirroring the field shape of `enterprise/lib/captain/response_schema.rb` (not copying its text — same licensing caveat as prior Scout phases)

---

## Phase 2: User Story 1 - Scout completes AI-driven conversations instead of defaulting to a human handoff (Priority: P1) 🎯 MVP

**Goal**: Enforce the `reasoning`/`response` structure at the API level via `chat.with_schema(...)`, so the model reliably produces a usable response instead of drifting into plain text that fails `JSON.parse`.

**Independent Test**: Run multiple real qualification conversations with Scout (including at least one that involves a tool call before the model's final reply) and confirm the customer receives the model's actual response, without triggering the "failed to interpret structured response" fail-safe path, at a rate under 5% of turns (per SC-001).

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T002 [P] [US1] Add RSpec tests asserting `Custom::Scout::ResponseSchema` declares required `reasoning`/`response` string fields and produces a valid JSON Schema (`#to_json_schema`/`#valid?`) in `custom/spec/services/custom/scout/response_schema_spec.rb`
- [X] T003 [P] [US1] Add RSpec tests for `AgentRunner`: (a) the chat is configured via `with_schema(Custom::Scout::ResponseSchema)` before/alongside `with_tool` calls, (b) `parse_structured_response` correctly extracts `response` when `RubyLLM` returns `response.content` as an already-parsed `Hash` (string keys, e.g. `{"reasoning" => "...", "response" => "..."}`), (c) it still falls back correctly to the existing fenced-JSON/plain-text `String` handling when `content` is a `String`, and (d) a tool call (e.g. `manage_opportunity`) still executes normally in the same turn as the schema-constrained final reply, in `custom/spec/services/custom/scout/agent_runner_spec.rb`

### Implementation for User Story 1

- [X] T004 [US1] Wire `chat.with_schema(Custom::Scout::ResponseSchema)` into the chat built in `Custom::Scout::AgentRunner#generate_and_process_response` (alongside the existing `chat.with_tool` calls) in `custom/app/services/custom/scout/agent_runner.rb`
- [X] T005 [US1] Update `Custom::Scout::AgentRunner#parse_structured_response` to accept `content` as either an already-parsed `Hash` (schema mode succeeded) or a `String` (existing fenced-JSON/plain-text fallback, unchanged), extracting `response`/`reasoning` from whichever shape is present, in `custom/app/services/custom/scout/agent_runner.rb`

**Checkpoint**: At this point, User Story 1 is fully functional and testable independently. Scout should complete the large majority of conversation turns instead of defaulting to a human handoff.

---

## Phase 3: User Story 2 - The existing safety guarantee still holds on genuine failures (Priority: P2)

**Goal**: Confirm that when a usable response still cannot be obtained — even with schema enforcement active — Scout continues to fail closed exactly as it does today: no raw/malformed content shown to the customer, existing private note created, existing fail-safe handoff triggered. This is a regression check on already-existing (Phase 08) behavior, not new implementation.

**Independent Test**: Force a genuine response failure (e.g. a model/provider that cannot produce a valid response even under schema enforcement) and confirm the customer never sees raw or malformed content, and the conversation is still handed off to a human, exactly as before.

**Depends on**: User Story 1 (Phase 2) — this story verifies the fail-closed path continues to hold *with* schema enforcement active, so T004/T005 must exist first.

### Tests for User Story 2

> **NOTE: Write this test FIRST, ensure it exercises the existing (unchanged) fail-safe path correctly**

- [X] T006 [US2] Add an RSpec test that forces `parse_structured_response` to fail even with the schema wired in (e.g. `response.content` is a `Hash` missing the `response` key, or a `String` that still fails `JSON.parse`) and asserts the existing fail-closed behavior is unchanged: no raw/malformed content ever passed to `dispatch_outgoing_reply`, existing private alert note created, existing fail-safe handoff (`perform_fail_safe_handoff`) triggered, in `custom/spec/services/custom/scout/agent_runner_spec.rb`

**Checkpoint**: At this point, both user stories are verified — Scout reliably completes conversations (US1), and the pre-existing safety guarantee is confirmed intact under the new schema-enforced path (US2).

---

## Phase 4: Polish & Cross-Cutting Concerns

**Purpose**: Verification, code quality, full test suite validation, and regression prevention.

- [X] T007 [P] Run RuboCop lint checks on `custom/app/services/custom/scout/response_schema.rb`, `custom/app/services/custom/scout/agent_runner.rb`, and their specs
- [X] T008 Run full RSpec test suite for Scout services in `custom/spec/services/custom/scout/`
- [X] T009 [P] Execute quickstart manual validation scenarios per `specs/057-scout-structured-response-reliability/quickstart.md`, including the Langfuse trace spot-check if the account has feature 056's observability configured

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately.
- **User Story 1 (Phase 2)**: Depends on Setup (T001) — needs `Custom::Scout::ResponseSchema` to exist before it can be wired into the chat.
- **User Story 2 (Phase 3)**: Depends on User Story 1 (Phase 2) — unlike a typical independent story, US2 specifically verifies the fail-closed path *with* schema enforcement active, so T004/T005 must be implemented first. This dependency is explicit in the spec's own "Independent Test" wording ("despite the reliability improvements").
- **Polish (Phase 4)**: Depends on completion of User Stories 1 and 2.

### Within Each User Story

- Tests MUST be written and fail before implementation (T002/T003 before T004/T005; T006 exercises behavior that already exists unchanged, written to confirm no regression).
- Schema class (T001) before it is wired into the chat (T004).
- `with_schema` wiring (T004) before the parsing-shape change that depends on it (T005) — both touch the same file sequentially.

### Parallel Opportunities

- US1 test tasks `T002` and `T003` touch different files and can run in parallel.
- `T004` and `T005` both touch `agent_runner.rb` and must run sequentially, not in parallel.
- Polish tasks `T007` and `T009` can run in parallel.

---

## Parallel Example: User Story 1

```bash
# Launch test creation for User Story 1 together:
Task: "Add RSpec tests for Custom::Scout::ResponseSchema shape/validity in custom/spec/services/custom/scout/response_schema_spec.rb"
Task: "Add RSpec tests for AgentRunner schema wiring and Hash/String parsing in custom/spec/services/custom/scout/agent_runner_spec.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup: `Custom::Scout::ResponseSchema`).
2. Complete Phase 2 (User Story 1: tests + schema wiring + Hash/String parsing).
3. **STOP and VALIDATE**: Verify with `bundle exec rspec custom/spec/services/custom/scout/response_schema_spec.rb custom/spec/services/custom/scout/agent_runner_spec.rb`, then run a handful of real conversations per `quickstart.md` to confirm the failure rate has actually dropped.
4. Deploy/demo MVP (Scout completes conversations instead of defaulting to human handoff).

### Incremental Delivery

1. Setup → schema class ready.
2. User Story 1 → fixes the near-100% parsing failure rate (MVP).
3. User Story 2 → regression-verifies the existing fail-closed guarantee still holds.
4. Polish → RuboCop, full Scout test suite, quickstart manual validation.

---

## Notes

- `[P]` tasks = different files, no dependencies on incomplete tasks.
- `[Story]` label maps task to specific user story for traceability.
- All tasks follow strict checklist formatting: `- [ ] [TaskID] [P?] [Story?] Description with file path`.
- Unlike feature 056, User Story 2 here is intentionally dependent on User Story 1 (not independent) — it is a regression check on the new code path, not a standalone capability.
