# Tasks: Scout Response Auditor

**Input**: Design documents from `/specs/058-scout-response-auditor/` (`spec.md`, `plan.md`, `data-model.md`, `research.md`, `quickstart.md`)
**Constitution**: `.specify/memory/constitution.md`

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add the per-account opt-in gate every other task is built behind.

- [X] T001 Add migration `db/migrate/21260828230000_add_response_auditor_flag_to_ichatr_scouts.rb` adding `feature_response_auditor` boolean (`null: false, default: false`) to `ichatr_scouts`, mirroring the existing `feature_memory` column shape in `db/migrate/21260819000005_add_pipeline_fields_to_ichatr_scouts.rb:7` (additive `up`, column-removing `down`); run `docker compose exec rails bundle exec rails db:migrate`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Give `AgentRunner` visibility into the turn's real tool activity — the ground truth both user stories' detectors need. No user story can be implemented until this exists.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 [P] Add RSpec tests for `Custom::Scout::Tools::CallRecorder` in `custom/spec/services/custom/scout/tools/call_recorder_spec.rb`: wrapping a tool records `{tool_name:, arguments:, simulated:, result:}` on success; a tool that raises still gets a record appended (via `ensure`) with `{tool_name:, arguments:, simulated:, error:}` and no `result:` key, and the exception still propagates to the caller; `simulated:` is whatever the includer passed in, not computed by the module itself
- [X] T003 Create `Custom::Scout::Tools::CallRecorder` in `custom/app/services/custom/scout/tools/call_recorder.rb` — extracted from `PlaygroundRunner#wrap_tool`/`#execute_and_record` (`custom/app/services/custom/scout/playground_runner.rb:70-93`) unchanged in mechanism (patches each tool's `#execute` via `define_singleton_method`, sitting underneath `BaseTool#call`'s existing `instrument_tool_call` layer), exposing `recorded_tool_calls` (array, reset per instance) and a method the includer calls per tool to wrap-and-register it, taking `simulated:` as an explicit argument rather than hardcoding `tool_name != 'call_custom_api'` (depends on T002)
- [X] T004 Refactor `Custom::Scout::PlaygroundRunner` (`custom/app/services/custom/scout/playground_runner.rb`) to `include Custom::Scout::Tools::CallRecorder`, replacing its private `wrap_tool`/`execute_and_record` methods, passing `simulated: tool_name != 'call_custom_api'` at the call site — no behavior change (depends on T003)
- [X] T005 Run `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/playground_runner_spec.rb` to confirm the T004 refactor introduced no regression in `recorded_tool_calls`' shape or Playground's existing simulated-response behavior
- [X] T006 Wire `Custom::Scout::Tools::CallRecorder` into `Custom::Scout::AgentRunner` (`custom/app/services/custom/scout/agent_runner.rb`): `include` the module, wrap each tool built in `#build_tools` with `simulated: false` before registering it with the chat via `with_tool`, exposing `@recorded_tool_calls` scoped to the current turn (depends on T003)

**Checkpoint**: `AgentRunner` now records what tools actually ran (and how) each turn. Both user stories can now be implemented.

---

## Phase 3: User Story 1 - Customer never receives a false claim about a completed action (Priority: P1) 🎯 MVP

**Goal**: Ground a reply-consistency check in the turn's real tool activity so a reply claiming an opportunity/stage/data update already happened — when no matching tool call succeeded — is corrected or escalated to a human before the customer ever sees it.

**Independent Test**: Run a real qualification conversation where the customer asks Scout to perform an opportunity/stage update and the update tool doesn't end up (successfully) called for that turn; confirm the customer never receives a reply claiming the action was completed — the conversation is instead repaired or handed to a human.

