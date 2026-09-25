---
description: "Task list for Scout V2 Turn Runner and Qualification Playbook (Playground)"
---

# Tasks: Scout V2 Turn Runner and Qualification Playbook (Playground)

**Input**: Design documents from `/specs/083-scout-turn-runner-playground/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/, quickstart.md

**Tests**: Tests are included per Constitution VI (Test-Driven Development) and the specification's acceptance scenarios.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Rails monorepo custom tree**: `custom/app/`, `custom/playbooks/`, `custom/spec/`
- **Config & scripts**: `config/features.yml`, `bin/sync-custom-module-hooks`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Configuration flags, sync hooks manifest, and initial playbook definition

- [X] T001 Register `scout_v2` feature flag under `feature_flags_ext_1` in `config/features.yml`
- [X] T002 [P] Add MANIFEST entry for `scout_v2` in `bin/sync-custom-module-hooks` anchoring on `delayed_automations` / `erp_integration`
- [X] T003 [P] Create the `qualificacao` playbook with YAML frontmatter and step instructions in `custom/playbooks/qualificacao.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Sandbox conversation resolver required before any playground turn can be executed or tested

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T004 [P] Write unit tests for playground sandbox conversation resolver in `custom/spec/services/custom/scout_v2/playground_conversation_spec.rb` verifying idempotent find-or-create of dedicated `Contact`, `Channel::Api`, `Inbox`, `ScoutInbox`, `ContactInbox`, and open `Conversation`, as well as account isolation and zero duplicate creations
- [X] T005 Implement `Custom::ScoutV2::PlaygroundConversation.for(scout)` in `custom/app/services/custom/scout_v2/playground_conversation.rb` providing idempotent resolution of per-scout sandbox conversation

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - A v2 turn executes end-to-end in the playground (Priority: P1) 🎯 MVP

**Goal**: Execute a complete Scout turn on the new engine with exactly one top-level LLM call (no audit, classifier, or repair calls), assemble the prompt and tool catalog fresh from the active playbook, persist `ScoutConversationState` before reply dispatch, fall back cleanly when no playbook matches, and ensure flag gating restores v1 behavior immediately when disabled.

**Independent Test**: Can be fully tested by fixing one playbook as active and doubling the language-model client, then confirming the assembled prompt, the assembled tool catalog, and the persisted routing state — without needing a real conversational reply or a live model call.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T006 [P] [US1] Write unit and contract specs for `Custom::ScoutV2::TurnRunner` in `custom/spec/services/custom/scout_v2/turn_runner_spec.rb` verifying: exactly one top-level LLM call per turn; prompt assembly with active playbook step body (and absence of v1 guardrails/funnel guidelines); tool catalog composition containing only declared tools plus `search_knowledge_base` (and strict exclusion of `move_opportunity_stage`, `handover_to_human`, `call_custom_api`); persistence of `active_playbook` and `activation_reason` to `ScoutConversationState` before returning; and fallback prompt with knowledge lookup only when no playbook matches
- [X] T007 [P] [US1] Write request specs for playground messages controller `scout_v2` dispatch in `custom/spec/requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb` verifying that with `scout_v2` enabled, requests resolve sandbox conversation and dispatch via `TurnRunner`, rendering `{ reply:, tool_calls: }`; without `scout_v2`, requests use existing `PlaygroundRunner`; and toggling the flag between requests switches execution path immediately without restart
- [X] T008 [P] [US1] Write job specs for process message job `scout_v2` dispatch in `custom/spec/jobs/custom/scout/process_message_job_spec.rb` verifying that with `scout_v2` enabled, `process_debounce` dispatches via `TurnRunner` and creates an outgoing message reply; without `scout_v2`, it dispatches via existing `AgentRunner`; and toggling the flag switches execution path immediately

### Implementation for User Story 1

- [X] T009 [US1] Implement `Custom::ScoutV2::TurnRunner` core service in `custom/app/services/custom/scout_v2/turn_runner.rb` with infra gate (quota/API key check), catalog loading, snapshot construction via `RoutingSnapshot::Builder`, router invocation, conditional `ScoutConversationState#record_state_activation!` persistence, prompt assembly, tool catalog wrapping via `CallRecorder#wrap_tool`, message history appending, and single top-level `chat.ask` call returning `{ reply:, tool_calls: }`
- [X] T010 [US1] Add `scout_v2` feature flag dispatch branch in `custom/app/controllers/api/v1/accounts/scouts/playground_messages_controller.rb` using `Custom::ScoutV2::PlaygroundConversation.for(@scout)` and `TurnRunner.new` when `Current.account.feature_enabled?('scout_v2')`, preserving existing `PlaygroundRunner` fallback
- [X] T011 [US1] Add `scout_v2` feature flag dispatch branch in `custom/app/jobs/custom/scout/process_message_job.rb` in `process_debounce` using `TurnRunner.new` when `@scout.account.feature_enabled?('scout_v2')`, creating outgoing `Message` and recording consumed response, preserving existing `AgentRunner` fallback

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently (MVP ready!)

---

## Phase 4: User Story 2 - Every v2 turn is observable from day one (Priority: P2)

