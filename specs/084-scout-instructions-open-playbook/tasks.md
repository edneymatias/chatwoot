---

description: "Task list for Scout V2 Typed Instructions, Playbook Index, and Mid-Turn Playbook Activation"
---

# Tasks: Scout V2 Typed Instructions, Playbook Index, and Mid-Turn Playbook Activation

**Input**: Design documents from `/specs/084-scout-instructions-open-playbook/` (`plan.md`, `spec.md`, `data-model.md`, `research.md`, `contracts/`, `quickstart.md`)

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `data-model.md`, `research.md`, `contracts/`

**Tests**: Test-driven development is mandatory per Constitution Principles VI–VIII. All unit, contract, and integration tests MUST be written and observed failing before implementation code is written.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story, strictly following the checklist format `- [ ] [TaskID] [P?] [Story?] Description with file path`.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Database schema updates for Scout communication style configuration

- [X] T001 Create migration in db/migrate/21260925000000_add_communication_style_to_ichatr_scouts.rb adding tone, response_length, and greeting columns to ichatr_scouts
- [X] T002 Run `rails db:migrate` for test and development environments (regenerates db/schema.rb)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core model extensions and shared infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 [P] Add model unit tests for tone and response_length enums and defaults in custom/spec/models/scout_spec.rb
- [X] T004 [P] Define tone and response_length Rails enums with defaults and ArgumentError validation in custom/app/models/scout.rb
- [X] T005 [P] Add unit tests for `Custom::ScoutV2::Tools::Registry.build(tool_names, scout:, conversation:)` tool instantiation in custom/spec/services/custom/scout_v2/tools/registry_spec.rb
- [X] T006 [P] Implement Custom::ScoutV2::Tools::Registry.build(tool_names, scout:, conversation:) to instantiate playbook tools in custom/app/services/custom/scout_v2/tools/registry.rb
- [X] T007 [P] Add unit tests for record_trigger_activation! in custom/spec/models/scout_conversation_state_spec.rb
- [X] T008 [P] Implement record_trigger_activation! on ScoutConversationState in custom/app/models/scout_conversation_state.rb

**Checkpoint**: Foundation ready - Scout enums, tool registry, and conversation state trigger activation helper available for user stories.

---

## Phase 3: User Story 1 - Typed Instructions Block (Priority: P1) 🎯 MVP

**Goal**: Deliver a typed, four-section Instructions block (`[Identity]`, `[Communication]`, `[Memory]`, `[Safety]`) driven by Scout model configuration without situational guidance or KB consultation timing rules.

**Independent Test**: Configure a scout's communication style and greeting, call `Custom::ScoutV2::Instructions::Builder.call(scout: scout)` in isolation, and confirm it outputs exactly four bracketed sections with configured values reflected, zero situational v1 guidance, and an untimed KB existence statement.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T009 [P] [US1] Create unit tests for CommunicationBuilder asserting tone and response length directives and greeting in custom/spec/services/custom/scout_v2/instructions/communication_builder_spec.rb
- [X] T010 [P] [US1] Create unit tests for Instructions::Builder asserting 4 typed sections and removal of v1 situational guidance in custom/spec/services/custom/scout_v2/instructions/builder_spec.rb

### Implementation for User Story 1

- [X] T011 [P] [US1] Implement IdentityBuilder with assistant role and topic scope in custom/app/services/custom/scout_v2/instructions/identity_builder.rb
- [X] T012 [P] [US1] Implement CommunicationBuilder with enum-to-sentence mapping and greeting in custom/app/services/custom/scout_v2/instructions/communication_builder.rb
- [X] T013 [P] [US1] Implement MemoryBuilder with data-retention policy in custom/app/services/custom/scout_v2/instructions/memory_builder.rb
- [X] T014 [P] [US1] Implement SafetyBuilder with non-negotiable safety rules and untimed knowledge base declaration in custom/app/services/custom/scout_v2/instructions/safety_builder.rb
- [X] T015 [US1] Implement Instructions::Builder composing the four typed sections in fixed order in custom/app/services/custom/scout_v2/instructions/builder.rb