### Tests for User Story 1

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T007 [P] [US1] Add RSpec tests for `Custom::Scout::ClaimConsistencySchema` in `custom/spec/services/custom/scout/claim_consistency_schema_spec.rb`: `decision` is a required string enum `safe | false_promise | false_completed_action`; `reason` is a required string; produces a valid JSON Schema
- [X] T008 [P] [US1] Add RSpec tests for `Custom::Scout::ClaimConsistencyService#check` in `custom/spec/services/custom/scout/claim_consistency_service_spec.rb`: calls `@scout.llm_chat(temperature: 0.0).with_schema(Custom::Scout::ClaimConsistencySchema)`, its prompt includes conversation history, the drafted reply text, and the turn's `recorded_tool_calls`; a recorded call with an `error:` key (tool ran but failed) does not count as grounding a "completed" claim, matching the clarified spec decision; wrapped in `instrument_llm_call`; any `StandardError` is rescued, reported via `ChatwootExceptionTracker`, logged, and returns a "no decision" sentinel rather than raising
- [X] T009 [P] [US1] Add RSpec tests for `Custom::Scout::ResponseAuditor` (US1 slice) in `custom/spec/services/custom/scout/response_auditor_spec.rb`: a `safe` consistency decision leaves the reply unchanged; a `false_completed_action` decision triggers exactly one internal repair `chat.ask(...)` call on the same `chat` object (never a customer-visible message), then one reverification; if still inconsistent after that single repair, escalates via `AgentRunner#perform_fail_safe_handoff`; any `StandardError` raised anywhere in the audit is rescued (`ChatwootExceptionTracker` + log) and resolves to "proceed with the original reply," never blocking delivery (FR-009); `ClaimConsistencyService#check` is never called (neither the initial call, the repair, nor the reverification) once the conversation is no longer `pending` — simulate the conversation status flipping to non-`pending` (e.g. a human agent takes over) between two of `#audit`'s internal steps and assert every step after that point is skipped, with no repair/escalation attempted (FR-013, spec Edge Cases "human already took over mid-turn")
- [X] T010 [US1] Extend `custom/spec/services/custom/scout/agent_runner_spec.rb`: with `feature_response_auditor: false` (default) on the Scout, a reply falsely claiming a completed action is delivered unchanged (no `ResponseAuditor`/extra LLM calls) — baseline regression per FR-008; with `feature_response_auditor: true`, the same false claim is corrected or escalated before `dispatch_outgoing_reply` runs; `responses_consumed` increments by exactly 1 for the turn regardless of how many auditor/repair calls happened (FR-012); no new `Messages::MessageBuilder`/message-creation call site is introduced outside the existing ones (FR-010)

### Implementation for User Story 1