**Goal**: Each v2 turn produces one instrumented session carrying exactly one top-level language-model generation containing inspectable metadata for active playbook name, activation reason, and unsatisfied flags (pending fields and unmet capability requirements). Every executed tool appears as its own instrumented record.

**Independent Test**: Can be fully tested by executing one turn with a doubled tracing backend/instrumentation and confirming a single session with a single top-level generation carrying the right attributes, plus one instrumented record per tool call — no live conversation or real model call required.

### Tests for User Story 2 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T012 [P] [US2] Add observability specs to `custom/spec/services/custom/scout_v2/turn_runner_spec.rb` verifying that `instrument_agent_session` and `instrument_llm_call` wrap the single LLM call with span name `llm.scout_v2.turn_runner`, feature name `scout_v2_turn_runner`, metadata containing `scout_id`, `playbook`, `activation_reason`, and read-only `unsatisfied_flags` (pending fields and unmet requires); per-tool Langfuse instrumentation (FR-015/Turn Trace) is inherited unchanged from `Custom::Scout::Tools::BaseTool#call`'s `instrument_tool_call` wrapper (already covered generically by `base_tool_spec.rb`, not re-tested here) — this spec instead verifies `CallRecorder` populates `result[:tool_calls]` (the array returned to the playground UI, a separate concern from tracing) with one entry per executed tool call

### Implementation for User Story 2

- [X] T013 [US2] Implement Langfuse instrumentation in `custom/app/services/custom/scout_v2/turn_runner.rb` integrating `Integrations::LlmInstrumentation` with `instrument_agent_session`, `instrument_llm_call`, and private `instrumentation_params` assembling span metadata (`scout_id`, `playbook`, `activation_reason`, and read-only `unsatisfied_flags`)

**Checkpoint**: At this point, User Stories 1 and 2 should both work and be fully observable

---

## Phase 5: User Story 3 - The qualification playbook actually qualifies a lead in the playground (Priority: P3)

**Goal**: With an open opportunity and pending required fields, the router activates the qualification playbook by conversation state, formatting pending fields in the prompt. The assistant follows playbook steps to collect missing information, recording values via `manage_opportunity`. Across multi-turn exchanges where state holds, the conversation stays on the qualification playbook without re-routing every turn, and no `Message` records are created on the sandbox conversation.

**Independent Test**: Can be fully tested by running a multi-turn dialogue against a conversation with an open opportunity and pending required fields, confirming the fields the customer supplies end up recorded through the opportunity-management tool, that the conversation is not re-routed away from the qualification playbook while collection is still in progress, and that no `Message` rows leak to the sandbox conversation.

### Tests for User Story 3 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**
- [X] T014 [P] [US3] Write multi-turn qualification integration specs in `custom/spec/services/custom/scout_v2/turn_runner_spec.rb` simulating a multi-turn dialogue: verifying router activates `qualificacao` by state when open opportunity has pending fields; prompt includes dynamic formatted pending fields section; tool call to `manage_opportunity` updates opportunity `custom_attributes`; second turn retains `qualificacao` without redundant state writes; and sandbox conversation has zero `Message` records

### Implementation for User Story 3

- [X] T015 [US3] Implement dynamic pending fields prompt formatting in `custom/app/services/custom/scout_v2/turn_runner.rb` extracting attribute labels and descriptions via `CustomAttributeDefinition` lookup on `ctx.pending_fields` and appending the "Campos pendentes para esta oportunidade:" section to the prompt when `qualificacao` is active
- [X] T016 [US3] Implement router continuity and state activation write guards in `custom/app/services/custom/scout_v2/turn_runner.rb` ensuring `record_state_activation!` is called only on initial/changed activation and skipped when `decision.playbook == ctx.active_playbook`

**Checkpoint**: All user stories should now be independently functional and integrated

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Improvements, end-to-end verification, and quality gates across all stories

- [X] T017 [P] Verify boot validation of `custom/playbooks/qualificacao.md` in `custom/spec/services/custom/scout_v2/playbook/loader_spec.rb` and `custom/spec/services/custom/scout_v2/playbook/validator_spec.rb` ensuring the new playbook passes schema validation cleanly
- [X] T018 [P] Run targeted RSpec test suite covering `custom/spec/services/custom/scout_v2/**`, `custom/spec/jobs/custom/scout/process_message_job_spec.rb`, and `custom/spec/requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb`
- [X] T019 [P] Execute scenarios 1 through 5 from `specs/083-scout-turn-runner-playground/quickstart.md` via `rails runner` to validate single-call LLM turn, fallback prompt, sandbox conversation reuse, engine toggle immediacy, and v1 zero regression
- [X] T020 [P] Run `bin/sync-custom-module-hooks --check` and `bin/sync-custom-module-hooks --audit` in `bin/sync-custom-module-hooks` to verify MANIFEST coverage for `config/features.yml`
- [X] T021 Run RuboCop on all new and modified files in `custom/app/`, `custom/spec/`, `config/features.yml`, and `bin/sync-custom-module-hooks` ensuring zero offenses and 150-char line limit compliance

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion (`qualificacao.md` available for boot checks) - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational (Phase 2) completion
- **User Story 2 (Phase 4)**: Depends on User Story 1 (Phase 3) completion (instruments the turn runner built in US1)
- **User Story 3 (Phase 5)**: Depends on User Story 1 & 2 completion (exercises qualification prompt extension and multi-turn state continuity)
- **Polish (Phase 6)**: Depends on all user stories (Phases 3, 4, and 5) being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after US1 - Adds instrumentation and metadata to `TurnRunner`
- **User Story 3 (P3)**: Can start after US1 - Extends `TurnRunner` with pending-fields prompt formatting and verifies multi-turn dialogue with `qualificacao` playbook