**Checkpoint**: At this point, User Story 1 is fully functional and testable independently. Composed instructions block contains exactly 4 sections and responds to scout configuration changes without prose editing.

---

## Phase 4: User Story 2 - Playbook Index Block (Priority: P2)

**Goal**: Deliver an always-on one-line-per-playbook index block derived dynamically from the loaded catalog, and wire prompt block assembly into `TurnRunner` while removing `FALLBACK_INSTRUCTIONS`.

**Independent Test**: Load a catalog of playbooks, invoke `Custom::ScoutV2::Playbook::IndexBuilder.call(catalog)`, and confirm it outputs `[Playbook Index]` with exactly one line per playbook (`- <name>: <trigger>`), verify an empty catalog outputs the header and fallback line, and verify `TurnRunner` composes Block 1, Block 2, and Block 3 in order without `FALLBACK_INSTRUCTIONS`.

### Tests for User Story 2 ⚠️

- [X] T016 [P] [US2] Create unit tests for Playbook::IndexBuilder verifying catalog line format and empty state in custom/spec/services/custom/scout_v2/playbook/index_builder_spec.rb
- [X] T017 [P] [US2] Update TurnRunner specs to assert prompt assembly of Instructions and Playbook Index blocks and removal of FALLBACK_INSTRUCTIONS in custom/spec/services/custom/scout_v2/turn_runner_spec.rb

### Implementation for User Story 2

- [X] T018 [US2] Implement Custom::ScoutV2::Playbook::IndexBuilder formatting catalog entries and empty fallback line in custom/app/services/custom/scout_v2/playbook/index_builder.rb
- [X] T019 [US2] Update TurnRunner#build_instructions to assemble Block 1, Block 2, and Block 3 in custom/app/services/custom/scout_v2/turn_runner.rb

**Checkpoint**: User Stories 1 and 2 are functional together. The assistant prompt contains both the typed instructions block and the catalog index on every turn.

---

## Phase 5: User Story 3 - Mid-Turn Playbook Activation (Priority: P3)

**Goal**: Expose the `open_playbook` tool when no playbook is forced by state, allowing the model to open a catalog playbook by name mid-turn, inject its declared tools into the live chat loop, persist `activation_reason: :trigger`, and handle unknown playbook names gracefully without failing the turn.

**Independent Test**: Execute `TurnRunner#perform` on a conversation with no state-forced playbook, verify `open_playbook` tool is registered, verify calling `open_playbook` injects declared tools into the live chat, returns the playbook markdown body as tool result, persists `activation_reason: 'trigger'`, and verify `open_playbook` is absent when a playbook is forced by state.

### Tests for User Story 3 ⚠️

- [X] T020 [P] [US3] Create unit tests for Custom::ScoutV2::Tools::OpenPlaybook covering execution, tool injection, trigger activation, and unknown name error handling in custom/spec/services/custom/scout_v2/tools/open_playbook_spec.rb
- [X] T021 [P] [US3] Add integration specs in custom/spec/services/custom/scout_v2/turn_runner_spec.rb for open_playbook gating, same-turn mid-turn tool availability, and trigger activation metadata

### Implementation for User Story 3

- [X] T022 [US3] Implement Custom::ScoutV2::Tools::OpenPlaybook tool class with live chat injection and trigger activation in custom/app/services/custom/scout_v2/tools/open_playbook.rb
- [X] T023 [US3] Refactor TurnRunner tool assembly to register OpenPlaybook when no playbook is forced and resolve tools via Registry in custom/app/services/custom/scout_v2/turn_runner.rb
- [X] T024 [US3] Update TurnRunner#metadata_for to read persisted activation_reason from ScoutConversationState in custom/app/services/custom/scout_v2/turn_runner.rb

**Checkpoint**: All three user stories are complete. The assistant can view the playbook index and activate a playbook mid-turn with immediate same-turn tool availability and trigger telemetry.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Verification, regression prevention, code style, and module sync checks across all touched files