- [X] T011 [P] [US1] Create `Custom::Scout::ClaimConsistencySchema < RubyLLM::Schema` in `custom/app/services/custom/scout/claim_consistency_schema.rb`: `string :decision, enum: %w[safe false_promise false_completed_action]`, `string :reason`, both required (strict mode, matching `Custom::Scout::ResponseSchema`'s existing default)
- [X] T012 [US1] Create `Custom::Scout::ClaimConsistencyService` in `custom/app/services/custom/scout/claim_consistency_service.rb` — `initialize(scout:, conversation:)`, `#check(message_history:, assistant_response:, recorded_tool_calls:)`; mirrors the shape of `Captain::Llm::AssistantFalsePromiseService` (`enterprise/app/services/captain/llm/assistant_false_promise_service.rb`, read-only reference, not copied text): `@scout.llm_chat(temperature: 0.0).with_schema(Custom::Scout::ClaimConsistencySchema).with_instructions(...).ask(prompt)` wrapped in `instrument_llm_call`; builds its own prompt (conversation history + drafted reply + a labeled `recorded_tool_calls` context block, since Captain's prompt helper has no tool-call parameter to reuse); `rescue StandardError => e` → `ChatwootExceptionTracker.new(e, account: @scout.account).capture_exception`, `Rails.logger.warn`, return `{'decision' => nil, 'reason' => nil, 'error' => e.message}` (depends on T011)
- [X] T013 [US1] Create `Custom::Scout::ResponseAuditor` in `custom/app/services/custom/scout/response_auditor.rb` — `initialize(scout:, conversation:)`, `#audit(chat:, response_text:, message_history:, recorded_tool_calls:)` implementing the US1 slice of the orchestration from `research.md` §4: **before calling `ClaimConsistencyService#check` — both the initial call and the reverification call after repair — re-check that the conversation is still `pending` (reload/uncached, matching the pattern `AgentRunner#conversation_pending?` already uses) and return immediately with the original `response_text` unchanged if it is not** (FR-013/spec Edge Cases: a human may take over while the audit's own LLM calls are in flight, and the checks must never run against, or interfere with, a conversation a human has already taken over); when still pending, call `ClaimConsistencyService#check`; on `false_promise`/`false_completed_action`, send one internal repair instruction via `chat.ask(...)` on the same `chat` object (never customer-visible), re-check pending status again, then call `ClaimConsistencyService#check` once more if still pending; if still inconsistent, call `AgentRunner#perform_fail_safe_handoff`-equivalent behavior (see T014 for how the caller wires this) and signal escalation; wrap the whole method in `rescue StandardError => e` → `ChatwootExceptionTracker` + log, resolving to "return the original `response_text` unchanged" (FR-009) (depends on T012)
- [X] T014 [US1] Wire `Custom::Scout::AgentRunner#process_response` (`custom/app/services/custom/scout/agent_runner.rb`): when `@scout.feature_response_auditor?`, after `parse_structured_response` succeeds and before `dispatch_outgoing_reply`, call `Custom::Scout::ResponseAuditor#audit` with the turn's `chat`, `parsed[:response]`, the turn's message history (build/reuse the same `{role:, content:}`-shaped array `#instrumentation_params` already builds — e.g. extract that message-building logic into a helper both `#instrumentation_params` and `#process_response` call, or store it as an instance variable when `#execute_chat` runs — so `ClaimConsistencyService`/`ActionClassifierService` receive the same shape their specs assume), and `@recorded_tool_calls`; use its result as the reply to dispatch, or call `perform_fail_safe_handoff('Resposta inconsistente com as ações executadas.')` and return early when it signals escalation (depends on T006, T013)

**Checkpoint**: User Story 1 is fully functional and independently testable — a false "already done" claim is now caught, corrected, or escalated before reaching the customer.

---

## Phase 4: User Story 2 - Promised actions, including human handoff, always actually happen (Priority: P2)

**Goal**: Catch any drafted reply that promises future work (handoff or otherwise) with no matching tool call, and separately route an explicit customer request for a human to a real handoff regardless of what Scout's own reply says.

**Independent Test**: Run a conversation where Scout's drafted reply promises a human handoff (or some other future action) without the corresponding action being triggered, and a separate conversation where the customer explicitly asks for a human agent; confirm both end up as a real human handoff or a corrected reply — never left `pending` indefinitely.

**Depends on**: User Story 1 (Phase 3) — extends the same `Custom::Scout::ResponseAuditor` (T013) with the action-classification step and the repair-loop's re-classification pass, so T013/T014 must exist first.

### Tests for User Story 2

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T015 [P] [US2] Add RSpec tests for `Custom::Scout::ActionClassifierSchema` in `custom/spec/services/custom/scout/action_classifier_schema_spec.rb`: `action` is a required string enum `continue | handoff`; `action_reason` is a required string enum (`explicit_human_request`, `human_offer_accepted`, `repeated_frustration_or_loop`, `out_of_scope_commercial_request`)
- [X] T016 [P] [US2] Add RSpec tests for `Custom::Scout::ActionClassifierService#classify` in `custom/spec/services/custom/scout/action_classifier_service_spec.rb`: calls `@scout.llm_chat(temperature: 0.0).with_schema(Custom::Scout::ActionClassifierSchema)`, judges the customer's own messages independent of Scout's drafted reply text, returns normalized `{action:, action_reason:}`; any `StandardError` is rescued, reported via `ChatwootExceptionTracker`, and returns a "no decision" sentinel rather than raising
- [X] T017 [US2] Extend `custom/spec/services/custom/scout/response_auditor_spec.rb`: `ActionClassifierService` runs first (only while the conversation is still `pending`); `action == 'handoff'` calls `Custom::Scout::HandoffService#perform(reason: action_reason)` and skips `ClaimConsistencyService` entirely for that turn (no double-handling, matching `research.md` §4's orchestration order); a `false_promise` decision (any future action, not just handoff — broad per the spec's clarified scope) goes through the same one-repair-then-escalate flow US1 established for `false_completed_action`; after a repair attempt, `ActionClassifierService` is re-run (if the conversation is still pending) before `ClaimConsistencyService`'s reverification; T013's per-step pending re-check (before each `ClaimConsistencyService#check` call) still holds once `ActionClassifierService` is added — assert a conversation that stops being `pending` between the `ActionClassifier` step and the `ClaimConsistency` step causes `#audit` to stop there too, calling neither `HandoffService` nor `ClaimConsistencyService`
- [X] T018 [US2] Extend `custom/spec/services/custom/scout/agent_runner_spec.rb`: an explicit customer request for a human (e.g. "let me talk to a person") results in `Custom::Scout::HandoffService#perform` being called even when Scout's own drafted reply doesn't mention handoff; a broken handoff promise, and separately a broken non-handoff future-work promise, each end up either repaired or escalated via `perform_fail_safe_handoff` — never left `pending` indefinitely; with `feature_response_auditor: false`, neither scenario triggers any proactive handoff beyond what Scout's own reply/tool use already does (FR-008 baseline for this story)

### Implementation for User Story 2

- [X] T019 [P] [US2] Create `Custom::Scout::ActionClassifierSchema < RubyLLM::Schema` in `custom/app/services/custom/scout/action_classifier_schema.rb`: `string :action, enum: %w[continue handoff]`, `string :action_reason, enum: %w[explicit_human_request human_offer_accepted repeated_frustration_or_loop out_of_scope_commercial_request]`, both required
- [X] T020 [US2] Create `Custom::Scout::ActionClassifierService` in `custom/app/services/custom/scout/action_classifier_service.rb` — `initialize(scout:, conversation:)`, `#classify(message_history:)`; mirrors the shape of `Captain::Llm::AssistantActionClassifierService` (`enterprise/app/services/captain/llm/assistant_action_classifier_service.rb`, read-only reference, not copied text) but with `@scout.llm_chat(temperature: 0.0)` instead of Captain's `Llm::BaseAiService`/model-routing, and Scout's own commercial-domain reasons instead of Captain's support-domain reason list; same `instrument_llm_call` + `rescue StandardError` → `ChatwootExceptionTracker` + log + sentinel pattern as T012 (depends on T019)
- [X] T021 [US2] Extend `Custom::Scout::ResponseAuditor#audit` (`custom/app/services/custom/scout/response_auditor.rb`) to run `ActionClassifierService#classify` first, only while the conversation is still `pending`: on `action == 'handoff'`, call `Custom::Scout::HandoffService.new(scout: @scout, conversation: @conversation).perform(reason: action_reason)` and return immediately (skip `ClaimConsistencyService` for this turn); otherwise fall through to the existing `ClaimConsistencyService` flow from T013 **unchanged, including its own pending re-checks before each `ClaimConsistencyService#check` call** — do not remove or bypass those when adding the `ActionClassifier` step in front of them; after a repair attempt (still inside the existing one-repair-cycle), re-run `ActionClassifierService` (if still `pending`) before `ClaimConsistencyService`'s reverification, applying the same handoff short-circuit if it now requests one (depends on T013, T020)

**Checkpoint**: User Stories 1 and 2 both work independently — false completed-action claims and broken promises (handoff or otherwise) are both caught, and explicit human requests are routed correctly regardless of Scout's own reply text.

---

## Phase 5: User Story 3 - Operators can enable this safety net per account without any risk to accounts that don't opt in (Priority: P3)

**Goal**: Confirm the flag genuinely gates all new behavior with zero cost when off, and is invisible to the customer experience when on and nothing is wrong.

**Independent Test**: Compare conversation behavior and LLM-call/`responses_consumed` accounting for the same account with the capability off vs. on; confirm no functional or billing-relevant difference when off, and that a normal ("safe") turn is unaffected when on.

**Depends on**: User Stories 1 and 2 (Phases 3-4) — this story verifies the flag-gating and no-op-when-safe guarantees across the complete auditor built by both prior stories, the same relationship Phase 057's own regression story (US2) had to its US1.

### Tests for User Story 3

- [X] T022 [P] [US3] Add RSpec tests in `custom/spec/services/custom/scout/agent_runner_spec.rb`: with `feature_response_auditor: false` across several distinct conversations/turn shapes (with and without tool calls), `Custom::Scout::ResponseAuditor.new` is never instantiated and neither `ActionClassifierService` nor `ClaimConsistencyService` ever receives an LLM call — a general, scenario-independent assertion (distinct from US1/US2's scenario-specific flag-off checks)
- [X] T023 [US3] Add RSpec test in `custom/spec/services/custom/scout/agent_runner_spec.rb`: with `feature_response_auditor: true` and a "safe" turn (reply makes no false/unsupported claim, any promised action has a matching successful tool call), the customer receives exactly the model's original reply with no extra customer-visible message, `responses_consumed` still increments by exactly 1, and no handoff is triggered

**Checkpoint**: All three user stories are independently functional and verified — the safety net is opt-in, zero-cost when off, and invisible when on and nothing is wrong.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Verification, code quality, full test suite validation, and regression prevention.

- [X] T024 [P] Run RuboCop on all new/modified files (`docker compose exec rails bundle exec rubocop custom/app/services/custom/scout/tools/call_recorder.rb custom/app/services/custom/scout/action_classifier_schema.rb custom/app/services/custom/scout/action_classifier_service.rb custom/app/services/custom/scout/claim_consistency_schema.rb custom/app/services/custom/scout/claim_consistency_service.rb custom/app/services/custom/scout/response_auditor.rb custom/app/services/custom/scout/agent_runner.rb custom/app/services/custom/scout/playground_runner.rb db/migrate/21260828230000_add_response_auditor_flag_to_ichatr_scouts.rb custom/spec/services/custom/scout/tools/call_recorder_spec.rb custom/spec/services/custom/scout/action_classifier_schema_spec.rb custom/spec/services/custom/scout/action_classifier_service_spec.rb custom/spec/services/custom/scout/claim_consistency_schema_spec.rb custom/spec/services/custom/scout/claim_consistency_service_spec.rb custom/spec/services/custom/scout/response_auditor_spec.rb custom/spec/services/custom/scout/agent_runner_spec.rb`), ensuring 0 offenses and 150-char line limit compliance per `AGENTS.md`
- [X] T025 Run the full Scout spec suite (`docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/`) to verify no regressions across other Scout tools/services (Opportunity, Contact, Notes, SystemPrompts, Handover, Catalog)
- [X] T026 Manual walkthrough / verification checks per `quickstart.md` §3: verify `feature_response_auditor` column defaults to `false` in `rails console`, verify `feature_response_auditor?` predicate works on `Scout` model, verify `AgentRunner` flag toggle cleanly branches without error in `specs/058-scout-response-auditor/quickstart.md`, including the Gemini-specific run flagged in its Prerequisites (validates `research.md` §4's flagged, pre-existing `with_schema`+`with_tool` risk empirically) and the SC-001 through SC-006 cross-checks

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately.
- **Foundational (Phase 2)**: No hard dependency on Setup — T002-T006 (`CallRecorder`) can start immediately in parallel with T001; only User Story 1's T014 needs T001's migrated column to exist by the time it runs. Both phases still BLOCK all user stories.
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2) — needs `@recorded_tool_calls` (T006) to exist before `ClaimConsistencyService` has grounding data to check against.
- **User Story 2 (Phase 4)**: Depends on User Story 1 (Phase 3) — extends the same `ResponseAuditor` class (T013) rather than being a parallel, independent file.
- **User Story 3 (Phase 5)**: Depends on User Story 1 AND User Story 2 (Phases 3-4) — verifies the complete gated behavior both stories built together.
- **Polish (Phase 6)**: Depends on all desired user stories being complete.

### Within Each User Story

- Tests MUST be written and fail before implementation (T007-T010 before T011-T014; T015-T018 before T019-T021).
- Schema classes before the services that use them (T011 before T012; T019 before T020).
- Services before the orchestrator that calls them (T012 before T013; T020 before T021).
- Orchestrator before the `AgentRunner` call site that wires it in (T013 before T014).

### Parallel Opportunities

- Foundational: T002 (CallRecorder tests) has no other file dependency and can start immediately; T003 depends on T002 existing first (tests-first), but nothing else in Setup/Foundational is parallelizable with it since T004/T005/T006 all depend on T003.
- US1 tests: T007, T008, T009 touch different files and can run in parallel; T010 extends a shared file (`agent_runner_spec.rb`) other stories also touch, so treat it as sequential relative to US2/US3's edits to the same file.
- US1 implementation: T011 has no dependency and can start as soon as T007 exists; T012-T014 are sequential (same-file/depends-on-previous-file chain).
- US2 tests: T015, T016 touch different files and can run in parallel; T017/T018 extend shared spec files US1 already touched — sequential relative to those.
- US2 implementation: T019 can run in parallel with any remaining US1 cleanup; T020-T021 are sequential.
- US3: T022 and T023 both extend `agent_runner_spec.rb` — sequential, not parallel, despite the `[P]` marker on T022 (marker reflects that T022 has no *implementation* dependency, not that it can run concurrently with T023 in the same file).
- Polish: T024 and T026 can run in parallel; T025 should run after T024 (lint clean) for a meaningful full-suite signal, though it has no hard code dependency.

---

## Parallel Example: User Story 1

```bash
# Launch independent US1 test-writing together:
Task: "Add RSpec tests for Custom::Scout::ClaimConsistencySchema in custom/spec/services/custom/scout/claim_consistency_schema_spec.rb"
Task: "Add RSpec tests for Custom::Scout::ClaimConsistencyService#check in custom/spec/services/custom/scout/claim_consistency_service_spec.rb"
Task: "Add RSpec tests for Custom::Scout::ResponseAuditor (US1 slice) in custom/spec/services/custom/scout/response_auditor_spec.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup: migration) + Phase 2 (Foundational: `CallRecorder`).
2. Complete Phase 3 (User Story 1: `ClaimConsistencySchema`/`Service` + `ResponseAuditor` + `AgentRunner` wiring).
3. **STOP and VALIDATE**: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/custom/scout/claim_consistency_schema_spec.rb custom/spec/services/custom/scout/claim_consistency_service_spec.rb custom/spec/services/custom/scout/response_auditor_spec.rb custom/spec/services/custom/scout/agent_runner_spec.rb`, then run the User Story 1 section of `quickstart.md` against a real conversation.
4. Deploy/demo MVP (false "already done" claims are caught before reaching the customer).

### Incremental Delivery

1. Setup + Foundational → tool-call ground truth ready.
2. User Story 1 → false completed-action claims caught (MVP).
3. User Story 2 → broken promises (handoff or otherwise) and explicit human requests also caught/routed.
4. User Story 3 → flag-off zero-cost and flag-on invisible-when-safe guarantees verified.
5. Polish → RuboCop, full Scout suite, quickstart manual validation (including the Gemini empirical check).

---

## Notes

- `[P]` tasks = different files, no dependencies on incomplete tasks.
- `[Story]` label maps task to specific user story for traceability.
- All tasks follow strict checklist formatting: `- [ ] [TaskID] [P?] [Story?] Description with file path`.
- Unlike a fully independent story set, User Story 2 (extends `ResponseAuditor`) and User Story 3 (verifies both) are intentionally dependent on earlier stories here — the same relationship Phase 057's own US2 had to its US1 — because the orchestration order mandated by `research.md` §4 (action classifier always before claim consistency) means both detectors live in one orchestrator class, not two independent ones.
- `research.md` §4's flagged Gemini `with_schema`+`with_tool` risk is pre-existing (inherited from Phase 057) and out of scope to fix here; T026 includes the recommended empirical check rather than a code task.

---

## Phase 7: Convergence

**Purpose**: Close a gap found by `/speckit-converge` between the implemented code and the feature's stated intent (spec/plan/tasks), verified by direct code inspection plus a clean RuboCop and full Scout spec-suite run.

- [X] T027 Fix the schema/prompt contradiction in `Custom::Scout::ActionClassifierService`'s `continue` path per FR-003 (contradicts): in `custom/app/services/custom/scout/action_classifier_schema.rb`, add `required: false` to the `string :action_reason, enum: REASONS` declaration (supported directly by the installed `ruby_llm-schema` 0.3.0's `PrimitiveTypes#string`); in `custom/app/services/custom/scout/action_classifier_service.rb`'s `system_instructions`, change "Quando action for 'continue', o action_reason pode ser omitido ou retornar 'continue'" to instruct the model to omit `action_reason` entirely when `action` is `'continue'` — dropping the "or return `'continue'`" alternative, since `'continue'` is not a valid `REASONS` enum member and asking the model to emit it (or to omit a field the schema currently marks required) puts two incompatible constraints on the same live provider call, a case `action_classifier_service_spec.rb`'s fully-mocked `chat.ask` cannot surface. Add/extend a spec asserting a `continue` response with no `action_reason` in the mocked content still normalizes to `{'action' => 'continue', 'action_reason' => nil}` without hitting the `invalid_classifier_response` branch.