### Within Each User Story

- Tests MUST be written and FAIL before implementation (Constitution VI)
- Value objects and resolvers before runner implementation
- Runner service before dispatch point controllers/jobs
- Core turn execution before dynamic prompt formatting and continuity optimizations
- Story complete and verified before moving to next priority

### Parallel Opportunities

- In Phase 1: `T002` (manifest entry) and `T003` (playbook creation) can run in parallel with or after `T001`
- In Phase 2: `T004` (sandbox spec) unblocks `T005` (sandbox implementation)
- In Phase 3: `T006`, `T007`, and `T008` (all test writing) can run in parallel as they touch different test files (`turn_runner_spec.rb`, `playground_messages_controller_spec.rb`, `process_message_job_spec.rb`)
- In Phase 3: Once `T009` (`TurnRunner`) is implemented, `T010` (controller dispatch) and `T011` (job dispatch) can run in parallel
- In Phase 6: `T017` (playbook validation), `T018` (RSpec suite), `T019` (quickstart verification), and `T020` (sync hooks audit) can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch all three spec writing tasks for User Story 1 together:
Task: "Write unit and contract specs for Custom::ScoutV2::TurnRunner in custom/spec/services/custom/scout_v2/turn_runner_spec.rb"
Task: "Write request specs for playground messages controller scout_v2 dispatch in custom/spec/requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb"
Task: "Write job specs for process message job scout_v2 dispatch in custom/spec/jobs/custom/scout/process_message_job_spec.rb"

# Once TurnRunner core is implemented, dispatch point updates can run in parallel:
Task: "Add scout_v2 feature flag dispatch branch in custom/app/controllers/api/v1/accounts/scouts/playground_messages_controller.rb"
Task: "Add scout_v2 feature flag dispatch branch in custom/app/jobs/custom/scout/process_message_job.rb"
```

## Parallel Example: User Story 2 & 3 Tests

```bash
# Author specs for TurnRunner extensions:
Task: "Add observability specs to custom/spec/services/custom/scout_v2/turn_runner_spec.rb"
Task: "Write multi-turn qualification integration specs in custom/spec/services/custom/scout_v2/turn_runner_spec.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`T001`–`T003`)
2. Complete Phase 2: Foundational (`T004`–`T005`)
3. Complete Phase 3: User Story 1 (`T006`–`T011`)
4. **STOP and VALIDATE**: Test User Story 1 independently with doubled LLM client — confirm single LLM call, prompt assembly, tool restrictions, and state persistence
5. Verify engine toggle works without deployment (Scenario 4 in quickstart.md)

### Incremental Delivery

1. Setup + Foundational → Feature flag registered, playbook loaded, and sandbox conversation resolver ready
2. Add User Story 1 → Single-call turn runner and both dispatch points functional (MVP!)
3. Add User Story 2 → Full observability with Langfuse metadata (playbook, activation reason, unsatisfied flags)
4. Add User Story 3 → Qualification playbook with dynamic pending-fields formatting and multi-turn state continuity
5. Polish & Verification → Targeted test suite green, quickstart scenarios verified, sync hooks clean, RuboCop 100% clean

### Parallel Team Strategy

With multiple developers:
1. Team completes Setup + Foundational together (`T001`–`T005`)
2. Once Foundational is done:
   - Developer A: TurnRunner core implementation & unit specs (`T006`, `T009`)
   - Developer B: Playground messages controller request specs & dispatch branch (`T007`, `T010`)
   - Developer C: ProcessMessageJob job specs & dispatch branch (`T008`, `T011`)
3. Integrates cleanly through the single `Custom::ScoutV2::TurnRunner` contract

---

## Notes

- `[P]` tasks = different files, no dependencies on uncompleted work
- `[Story]` label maps task directly to `spec.md` user stories for complete traceability
- Every task includes an explicit file path to eliminate ambiguity
- All specs follow Constitution VII: real database records, zero mocking of internal AR models or services
- Exactly one top-level LLM call per turn attempt (SC-001)
- Never create `Message` rows for playground sandbox conversations (research.md D3)

---

## Phase 7: Convergence

- [X] T022 Add a test in `custom/spec/services/custom/scout_v2/turn_runner_spec.rb` invoking the active playbook's declared tool twice within a single turn (e.g., two `manage_opportunity` calls inside one stubbed `chat.ask`) and asserting `result[:tool_calls]` contains two distinct entries per spec.md Edge Case "the active playbook's declared tool is invoked more than once within the same turn" (missing)