- [X] T025 [P] Run regression tests for v1 execution path in custom/spec/services/custom/scout/system_prompts_service_spec.rb and custom/spec/services/custom/scout/agent_runner_spec.rb
- [X] T026 [P] Run RuboCop checks and auto-formatting across all modified and created files against .rubocop.yml
- [X] T027 Run sync-custom-module-hooks audit to ensure zero gaps in bin/sync-custom-module-hooks
- [X] T028 Validate all test scenarios and targeted spec suite per specs/084-scout-instructions-open-playbook/quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - executes database migration
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational completion (`Scout#tone`, `Scout#response_length`, `Scout#greeting`)
- **User Story 2 (Phase 4)**: Depends on US1 completion (adds index block alongside Instructions block in `TurnRunner`, removes `FALLBACK_INSTRUCTIONS`)
- **User Story 3 (Phase 5)**: Depends on US2 completion (`open_playbook` tool references catalog index and integrates with `TurnRunner` tool loop)
- **Polish (Phase 6)**: Depends on completion of all user stories

### User Story Dependencies

- **User Story 1 (P1)**: Can start immediately after Foundational (Phase 2)
- **User Story 2 (P2)**: Depends on US1 instructions block existing to compose prompt blocks in `TurnRunner`
- **User Story 3 (P3)**: Depends on US2 index existing to give the model names to open, and depends on `TurnRunner` prompt block assembly

### Within Each User Story

- Tests MUST be written first and observed failing before implementation begins (TDD, Constitution VI & VIII)
- Builder leaf classes (`IdentityBuilder`, `CommunicationBuilder`, `MemoryBuilder`, `SafetyBuilder`) before orchestrator (`Instructions::Builder`)
- Tool classes (`OpenPlaybook`) before runner integration (`TurnRunner#build_tools`)
- Core logic before telemetry updates (`TurnRunner#metadata_for`)

### Parallel Opportunities

- Within Phase 2: T003, T004, T005, T006, T007, T008 can run across distinct files
- Within Phase 3 (US1):
  - T009 and T010 tests can be written in parallel
  - T011, T012, T013, T014 section builders can be implemented in parallel before T015
- Within Phase 4 (US2): T016 and T017 test specifications can be written in parallel
- Within Phase 5 (US3): T020 and T021 tests can be written in parallel
- Within Phase 6: T025 and T026 can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch test creation for User Story 1 together:
Task: "T009 [P] [US1] Create unit tests for CommunicationBuilder asserting tone and response length directives and greeting in custom/spec/services/custom/scout_v2/instructions/communication_builder_spec.rb"
Task: "T010 [P] [US1] Create unit tests for Instructions::Builder asserting 4 typed sections and removal of v1 situational guidance in custom/spec/services/custom/scout_v2/instructions/builder_spec.rb"

# Launch section builders for User Story 1 together:
Task: "T011 [P] [US1] Implement IdentityBuilder with assistant role and topic scope in custom/app/services/custom/scout_v2/instructions/identity_builder.rb"
Task: "T012 [P] [US1] Implement CommunicationBuilder with enum-to-sentence mapping and greeting in custom/app/services/custom/scout_v2/instructions/communication_builder.rb"
Task: "T013 [P] [US1] Implement MemoryBuilder with data-retention policy in custom/app/services/custom/scout_v2/instructions/memory_builder.rb"
Task: "T014 [P] [US1] Implement SafetyBuilder with non-negotiable safety rules and untimed knowledge base declaration in custom/app/services/custom/scout_v2/instructions/safety_builder.rb"
```

---

## Parallel Example: User Story 2

```bash
# Launch test creation for User Story 2 together:
Task: "T016 [P] [US2] Create unit tests for Playbook::IndexBuilder verifying catalog line format and empty state in custom/spec/services/custom/scout_v2/playbook/index_builder_spec.rb"
Task: "T017 [P] [US2] Update TurnRunner specs to assert prompt assembly of Instructions and Playbook Index blocks and removal of FALLBACK_INSTRUCTIONS in custom/spec/services/custom/scout_v2/turn_runner_spec.rb"
```

---

## Parallel Example: User Story 3

```bash
# Launch test creation for User Story 3 together:
Task: "T020 [P] [US3] Create unit tests for Custom::ScoutV2::Tools::OpenPlaybook covering execution, tool injection, trigger activation, and unknown name error handling in custom/spec/services/custom/scout_v2/tools/open_playbook_spec.rb"
Task: "T021 [P] [US3] Add integration specs in custom/spec/services/custom/scout_v2/turn_runner_spec.rb for open_playbook gating, same-turn mid-turn tool availability, and trigger activation metadata"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (Migration)
2. Complete Phase 2: Foundational (Scout enums, Registry, ScoutConversationState helper)
3. Complete Phase 3: User Story 1 (Typed Instructions Block)
4. **STOP and VALIDATE**: Verify `Custom::ScoutV2::Instructions::Builder` in isolation with `custom/spec/services/custom/scout_v2/instructions/`

### Incremental Delivery

1. Setup + Foundational → Database schema and models ready
2. Add User Story 1 → Typed instructions block testable in isolation (MVP!)
3. Add User Story 2 → Playbook index builder ready; prompt block assembly wired into `TurnRunner`, `FALLBACK_INSTRUCTIONS` removed
4. Add User Story 3 → Mid-turn activation tool `open_playbook` registered and operational during turn execution
5. Polish & Verification → Targeted specs, RuboCop clean, v1 regression-free

### Parallel Team Strategy

With multiple developers:
1. Complete Setup and Foundational together
2. Once Foundational is done:
   - Developer A implements US1 section builders
   - Developer B implements US2 index builder
   - Developer C implements US3 `OpenPlaybook` tool
3. Integrate into `TurnRunner` sequentially (US2 prompt assembly → US3 tool registration and metadata)

---

## Notes

- `[P]` tasks = different files, no dependencies
- `[Story]` label maps task to specific user story for traceability
- Every acceptance criterion in `spec.md` is covered by at least one test task
- Test tasks precede implementation tasks in each user story phase per TDD rules
- No v1 files under `custom/app/services/custom/scout/` are modified (FR-017)

---

## Phase 7: Convergence

- [X] T029 CRITICAL: Replace the `instance_double(Custom::ScoutV2::Playbook, ...)` fixtures with real `Custom::ScoutV2::Playbook` instances in custom/spec/services/custom/scout_v2/playbook/index_builder_spec.rb per Constitution VII (contradicts)
- [X] T030 Add a TurnRunner integration spec in custom/spec/services/custom/scout_v2/turn_runner_spec.rb that executes an `open_playbook` call during the turn and asserts the opened playbook's declared tools are registered on the same live chat instance driving `chat.ask`, that the body is returned as the tool result, and that `ScoutConversationState#activation_reason` is `trigger` per FR-014, US3/AC4, SC-004 (partial)
- [X] T031 Assert the state-forced-playbook prompt contains the `[Identity]`/`[Communication]`/`[Memory]`/`[Safety]` sections followed by `[Playbook Index]` followed by the playbook body, in that order, in the forced context of custom/spec/services/custom/scout_v2/turn_runner_spec.rb per FR-018, SC-007 (partial)
- [X] T032 Remove the unreachable non-`Catalog` coercion branch (`@catalog.respond_to?(:playbooks) ? ... : Array(@catalog)`) from custom/app/services/custom/scout_v2/playbook/index_builder.rb per contracts/turn_prompt_blocks.md Block 2 (unrequested)
- [X] T033 Remove the unreachable `|| TONE_DIRECTIVES['friendly']` and `|| RESPONSE_LENGTH_DIRECTIVES['concise']` fallbacks from custom/app/services/custom/scout_v2/instructions/communication_builder.rb per FR-003 and Constitution II (unrequested)

## Phase 8: Convergence

- [X] T034 CRITICAL: Rewrite the tone/response_length examples in custom/spec/services/custom/scout_v2/instructions/communication_builder_spec.rb to assert each enum value yields its exact expected directive sentence (literal strings, not the builder's constants) and that no raw enum key (`friendly`, `matter_of_fact`, `humorous`, `concise`, `thorough`, …) appears in the output, so a raw-key or swapped-mapping mutant fails, per Constitution VII and FR-003 (contradicts)
- [X] T035 CRITICAL: Replace the `allow(runner).to receive(:instrument_agent_session).and_wrap_original` spy on the class under test in custom/spec/services/custom/scout_v2/turn_runner_spec.rb ("populates turn metadata with trigger activation_reason") with an assertion on the `activation_reason` attribute actually emitted at the OpenTelemetry tracing boundary, per Constitution VII and FR-015 (contradicts)
- [X] T036 CRITICAL: Delete the cosmetic `be_present`-only example "is never blank or nil" from custom/spec/services/custom/scout_v2/playbook/index_builder_spec.rb (the preceding empty-catalog example already asserts the exact header and line), per Constitution VII (contradicts)
- [X] T037 Normalize each playbook trigger to a single line (e.g. `pb.trigger.squish`) in custom/app/services/custom/scout_v2/playbook/index_builder.rb so folded-YAML (`trigger: >`) triggers with a trailing newline do not insert blank lines between index entries, and add a failing-first example in custom/spec/services/custom/scout_v2/playbook/index_builder_spec.rb with two playbooks whose triggers end in `"\n"` asserting exactly header + one line per playbook, per FR-009, FR-010, SC-003 (partial)
- [X] T038 Make Custom::ScoutV2::Tools::Registry.build fail loudly on an unregistered tool name (`TOOL_CLASSES.fetch`) and drop the unreachable `Array(nil)` coercion in custom/app/services/custom/scout_v2/tools/registry.rb, replacing the "ignores unknown tool names" and nil-input examples in custom/spec/services/custom/scout_v2/tools/registry_spec.rb, per contracts/open_playbook_tool.md (every declared tool is resolved and added) (contradicts)
- [X] T039 Remove the unreachable `@scout.name.presence || 'Scout'`, `@scout.account&.name`, and `account_name.present?` fallbacks from custom/app/services/custom/scout_v2/instructions/identity_builder.rb (Scout validates name and account; Account validates name), per Constitution II and contracts/turn_prompt_blocks.md Block 1 (unrequested)
- [X] T040 Remove the unreachable `|| 'state'` fallback from TurnRunner#metadata_for in custom/app/services/custom/scout_v2/turn_runner.rb (a present `decision.playbook` always has a persisted `activation_reason`), per Constitution II and research.md §3 (unrequested)
- [X] T041 Make `tool_wrapper:` a required keyword and remove the `@tool_wrapper ? … : tool` branch and `options[:playground] || false` fallback in custom/app/services/custom/scout_v2/tools/open_playbook.rb (TurnRunner, the only caller, always passes both), per Constitution II and research.md §7 (unrequested)

## Phase 9: Convergence

- [X] T042 CRITICAL: Remove the `# rubocop:disable/enable Metrics/ParameterLists` pair from custom/app/services/custom/scout_v2/tools/open_playbook.rb by dropping the `playground:` keyword from `OpenPlaybook#initialize` (its only caller, `TurnRunner#setup_chat`, always passes `false`, which is `BaseTool`'s default) and calling `super(scout, conversation)`; update the `OpenPlaybook.new` call in custom/app/services/custom/scout_v2/turn_runner.rb and the subject in custom/spec/services/custom/scout_v2/tools/open_playbook_spec.rb, per Constitution III and AGENTS.md Code Style (contradicts)
- [X] T043 CRITICAL: Add mutation-resistant examples to custom/spec/services/custom/scout_v2/instructions/builder_spec.rb asserting the `[Identity]` section contains the scout's name, the account's name, and the commercial-scope restriction; the `[Memory]` section states the conversation-scoped retention policy; and the `[Safety]` section carries each of the four non-negotiable rules (no fabrication, no unguaranteed promises, detect-and-reply in the customer's language, commercial scope) — so deleting any one of those statements fails a test, per FR-002, FR-004, FR-005 and Constitution VI/VII (partial)
- [X] T044 CRITICAL: Add a TurnRunner integration example in custom/spec/services/custom/scout_v2/turn_runner_spec.rb (no-playbook context) where `chat.ask` invokes the registered `open_playbook` tool with an unknown name, asserting `perform` still returns the reply, `result[:tool_calls]` records the `open_playbook` call with an `{ error: ... }` result, no `manage_opportunity` tool was registered, and `ScoutConversationState` has no `active_playbook`/`activation_reason`, per US3/AC6, SC-006 and Constitution VI (partial)

## Phase 10: Convergence

- [X] T045 CRITICAL: Replace the three never-present markers (`DIRETRIZES DE ESTÁGIO E FUNIL`, `DIRETRIZES FUNDAMENTAIS DE COMPORTAMENTO`, `Nunca diga frases como "não tenho acesso"`) in the "excludes v1 guardrails and funnel guidelines" example of custom/spec/services/custom/scout_v2/turn_runner_spec.rb with markers that actually exist in custom/app/services/custom/scout/system_prompts_service.rb (`[Diretrizes de Segurança e Resposta]`, `[Formato de Resposta Obrigatório]`, `Confirmação de ação`, `Intenção Comercial`, `Fallback para humano`, `Reconhecimento de intenção fora de prospecção`), assert the same exclusion in the no-playbook context, and drop the dead `DIRETRIZES DE ESTÁGIO E FUNIL` entry from custom/spec/services/custom/scout_v2/instructions/builder_spec.rb — so injecting v1 guidance into `TurnRunner#build_instructions` fails a test, per FR-008, SC-001 and Constitution VII (contradicts)
- [X] T046 CRITICAL: Add a TurnRunner example in custom/spec/services/custom/scout_v2/turn_runner_spec.rb (no-playbook context) asserting the composed instructions contain `- <name>: <trigger.squish>` for every playbook returned by `Custom::ScoutV2::Playbook::Loader.load_all`, under `[Playbook Index]`, so passing an empty/other catalog to `IndexBuilder` from `TurnRunner#build_instructions` fails, per FR-009, FR-010, US2/AC1, SC-003 and Constitution VI/VII (partial)
- [X] T047 CRITICAL: Add a whitespace-only greeting case (e.g. `scout.greeting = '   '`) to custom/spec/services/custom/scout_v2/instructions/communication_builder_spec.rb asserting the output contains the exact generic directive `Cumprimente o cliente de forma educada e adequada ao início da conversa.` and not `utilizando a seguinte saudação`, so a `present?` → `nil?` mutant fails, per FR-003, contracts/turn_prompt_blocks.md Block 1 and Constitution VII (partial)

## Phase 11: Convergence

- [X] T048 CRITICAL: Add a TurnRunner integration example in custom/spec/services/custom/scout_v2/turn_runner_spec.rb (no-playbook context) where `chat.ask` executes the registered `open_playbook` tool with `qualificacao` and then executes the `manage_opportunity` tool it injected mid-turn, asserting `result[:tool_calls]` contains that `manage_opportunity` call with its exact arguments, `simulated: false`, and a result (so a `tool_wrapper: ->(tool) { tool }` mutant in `TurnRunner#setup_chat` fails), per research.md §7 (tool-call recording parity for trigger-injected tools), FR-014, SC-004 and Constitution VII (partial)

## Phase 12: Convergence

- [X] T049 CRITICAL: Add a TurnRunner example in custom/spec/services/custom/scout_v2/turn_runner_spec.rb that updates the scout (`tone: :humorous`, `response_length: :thorough`, `greeting: 'E aí, tudo certo?'`), runs `perform`, and asserts the composed instructions passed to `with_instructions` contain the literal humorous/thorough directive sentences and the quoted greeting and do not contain the default friendly/concise sentences — so a `TurnRunner#build_instructions` that composes the Instructions block from anything other than the turn's own scout (verified mutant: `Scout.new(account:, name:)` survives all 20 current examples) fails, per US1/AC2, FR-007, SC-002 and Constitution VI/VII (partial)
- [X] T050 CRITICAL: Add TurnRunner examples in custom/spec/services/custom/scout_v2/turn_runner_spec.rb (both the state-forced and no-playbook contexts) asserting the full ordered list of bracketed block headers in the composed instructions (`instructions.scan(/^\[([^\]]+)\]$/)`) is exactly `Identity, Communication, Memory, Safety, Playbook Index` — so injecting any extra section/guidance between `[Safety]` and `[Playbook Index]` (verified mutant: a `[Guidelines]` block telling the model to consult the knowledge base "sempre que for útil" survives all 20 current examples) fails, per FR-001, FR-006, FR-018, US1/AC1, SC-001, SC-007 and Constitution VI/VII (partial)
- [X] T051 Add examples to custom/spec/models/scout_spec.rb asserting `Scout.create!` with `tone: nil` and, separately, with `response_length: nil` raises `ActiveRecord::NotNullViolation` (compare `error.class.name`), pinning the non-null half of FR-003 that no current spec exercises, per FR-003 and Constitution VI (partial)
- [X] T052 Remove the unneeded `.to_s` coercions — `@scout.tone.to_s`/`@scout.response_length.to_s` in custom/app/services/custom/scout_v2/instructions/communication_builder.rb (Rails enum readers already return String), `name.to_s` in custom/app/services/custom/scout_v2/tools/open_playbook.rb (the tool's `name` param is declared `type: :string`), and `name.to_s` in custom/app/services/custom/scout_v2/tools/registry.rb (playbook `tools:` entries are YAML strings) — per Constitution II and AGENTS.md "do not add compatibility coercions" (unrequested)

## Phase 13: Convergence

- [X] T053 CRITICAL: Add a TurnRunner example in custom/spec/services/custom/scout_v2/turn_runner_spec.rb (no-playbook context) that points `SCOUT_V2_PLAYBOOKS_DIR` via `with_modified_env` at a tmp dir holding a copy of `custom/playbooks/qualificacao.md`, runs `perform`, then writes a second valid playbook file (e.g. `duvida_comercial.md` with its own `name`/`trigger`/`priority`) into that dir and runs `perform` again on a new runner — asserting the second turn's `[Playbook Index]` contains exactly one line per file, including `- duvida_comercial: <trigger>`, which the first turn's did not — so a `TurnRunner` that caches or hardcodes the catalog instead of loading it at composition time fails (today every TurnRunner example loads only the one shipped playbook, so a class-level memoized catalog survives all 111 targeted examples), per US2/AC2, FR-010, SC-003 and Constitution VI (partial)

## Phase 14: Code review follow-ups

- [X] T054 Reject unregistered playbook `tools:` names at boot in custom/app/services/custom/scout_v2/playbook/validator.rb (`validate_tools`), so `Registry.fetch` can never raise mid-turn
- [X] T055 Scope the greeting directive in custom/app/services/custom/scout_v2/instructions/communication_builder.rb to the first reply only and `squish` the configured greeting so it cannot open a fake bracketed section (FR-001)
- [X] T056 Move Memory/Safety prose into `Instructions::Builder::MEMORY_SECTION`/`SAFETY_SECTION` (delete memory_builder.rb/safety_builder.rb) and drop the refusal sentence duplicated between `[Identity]` and `[Safety]`
- [X] T057 Move pending-fields formatting into `Custom::ScoutV2::Playbook::PendingFieldsFormatter`, split tool assembly into `TurnRunner#build_tools`, and read `ScoutConversationState` once per turn in `TurnRunner`
- [X] T058 Delete tests that pin framework behaviour or never-present v1 wording (enum `ArgumentError`/assignment, greeting column save, `update!` leaving other columns alone, v1-phrase absence) and reference directive constants instead of duplicated literals in turn_runner_spec.rb
- [X] T059 Record in spec.md Assumptions that a trigger-opened playbook stays active until a strictly higher-priority `when_state` playbook interrupts it, accepted for this phase because `scout_v2` stays development-only until after Brief 05
