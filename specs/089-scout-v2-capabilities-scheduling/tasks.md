---
description: "Task list for Scout V2 Capabilities and End-to-End Scheduling implementation"
---

# Tasks: Scout V2 Capabilities and End-to-End Scheduling

**Input**: Design documents from `/specs/089-scout-v2-capabilities-scheduling/` (`spec.md`, `plan.md`, `data-model.md`, `research.md`, `quickstart.md`, `contracts/`)

**Prerequisites**: `plan.md` (required), `spec.md` (required for user stories), `research.md`, `data-model.md`, `contracts/turn_assembly.md`, `contracts/erp_provider.md`, `contracts/capabilities.md`

**Tests**: Test-Driven Development (TDD) is NON-NEGOTIABLE per project constitution (Principles VI, VII, VIII). Test tasks are included for every functional slice, exercising claims through their specified entry points (direct calls for decisions/predicates, WebMock effect checks for capability calls, and request specs for end-to-end turn wiring).

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story in priority order (P1 → P2 → P3). Everything both US1 and US2 need (state column, contract value objects, hook settings schema, ERP client/adapter, registry, snapshot wiring) lives in Phase 2.

## Format: `- [ ] [TaskID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (`[US1]`, `[US2]`, `[US3]`). Omitted for Setup, Foundational, and Polish phases.
- Exact file paths included in all descriptions
- Verbatim constraints from `data-model.md` and contracts included in task descriptions

## Test-first rule (applies to every phase)

Within a phase, all test tasks come before the implementation tasks of the same slice. Run the new specs with the targeted command from `quickstart.md` §2 and **observe them fail for the right reason** (missing column / constant / tool / behavior) before writing the code that makes them pass. `[P]` is used only between tasks of the same kind (tests with tests, implementation with implementation) that touch different files — never between a test and its own implementation.

**Spec → code names**: "slot identifier" → `slot_id`; "configuration identifiers" → the seven hook settings `id_empresa`, `id_usuario`, `id_convenio`, `nr_convenio`, `id_origem_pessoa`, `id_agenda`, `id_servico` (the hook also holds `token`, the credential, which is never an identifier and never recorded).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: External fixtures capture, database schema addition, and migration baseline

- [X] T001 Capture ERP Younus sample response fixtures in `custom/spec/fixtures/erp/younus/` (`find_person_found.json`, `find_person_none.json`, `find_person_multiple.json`, `free_slots.json`, `free_slots_empty.json`, `create_person.json`, `create_appointment.json`, and `error_declined.json` — a `sucesso: false` write) per `quickstart.md` §0.3: reads from any account/company, writes only against the test company/agenda. If the ERP host is unreachable from the `rails` container (it timed out at 85 s during planning), capture from the vendor's workflow/console and record the source inside each fixture file. If neither source is reachable, STOP and ask the user for the bodies — never hand-author vendor shapes. **Anonymize every fixture before committing**: replace personal data (names, phones, documents) keeping keys and envelope
- [X] T002 Create database migration `db/migrate/21260930000000_add_capability_state_to_ichatr_scout_conversation_states.rb` adding `capability_state` with constraint `jsonb, default: {}, null: false` (reversible)
- [X] T003 Apply the migration in the container (`docker compose exec rails bundle exec rails db:migrate` and `docker compose exec rails env RAILS_ENV=test bundle exec rails db:migrate`) on a clean `chatwoot_dev`/`chatwoot_test`; inspect the `db/schema.rb` diff and confirm it contains only `capability_state` and no foreign objects (n8n triggers/functions — AGENTS.md); then run `spec/config/schema_spec.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: State storage, contract value objects, hook settings schema, ERP client/adapter, registry resolution and routing snapshot wiring (including the contract-only `Scheduling` and `CustomerRegistry` classes, T024/T025) that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Tests for Foundational ⚠️

- [X] T004 [P] Unit tests for `ScoutConversationState` capability methods (`remember_customer!`, `remember_slots!` — merges, never replaces —, `remember_booking!`) in `custom/spec/models/scout_conversation_state_spec.rb`
- [X] T005 [P] Unit tests for `Operation` value object (`problems_for`, `deviations_for`, `params_schema`; a syntactically valid past date passes `problems_for` — types, not business rules) in `custom/spec/services/custom/scout_v2/capabilities/operation_spec.rb`
- [X] T006 [P] Unit tests for `CallRecord` serialization and credential isolation (token never present in `#to_span_json`) in `custom/spec/services/custom/scout_v2/capabilities/call_record_spec.rb`
- [X] T007 [P] Unit tests for `Base` DSL and catalog parity with `Catalog::KNOWN_NAMES` in `custom/spec/services/custom/scout_v2/capabilities/base_spec.rb`
- [X] T008 [P] Contract specs for the `younus` app and hook settings (FR-010, US2-AS10): `visible_properties` (`id_empresa`, `token`, `id_usuario`, `id_convenio`, `nr_convenio`, `id_origem_pessoa`, `id_agenda`, `id_servico`) in `custom/spec/models/custom/integrations/app_spec.rb`; in `custom/spec/models/custom/integrations/hook_spec.rb`, a hook with only `token` + `id_empresa` stays valid, the six new optional keys are accepted, a non-numeric value on the five id keys is rejected (a cleared `''` stays valid), and an unknown key is still rejected
- [X] T009 [P] Unit specs for `Erp::Younus::Client` (`find_person`, `create_person`, `free_slots`, `create_appointment`): every identifier and the token come from the `settings` kwarg (distinctive values asserted with WebMock `have_requested … with`), numeric ids sent as integers, `nrConvenio` as string, `Erp::ApiError`/`Erp::AuthenticationError` mapping, no retry, in `custom/spec/services/erp/younus/client_spec.rb` (uses the T001 fixtures)
- [X] T010 [P] Unit specs for `Erp::Younus::Adapter` in `custom/spec/services/erp/younus/adapter_spec.rb`: provider methods normalize vendor bodies to contract shapes; several people → `status: :ambiguous`, none → `:not_found`; vendor omissions become `nil` and nothing raises on unexpected shapes (FR-004, FR-016)
- [X] T011 [P] Unit tests for `Registry.resolve` and `Registry.satisfied_names` (enabled hook, `category: erp`, `hook.feature_allowed?`, `PROVIDERS`, non-blank required settings, and digits-only `id_*` values — a non-numeric `id_empresa` or `id_agenda` resolves as unsatisfied, never raises; the two capabilities evaluated independently; never raises for no hook / disabled hook / flag off / unsupported vendor / blank or malformed key; `Adapter.capability_settings` key lists exactly as `contracts/erp_provider.md` §1) in `custom/spec/services/custom/scout_v2/capabilities/registry_spec.rb`
- [X] T012 [P] Unit tests for `RoutingSnapshot::Builder` satisfied-capabilities resolution (lists exactly the satisfied names; `[]` for accounts with no integration) in `custom/spec/services/custom/scout_v2/routing_snapshot/builder_spec.rb`

### Implementation for Foundational

- [X] T013 [P] Implement `remember_customer!(id:, name:)`, `remember_slots!(slots)`, and `remember_booking!(appointment_id:, starts_at:)` updating `capability_state` in `custom/app/models/scout_conversation_state.rb`
- [X] T014 [P] Implement `Operation` value object with `Input = Data.define(:name, :type, :required)` (`type` ∈ `'string' | 'date'`) and `Output = Data.define(:required, :shape)` (`shape` ∈ `:record | :list`), with `#problems_for(inputs)`, `#deviations_for(data)`, and `#params_schema` in `custom/app/services/custom/scout_v2/capabilities/operation.rb`
- [X] T015 [P] Implement `CallRecord` (`Data.define(:capability, :operation, :inputs, :injected, :outcome, :error, :deviations)`) with `#to_span_json`; `injected` restricted to the seven identifier keys + `phone`, so the token cannot be present by construction, in `custom/app/services/custom/scout_v2/capabilities/call_record.rb`
- [X] T016 Implement `Base` DSL (`capability_name`, `operation`, `operations`) in `custom/app/services/custom/scout_v2/capabilities/base.rb` (after T014)
- [X] T017 [P] Extend the `younus` app in `config/integration/apps.yml` with optional settings `id_usuario`, `id_convenio`, `nr_convenio`, `id_origem_pessoa`, `id_agenda`, `id_servico` (`pattern: '^\d*$'` on the five id keys; `nr_convenio` a plain string; `additionalProperties: false`; `required` stays `token` + `id_empresa`), matching form items, and `visible_properties`. Form labels follow the existing raw English labels of this block (`API Token`, `Company ID`) — a justified deviation from the pt-BR rule recorded in plan.md Complexity Tracking; no frontend or locale change; app `name`/`description` remain localized in `en.yml`/`pt_BR.yml` and are untouched
- [X] T018 Update the MANIFEST `insert:` for the `younus` block in `bin/sync-custom-module-hooks` byte-for-byte to match T017, then run `docker compose exec rails ruby bin/sync-custom-module-hooks --check` (after T017)
- [X] T019 [P] Implement `find_person`, `create_person`, `free_slots`, and `create_appointment` in `custom/app/services/erp/younus/client.rb` with a `settings` kwarg injecting identifiers and the token in the header (`Integer(value)` on numeric ids; safe because the registry only resolves hooks whose `id_*` values are digits — T021)
- [X] T020a Implement `Adapter.capability_settings` (`contracts/erp_provider.md` §1) in `custom/app/services/erp/younus/adapter.rb`; static, needs no vendor bodies, so not blocked by T001 (asserted in T011)
- [X] T020 Implement provider methods `find_person(phone:)`, `create_person(name:, phone:)`, `list_free_slots(date:)`, `create_appointment(person_id:, person_name:, starts_at:, notes:)` normalizing vendor shapes in `custom/app/services/erp/younus/adapter.rb` (after T019)
- [X] T024 [P] Define the `Scheduling` capability contract only (`list_slots`: `date` required, `service` optional and informational — its model-facing description says it is recorded but never sent; `book`: `slot_id` required, `notes` optional) in `custom/app/services/custom/scout_v2/capabilities/scheduling.rb`. Numbered out of sequence: it executes in Phase 2 after T016 because `Registry` (T021) and the `Base` parity spec (T007) need the class. `list_slots` is implemented in T026a, `book` in T032
- [X] T025 [P] Define the `CustomerRegistry` capability contract only (`find_by_phone`: no inputs; `create`: `name` required) in `custom/app/services/custom/scout_v2/capabilities/customer_registry.rb`. Numbered out of sequence: executes in Phase 2 after T016 (same reason as T024). The operation methods are implemented in T031
- [X] T021 Implement `Registry` with `Resolution = Data.define(:capability, :provider)`, `PROVIDERS = { 'younus' => Erp::Younus::Adapter }.freeze`, `#resolve(name, account:)`, and `#satisfied_names(account:)` in `custom/app/services/custom/scout_v2/capabilities/registry.rb`; a capability is satisfied only when every listed key is non-blank and every `id_*` key (`id_empresa` included) matches `/\A\d+\z/` (`contracts/erp_provider.md` §1) (after T016, T020a, T024, T025)
- [X] T022 Wire `satisfied_capabilities: Custom::ScoutV2::Capabilities::Registry.satisfied_names(account: @conversation.account)` in `custom/app/services/custom/scout_v2/routing_snapshot/builder.rb` (after T021)

**Checkpoint**: Foundation ready — state storage, contract value objects, settings schema, ERP client/adapter and registry are functional; capability classes and the operation tool can now proceed

---

## Phase 3: User Story 1 - A capability is a strict contract the assistant cannot bend (Priority: P1) 🎯 MVP

**Goal**: A capability declares operations, validates model inputs strictly before external calls, records soft output deviations in trace without failing the turn, and resolves per-account satisfaction without raising exceptions.

**Independent Test**: Through `OperationTool` and `Scheduling#list_slots` (the only operation with no conversation-side precondition) against the WebMock ERP stand-in: missing/wrongly typed input → error returned and 0 requests; valid call → request made; payload missing a declared output field → returned to the assistant and recorded as a deviation. Registry resolution ("unsatisfied", no exception) is verified in Phase 2 (T011, T012).

**Prerequisite**: T023 exercises `Scheduling#list_slots` against the ERP stand-in, which needs the provider methods (T019, T020) and therefore the T001 fixtures (user input: test company/agenda). The US1 checkpoint cannot go green before T001, so ask for those inputs before starting.

### Tests for User Story 1 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T023 [P] [US1] Unit specs for `OperationTool` in `custom/spec/services/custom/scout_v2/capabilities/operation_tool_spec.rb`: missing required input and wrongly typed `date` input → `{ error: }` naming the input/expectation with WebMock reporting 0 requests; optional input omitted → call proceeds; output missing a declared non-identifier field → data still returned and deviation in the span; ERP timeout/error response → failed result saying the outcome may be unknown and not to repeat; credential rejection → definitive refusal text (`contracts/capabilities.md` §1a); request count = 1 (no retry), turn not ended; a non-ERP exception propagates (no broad rescue)

### Implementation for User Story 1

- [X] T026 [US1] Implement `OperationTool < Custom::Scout::Tools::BaseTool` in `custom/app/services/custom/scout_v2/capabilities/operation_tool.rb`: strict input check → capability precondition → provider call → soft output check → `CallRecord` on the tool span; `Erp::ApiError`/`Erp::AuthenticationError` mapped to `{ error: }` without retry
- [X] T026a [US1] Implement `Scheduling#list_slots` (provider call, `remember_slots!`, contract-shaped result `{ slots: [...] }`) in `custom/app/services/custom/scout_v2/capabilities/scheduling.rb` (after T020, T024)

**Checkpoint**: User Story 1 is functional and independently testable with `bundle exec rspec custom/spec/services/custom/scout_v2/capabilities/`; its request-level example (T037d) needs the scope wiring and playbook (T045, T046) and runs in Phase 5, so the Principle VI story gate for US1 closes only there

---

## Phase 4: User Story 2 - The integration hides configuration from the assistant (Priority: P2)

**Goal**: Integration settings and contact record supply credentials, configuration identifiers, and phone; the model authors only conversational inputs and cannot book un-offered slots or un-resolved customers.

**Independent Test**: Inspect WebMock ERP requests for configured identifiers, verify contact phone injection, verify precondition failures on missing phone or invalid booking state with 0 ERP calls, and test contact-data card compatibility.

### Tests for User Story 2 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T027 [P] [US2] Unit specs for `CustomerRegistry` in `custom/spec/services/custom/scout_v2/capabilities/customer_registry_spec.rb`: blank contact phone → error before any request; single match remembered via `remember_customer!`; several matches → ambiguous and never picked (FR-016); not found → `create` sends the given name with the contact's phone and remembers the customer; registration answered without a person id, or a single match without a readable id → failed result (not `created`, not `not_found`), no customer remembered (FR-029)
- [X] T028 [P] [US2] Unit specs for `Scheduling#book` in `custom/spec/services/custom/scout_v2/capabilities/scheduling_spec.rb`: no resolved customer → error before any request; `slot_id` never returned by a listing in this conversation → error before any request; slots from an earlier listing stay bookable after a new listing; success → `remember_booking!`; a second `book` (any slot) after a remembered booking → error before any request, booking unchanged (US2-AS11, FR-028); an answer without `appointment_id` → failed result, no booking remembered, exit stays rejected (FR-028)
- [X] T029 [P] [US2] Extend `custom/spec/services/custom/scout_v2/capabilities/operation_tool_spec.rb` for US2-AS1–5 and AS9: no operation's input declaration contains company/user/agreement/agreement number/origin/schedule/service identifiers, a credential, or a phone; requests for all four operations carry the configured identifiers and the contact phone and nothing supplied by the assistant (distinctive values); a distinctive `service` passed to `scheduling_list_slots` is recorded in the span inputs but the request carries the configured `id_servico` only; the trace records operation, assistant inputs, injected identifiers and phone, outcome — and never the token
- [X] T030 [P] [US2] Regression example for the contact-data card (US2-AS10, FR-026) in `custom/spec/requests/api/v1/accounts/integrations/erp_controller_spec.rb`: a hook holding only `token` + `id_empresa` still fetches customer data unchanged. If an equivalent example already exists, run it and add nothing

### Implementation for User Story 2

- [X] T031 [US2] Implement `CustomerRegistry#find_by_phone` and `#create` in `custom/app/services/custom/scout_v2/capabilities/customer_registry.rb`: phone from the contact, normalized with `provider.normalize_phone_digits` (first make `Erp::BaseAdapter#normalize_phone_digits` public in `custom/app/services/erp/base_adapter.rb` by moving it above `private` — visibility only; `BaseAdapter` specs stay green), precondition on blank phone, single/ambiguous/not_found handling, `remember_customer!`
- [X] T032 [US2] Implement `Scheduling#book` in `custom/app/services/custom/scout_v2/capabilities/scheduling.rb`: preconditions (no earlier booking, resolved customer, offered slot membership — in that order, `contracts/capabilities.md` §2.2) before any request, `create_appointment` for the remembered customer, `remember_booking!`

**Checkpoint**: User Stories 1 AND 2 work together: operations call the ERP with configured identifiers and hide all configuration from the model; its request-level example (T037e) runs in Phase 5 with T037d

---

## Phase 5: User Story 3 - A qualified lead is scheduled end to end in the playground (Priority: P3)

**Goal**: Qualified lead is guided through end-to-end scheduling in the playground, booking an offered slot with start and reference recorded, with handoffs for no phone, declined options, and ERP failures.

**Independent Test**: Run scripted multi-turn conversations in playground scheduling request specs for happy path, no-slot path, handoff paths, no-phone path, and verify exit precondition prevents premature agendado completion.

**Verification scope**: Scripted Gemini turns prove the plumbing (routing, tools, exits, state, trace). Model-driven behavior — at most three options, natural-language wording, options only from the ERP answer, two-failed-lookup counting (the system keeps no counter) — is bounded by the playbook guidance, asserted as key-phrase body invariants of the shipped `agendamento.md` in T047 (research §10 list, as 088 does) and confirmed in the manual playground pass (T054). The nearest-date search is bounded to the three days after the requested one (spec FR-019).

### Tests for User Story 3 ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T033 [P] [US3] Unit specs for exit precondition handling and outcome messaging in `custom/spec/services/custom/scout_v2/exits/exit_tool_spec.rb`: `agendado` without a successful booking → error, state unchanged, scheduling not completed; with a booking → accepted, message, persisted tool-call result and finished exit span carry booked start and reference (FR-022); an assistant-supplied `inicio` is rejected as undeclared; the precondition runs before dispatch
- [X] T034 [P] [US3] Unit specs for exit precondition grammar in `custom/spec/services/custom/scout_v2/playbook/loader_spec.rb` and `custom/spec/services/custom/scout_v2/playbook/dependency_rules_spec.rb` (known key, unknown precondition name rejected, only allowed on terminal exits)
- [X] T035 [P] [US3] Unit specs for phone-missing notice rendering (`requires: customer_registry` ∧ blank contact phone) in `custom/spec/services/custom/scout_v2/playbook/content_builder_spec.rb`
- [X] T036 [P] [US3] Unit specs for capability tools registration in `custom/spec/services/custom/scout_v2/turn_scope_spec.rb`: offered only while the playbook is in effect and every `requires` is satisfied; not offered to other playbooks, baseline or interruption takeovers; account HTTP tools (`call_custom_api`/`ScoutTool`) never offered by V2 (FR-026)
- [X] T047 [US3] Cut over the 088 specs to the target `agendamento.md` **before** T046 and observe them red: `playbook/catalog_spec.rb`, `turn_scope_spec.rb`, `unsatisfied_items_spec.rb`, `playbook/content_builder_spec.rb` (shipped-catalog examples; all under `custom/spec/services/custom/scout_v2/`) and `custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb` (4 markers, no `politica_reagendamento`, `agendado` without `inicio`, with `precondition: booking`). `catalog_spec.rb` also asserts the body invariants listed in `contracts/turn_assembly.md` §4. Numbered out of sequence: T047 runs before T046, which turns it green in the same commit (research §11)
- [X] T037a [US3] Acceptance request specs, success paths, in `custom/spec/requests/api/v1/accounts/scouts/playground_scheduling_spec.rb` (real playbook file, real routing, WebMock ERP and Gemini): scripted qualification pins scheduling by transition in the same turn (AS1), customer found (0 create requests) and customer not found → `customer_registry_create` with the confirmed name and the contact's phone (AS3), happy path to `exit_agendado` with the exit's persisted tool-call result carrying booked start and reference (AS5, FR-022), nearest-date path over at most three following days (AS6), no-slot path (AS7), booking within four lead messages (SC-004)
- [X] T037b [US3] Same file — handoff and rejection paths: person request / urgency / two failed lookups (two ambiguous answers) → built-in escalation exit (AS8), scheduled exit without a booking rejected with state unchanged (AS9), no-phone lead with 0 ERP requests and the missing phone stated (AS11), ERP timeout / credential rejection / error response → failed result, no booking promise, transfer in the same turn (AS12, SC-009)
- [X] T037c [US3] Same file — state paths: no re-pinning after scheduled / no-slot / transfer, including after hand-back (AS10, SC-007); degraded account keeps Brief 06 behavior with 0 ERP requests and unsatisfied items exactly `scheduling` + `customer_registry` (AS13, SC-003); satisfied account shows no pending step and empty unsatisfied items (AS2, SC-011)
- [X] T037d [US1] Same file — US1 contract-criterion (Principle VI): inside a real turn a model call with a missing or mistyped input gets the `{ error: }` result with 0 ERP requests and a corrected call in the same turn succeeds (AS1–3, SC-001); an ERP answer missing a declared output field completes the turn normally with the deviation in the finished span (AS4, SC-008)
- [X] T037e [US2] Same file — US2 contract-criterion (Principle VI): across a full turn the requests received by the WebMock ERP for all four operations carry the hook's distinctive identifiers and the contact's phone, nothing from the model, and the finished `capability_call` spans contain them but never the token (AS2–5, AS9, SC-002)

### Implementation for User Story 3

- [X] T038 [P] [US3] Implement `Exits::Preconditions` registry mapping `'booking'` to the capability-state check in `custom/app/services/custom/scout_v2/exits/preconditions.rb`
- [X] T039 [P] [US3] Add `precondition:` keyword (default `nil`) to `ExitDeclaration` in `custom/app/services/custom/scout_v2/playbook/exit_declaration.rb`
- [X] T040 [P] [US3] Add `'precondition'` to `ALLOWED_EXIT_KEYS` in `custom/app/services/custom/scout_v2/playbook/loader.rb`
- [X] T041 [P] [US3] Validate exit precondition existence and terminal-kind restriction in `custom/app/services/custom/scout_v2/playbook/dependency_rules.rb` (not in the Validator body — `Metrics/ClassLength`)
- [X] T042 [US3] Check exit precondition before dispatch in `custom/app/services/custom/scout_v2/exits/exit_tool.rb`, returning an error on unmet precondition (after T038, T039)
- [X] T043 [US3] Update `Terminal#success_message` in `custom/app/services/custom/scout_v2/exits/terminal.rb` to report booked start and reference for the booking precondition
- [X] T044 [US3] Implement `PHONE_MISSING_NOTICE` appending in `custom/app/services/custom/scout_v2/playbook/content_builder.rb` for `customer_registry` with blank contact phone
- [X] T045 [US3] Register capability `OperationTool`s under the "playbook in effect + all `requires` satisfied" scoping in `custom/app/services/custom/scout_v2/turn_scope.rb` (keep `TurnScope` ≤ 175 lines; extract if needed)
- [X] T046 [US3] Rewrite `custom/playbooks/agendamento.md` (Portuguese) to the target shape and body invariants of `contracts/turn_assembly.md` §4 and research §11: `precondition: booking` on `agendado` without `inicio`; drop `needs: [politica_reagendamento]` and step 6; `not_found` → confirm the name, `customer_registry_create`; two `ambiguous` → `exit_handoff`; any ERP failure or tool error → `exit_handoff` in the same turn, never repeating the call; phone-missing handoff; ≤ 3 returned options; nearest-date rule bounded to three days. Makes T047 green (after T047 and T039–T041, so the shipped catalog still boots)

**Checkpoint**: All user stories functional, tested, and integrated end-to-end

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Repository-wide health gates, regression, mutation checks, and manual verification against the real ERP

- [X] T048 [P] Verify sync custom module hooks: `docker compose exec rails ruby bin/sync-custom-module-hooks --check` (0 `missing`, `younus` entry matches `apps.yml`) and `--audit` (0 gaps, `apps.yml` shows `covered`; fast-forward `develop` first — AGENTS.md)
- [X] T049 [P] Validate code style: `docker compose exec rails bundle exec rubocop` (0 offenses; no `.rubocop_todo.yml` additions)
- [X] T050 Verify database schema consistency: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec spec/config/schema_spec.rb`
- [X] T051 Run the targeted regression sets of `quickstart.md` §2 (capabilities + ERP, exits/playbook/snapshot/scope/model/integrations, acceptance including `custom/spec/jobs/custom/scout/process_message_job_spec.rb` and `custom/spec/requests/api/v1/accounts/integrations/`) and confirm the existing engine and the contact-data card show no change (SC-010)
- [X] T052 Run the deliberate-mutant checks of `quickstart.md` §5 (Principle VII): apply each mutation, confirm the named example turns red, revert it, and re-run the touched specs green
- [X] T053 Execute the console smoke check of `quickstart.md` §3 (independent capability resolution: all identifiers → both names; blank `id_agenda` → `customer_registry` only)
- [X] T054 Manual playground pass of `quickstart.md` §4 against a real ERP integration (SC-010, US3-AS14): performs real writes, so use only a test company/agenda supplied by the user; reset the sandbox state and set the contact phone per §4 step 2; verify identifiers in the recorded `capability_call` spans equal the hook's, no token, ≤ 3 natural-language options, nearest-date search limited to the three following days, two failed lookups (ambiguous) → transfer, the no-slot / person-request / no-phone / wrong-token paths, and no re-pinning afterwards. Do not commit or push before the user's explicit validation (AGENTS.md workflow constraint)
  - **Concluído por transferência (2026-09-30, decisão do usuário)**: 089 aprovado no código e testes T001–T053; a execução da prova prática no playground contra o ERP real foi transferida para a Fase 13 (`docs/kanban/ciclo 13/scoutv2/briefs/13-disciplina-de-interrupcao-e-prova-do-agendamento.md`, §7 "Prova herdada do brief 07"), onde as correções de disciplina de interrupção e identificação tornarão a conversa estável até o agendamento.
- [X] T055 After the user's explicit validation and only when a PR is opened, record the Principle V decision in the PR description: `grep -rnE "Erp::|ScoutV2|integrations/hook" enterprise/` finds nothing and no OSS class is edited, so no Enterprise override or extension point is needed. No commit or push before that validation (AGENTS.md)
  - **Concluído**: Verificação executada no repositório (`grep -rnE "Erp::|ScoutV2|integrations/hook" enterprise/` retornou 0 ocorrências). Registro preparado para inclusão na descrição do PR.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies. T001 needs user input (test company/agenda) — ask first; T009, T010, T019 and T020 (provider methods) wait for its fixtures; T020a, T021 and T022 do not.
- **Foundational (Phase 2)**: Depends on Setup T002–T003; T001 gates only T009, T010, T019 and T020 — BLOCKS all user stories. Internal order: tests T004–T012 → implementation; T016 after T014; T018 after T017; T020 after T019; T020a has no dependency; T024 and T025 after T016; T021 after T016 + T020a + T024 + T025; T022 after T021.
- **User Story 1 (Phase 3)**: Depends on Foundational (T004–T025).
- **User Story 2 (Phase 4)**: Depends on US1 (`OperationTool` T026, `Scheduling#list_slots` T026a, contracts T024/T025).
- **User Story 3 (Phase 5)**: Depends on US2 for the end-to-end specs T037a–e and the playbook rewrite T046 (T047 first, red, then T046; T046 also waits for T039–T041). The exit-precondition tasks (T033/T034, T038–T043), the phone-missing notice (T035/T044) and capability tool scoping (T036/T045) depend only on Foundational + US1 and may start earlier.
- **Polish (Phase 6)**: Depends on all user story phases being complete. T054 is the last verification and needs the user; T055 follows the user's validation.

### User Story Dependencies

- **User Story 1 (P1)**: Contract strictness and tool envelope; uses the Foundational ERP layer. No story dependencies.
- **User Story 2 (P2)**: Requires US1 `OperationTool` and capability files to add conversation-side rules and identifier/phone verification.
- **User Story 3 (P3)**: Requires US2 to execute the full scheduling flow with exit preconditions.

### Within Each User Story

- Tests MUST be written and observed failing before implementation
- Value objects / schemas before services
- Services / adapters before playbook / UI wiring
- Core capability implementation before cutover updates

### Parallel Opportunities

- Phase 1: none (sequential fixture and database steps).
- Phase 2: tests T004–T012 in parallel (T009/T010 after T001); then implementation T013, T014, T015, T017, T019, T020a in parallel; T016, T018, T020 follow their dependencies, then T024 and T025 in parallel, then T021, T022.
- Phase 3: none (T026 then T026a).
- Phase 4: T027–T030 in parallel.
- Phase 5: T033–T036 in parallel; T038–T041 in parallel. T035, T036 and T047 edit the same spec files (`content_builder_spec`, `turn_scope_spec`): run T047 after T035/T036, never concurrently.
- Phase 6: T048 and T049 in parallel.

---

## Parallel Example: Foundational tests

```bash
Task: "Unit tests for ScoutConversationState in custom/spec/models/scout_conversation_state_spec.rb"
Task: "Unit tests for Operation in custom/spec/services/custom/scout_v2/capabilities/operation_spec.rb"
Task: "Unit tests for Registry in custom/spec/services/custom/scout_v2/capabilities/registry_spec.rb"
Task: "Contract specs for younus app/hook settings in custom/spec/models/custom/integrations/{app,hook}_spec.rb"
```

## Parallel Example: User Story 2

```bash
Task: "Unit specs for CustomerRegistry in custom/spec/services/custom/scout_v2/capabilities/customer_registry_spec.rb"
Task: "Unit specs for Scheduling#book in custom/spec/services/custom/scout_v2/capabilities/scheduling_spec.rb"
Task: "Identifier/phone/trace examples in custom/spec/services/custom/scout_v2/capabilities/operation_tool_spec.rb"
Task: "Contact-data card regression in custom/spec/requests/api/v1/accounts/integrations/erp_controller_spec.rb"
```

## Parallel Example: User Story 3

```bash
Task: "Unit specs for exit precondition handling in custom/spec/services/custom/scout_v2/exits/exit_tool_spec.rb"
Task: "Unit specs for exit precondition grammar in loader_spec.rb and dependency_rules_spec.rb"
Task: "Unit specs for phone missing notice rendering in content_builder_spec.rb"
Task: "Unit specs for capability tools registration scoping in turn_scope_spec.rb"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (fixtures and migration; T001 needs the user's test company/agenda and gates the US1 checkpoint)
2. Complete Phase 2: Foundational (state, value objects, settings schema, ERP client/adapter, registry, snapshot)
3. Complete Phase 3: User Story 1 (capability contracts and operation tool)
4. **STOP and VALIDATE** (unit level only — US1's request-level example T037d needs T045/T046, so US1 alone is not releasable): `bundle exec rspec custom/spec/services/custom/scout_v2/capabilities/`
5. Demonstrate strict input rejection (0 requests) and soft output deviation recording

### Incremental Delivery

1. Setup + Foundational → data structures, ERP layer and satisfaction registry ready
2. Add User Story 1 → strict contract enforcement and tool envelope operational (MVP)
3. Add User Story 2 → configuration hidden, conversation-side preconditions enforced
4. Add User Story 3 → playground end-to-end scheduling with exit preconditions and guidance
5. Polish → regression, mutants, manual pass against the real ERP

### Parallel Team Strategy

With multiple developers:
1. Team completes Setup + Foundational together (T001–T022)
2. After Foundational:
   - Developer A: User Story 1 (T023, T026, T026a), then User Story 2 (T027–T032)
   - Developer B: the US3 pieces that depend only on Foundational + US1 (T033–T036, T047 red-run, T038–T044, T045)
3. Developer A or B then completes T047 (red), T046, T037a–e once US2 is done, and Polish

---

## Notes

- `[P]` tasks = different files, no dependencies
- `[Story]` label maps task to specific user story for traceability
- Each user story is independently completable and testable
- Strict adherence to TDD: verify tests fail before implementing
- Commit only after the user's explicit validation (AGENTS.md); when committing, run `git commit` inside the `vite` container
- Containerized execution: prefix Ruby commands with `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec`
- Do not run full global test suites during iteration; scope test runs surgically to the modified component (Constitution Principle IX)

## Phase 7: Convergence

- [X] T056 CRITICAL: Rewrite `custom/spec/services/custom/scout_v2/capabilities/customer_registry_spec.rb` and `scheduling_spec.rb` without `instance_double(Erp::Younus::Adapter)` / `allow(provider).to receive(...)`: build a real `Integrations::Hook` (`app_id: 'younus'`, all seven identifiers + token) and the real `Erp::Younus::Adapter`, stub only the vendor HTTP with WebMock using the T001 fixtures (`find_person_*`, `create_person`, `free_slots*`, `create_appointment`, `error_declined`), and assert the requests received and the persisted `capability_state`; keep every existing scenario (no-phone, single/ambiguous/not_found, FR-029 missing id, FR-013/FR-014/FR-028 book preconditions, booking without `appointment_id`). In `capabilities/base_spec.rb` replace `instance_double(Erp::BaseAdapter)`/`instance_double(Conversation)` with a real adapter and a factory conversation per Constitution VII (contradicts)
- [X] T057 CRITICAL: Rewrite `custom/spec/services/erp/younus/adapter_spec.rb` so the capability-provider examples (`find_person`, `create_person`, `list_free_slots`, `create_appointment`, and the existing `test_connection`/`find_by_id`/`search_by_phone` examples) no longer use `instance_double(Erp::Younus::Client)` / `allow(Erp::Younus::Client).to receive(:new)`: drive the real client against WebMock with the T001 fixtures, asserting the normalized contract shapes (`:ambiguous`/`:not_found`/`:found`, `-03:00` slot start, sorted slots, `appointment_id` nil when the vendor omits it) per Constitution VII and plan.md Constitution Check VII ("no stub of `Erp::Younus::Adapter`") (contradicts)
- [X] T058 CRITICAL: In `custom/spec/services/custom/scout_v2/capabilities/operation_tool_spec.rb` remove the internal-collaborator doubles: replace `allow(adapter).to receive(:list_free_slots)` (non-ERP exception example and the soft-output example) with WebMock responses (a malformed/short vendor answer for the deviation example; a real non-`Erp::Error` failure path or drop the example if no real trigger exists), replace the `instance_double(OpenTelemetry::Trace::Span)` / `allow(OpenTelemetry::Trace).to receive(:current_span)` capture with the OTel in-memory exporter pattern from the 088 trace specs, and replace `instance_double(Custom::ScoutV2::TurnScope)` with a real `TurnScope`. In `custom/spec/requests/api/v1/accounts/scouts/playground_scheduling_spec.rb` (~line 616) replace `allow_any_instance_of(Erp::Younus::Adapter).to receive(:list_free_slots)` (SC-008 example) with a WebMock vendor answer that yields the slot without a start, and drop its `rubocop:disable RSpec/AnyInstance` per Constitution VII (contradicts)
- [X] T059 CRITICAL: In `custom/spec/services/custom/scout_v2/routing_snapshot/builder_spec.rb` ("satisfied_capabilities resolution") replace `allow(Custom::ScoutV2::Capabilities::Registry).to receive(:satisfied_names)` with real `Integrations::Hook` rows (fully configured hook → `%w[scheduling customer_registry]`, hook lacking `id_agenda` → `customer_registry` only, no hook → `[]`); in `custom/spec/models/custom/integrations/hook_spec.rb` ("settings schema validation (FR-010, US2-AS10)") replace `instance_double(Erp::Younus::Adapter)` + `allow(Erp::AdapterFactory).to receive(:build)` with a WebMock stub of the vendor connection-test request, per Constitution VII (contradicts)
- [X] T060 Make the `capability_call` `injected` record list only the identifiers that operation's ERP request actually carries, per FR-017 and `contracts/capabilities.md` §5 (today `OperationTool#extract_settings_identifiers` reads `provider.instance_variable_get(:@settings)` and records every present identifier for every operation, e.g. `id_usuario`/`id_convenio` on `scheduling_list_slots`, which sends only `id_empresa`, `id_agenda`, `id_servico`): expose the per-operation identifier keys from the provider (declared next to the client request shapes, no `instance_variable_get`), record exactly those plus `phone`/`person_id`, and strengthen `operation_tool_spec.rb` (currently `include(...)`) plus `playground_scheduling_spec.rb` (T037e) to assert the exact `injected` hash per operation so a superset fails (partial)
- [X] T061 Add the model-facing `description` for operation inputs to `Operation#params_schema` (and the `input` DSL in `Capabilities::Base`), declaring at least `service` on `scheduling_list_slots` as "nome do serviço desejado, apenas informativo" (recorded in the trace, never sent) and the `YYYY-MM-DD` format of `date`, per FR-002 and `contracts/capabilities.md` §2.1 / T024; cover it in `operation_spec.rb` (`params_schema` includes the description) (partial)

## Phase 8: Convergence

- [X] T062 CRITICAL: Remove internal-collaborator doubles from the specs that carry 089's contact-data-card proof and hook validation, per Constitution VII and US2/AC10: in `custom/spec/requests/api/v1/accounts/integrations/erp_controller_spec.rb` (lines ~53-87) replace `instance_double(Erp::Younus::Adapter)`, `allow(Erp::AdapterFactory).to receive(:build)`, `allow(adapter).to receive(:fetch_data)` and `instance_double(ChatwootExceptionTracker)` with WebMock stubs of the Younus endpoints (assert the JSON body and the 5xx status, not `have_received(:capture_exception)`); in `custom/spec/models/custom/integrations/hook_spec.rb` replace the `instance_double(Erp::Younus::Adapter)` / `allow(Erp::AdapterFactory).to receive(:build)` / `have_received(:test_connection)` examples of the "whitespace sanitization", "synchronous connection validation", "non-ERP hooks" and "validation localization" groups with the real factory/adapter against a WebMock stub of the vendor connection-test request (assert the request made or not made). Keep every existing scenario (contradicts)
- [X] T063 HIGH: Complete the `agendamento.md` guidance per FR-019, FR-015 and `contracts/turn_assembly.md` §4 (today step 5 never names `scheduling_list_slots` for the nearest-date search, never says the no-slot reason must state that no availability was found when none of the three following days has a free time, and the ERP-failure rule in step 7 lacks "não repita a chamada"): name `scheduling_list_slots` in step 5, require `exit_sem_horario` to state that no availability was found when the three-day search finds nothing, and add that an ERP failure or tool error is never retried before `exit_handoff`. Keep the four `[[depends:]]` markers on their current steps (partial)
- [X] T064 HIGH: Extend `custom/spec/services/custom/scout_v2/playbook/catalog_spec.rb` with key-phrase assertions for the remaining `contracts/turn_assembly.md` §4 body invariants, per T047, FR-019, FR-020 and FR-024 (today only marker counts and tool-name `include`s are asserted): not_found → confirm the name then `customer_registry_create`; two `ambiguous` answers → `exit_handoff`; at most three returned times in natural language and only a returned `slot_id`; `exit_agendado` only after `scheduling_book` succeeded; nearest date searched with `scheduling_list_slots` on at most the three following days, none free → `exit_sem_horario` stating no availability was found; person request / clinical urgency / tool error → `exit_handoff` in the same turn without a booking promise and without repeating the call; missing phone → `exit_handoff` without asking for it and without `customer_registry_*` calls; no rescheduling/cancellation rules. Write them before T063 and observe them red (partial)
- [X] T065 MEDIUM: Strengthen the US3 acceptance examples in `custom/spec/requests/api/v1/accounts/scouts/playground_scheduling_spec.rb`, per Constitution VI/VII and US3/AC6, AC7, AC8 (today AS6 ends on `capability_state['booking']` `be_present` and never asserts the booked start or the three-day bound; AS7 never asserts how many days were probed; AS8 has no clinical-urgency turn, no transfer-effect assertion and no count of the two find-by-phone requests): assert `capability_state['booking']` start/appointment id equal the nearest-date slot and that no listing request is made beyond the third following day (AS6, AS7), add a clinical-urgency turn and assert the transfer effect on the conversation plus exactly two find-by-phone requests for the ambiguous path (AS8) (partial)
- [X] T066 MEDIUM: Add a test that capability `OperationTool`s and `exit_agendado` are NOT registered during an interruption takeover while `agendamento` is pinned and both capabilities are satisfied, per FR-018, `contracts/turn_assembly.md` §5 (takeover row) and the quickstart §5 mutant "actions_for registers capability tools for takeover playbooks", in `custom/spec/services/custom/scout_v2/turn_scope_spec.rb` (real pinned state + real takeover, observe the registered tool names) (missing)
- [X] T067 MEDIUM: Run the exit precondition before payload validation in `Exits::ExitTool#execute` (`custom/app/services/custom/scout_v2/exits/exit_tool.rb`), per `contracts/turn_assembly.md` §3 ("before payload validation and dispatch") and T033: today `PayloadValidator.call` runs first, so `exit_agendado` without a booking and with an undeclared `inicio` returns the payload error instead of the booking error; add the example to `exits/exit_tool_spec.rb` first and observe it red (contradicts)
- [X] T068 LOW: Restrict the `settings:` kwarg built by `Erp::Younus::Adapter#client_kwargs` (`custom/app/services/erp/younus/adapter.rb`) to the seven identifier keys (`id_empresa`, `id_usuario`, `id_convenio`, `nr_convenio`, `id_origem_pessoa`, `id_agenda`, `id_servico`), per `contracts/erp_provider.md` §3 and FR-017 (today it passes the whole hook settings, token included, although the client already receives `token:` separately); cover it in `erp/younus/adapter_spec.rb` (contradicts)
- [X] T069 LOW: Remove the unused alias keys (`find_person`, `create_person`, `list_free_slots`, `create_appointment`) from `Erp::Younus::Adapter::OPERATION_IDENTIFIER_KEYS` (only `find_by_phone`, `create`, `list_slots`, `book` are ever passed by `OperationTool`), and record the `operation_identifier_keys` provider hook (also declared on `Erp::BaseAdapter`, beyond the plan's "visibility only" edit of that file) in `plan.md`/`contracts/erp_provider.md` or derive the keys from the existing contract, per Constitution II and plan.md "Scale/Scope" (unrequested)

## Phase 9: Convergence

- [X] T070 LOW: Record `nr_convenio` in the `capability_call` `injected` hash exactly as sent to the ERP, per FR-017 and `contracts/capabilities.md` §5 (`OperationTool#cast_identifier` in `custom/app/services/custom/scout_v2/capabilities/operation_tool.rb` runs `Integer()` on every identifier, so a configured agreement number such as `"000123"` is traced as `123` while `Erp::Younus::Client#create_person` sends `nrConvenio` as the string `"000123"`): cast only the `id_*` keys (which the client also sends via `Integer()`) and keep `nr_convenio` a string; add the example first with a leading-zero `nr_convenio` in `custom/spec/services/custom/scout_v2/capabilities/operation_tool_spec.rb` (`customer_registry_create` span `injected`) and observe it red (partial)

## Phase 10: Convergence

- [X] T071 HIGH: Reconcile the T001 fixtures in `custom/spec/fixtures/erp/younus/` with the specs that consume them — 9 examples fail today because the files drifted from their consumers: `free_slots.json` carries its slots under `dados` (strings `2026-10-15 09:30 …`) while `Erp::Younus::Client#free_slots` reads the vendor's `horarios` envelope (as `free_slots_empty.json` does), so every listing comes back `[]`; `find_person_found.json` holds `idPessoa 123456` / `Maria Silva` / `idEmpresa 1041` while the specs expect `784868` / `Teste Lead Scout` / `648` (`create_person.json`, `create_appointment.json` and `find_person_multiple.json` already use those). Restore `free_slots.json` to the `horarios` envelope with the `2026-10-15 08:00` / `08:40` times the specs assert (T001: anonymize personal data only, keep keys and envelope), align `find_person_found.json` with the test-company values, and do not loosen any assertion. Acceptance: `custom/spec/services/erp/younus/{adapter,client}_spec.rb`, `capabilities/customer_registry_spec.rb:64` and `custom/spec/requests/api/v1/accounts/scouts/playground_scheduling_spec.rb` (T037a AS3/AS5/SC-004, T037e) all pass, per T001, T009, T010, T027, T037a, T037e (partial)
- [X] T072 LOW: Remove the dead fallbacks in `OperationTool#extract_settings_identifiers` (`custom/app/services/custom/scout_v2/capabilities/operation_tool.rb`): `provider.respond_to?(:settings)` / `respond_to?(:operation_identifier_keys)` are always true (`Erp::BaseAdapter` exposes both publicly), so the `provider.instance_variable_get(:@settings)` branch and the `CallRecord::ALLOWED_INJECTED_KEYS` else-branch (which would trace every identifier for an operation) can never run; read `provider.settings` and `provider.operation_identifier_keys(@operation.name)` directly, per T060 ("no `instance_variable_get`") and Constitution II (partial)

## Phase 11: Convergence

- [X] T073 MEDIUM: Restore the T049 gate (`docker compose exec rails bundle exec rubocop` with 0 offenses): `bin/sync-custom-module-hooks` (a file this feature edits for the `younus` MANIFEST entry) now reports `Layout/CommentIndentation` (line 716) and `Layout/ArrayAlignment` (line 717) in the Langfuse-metadata MANIFEST block; fix them with `rubocop -a` on that file only (no `.rubocop_todo.yml` additions) and re-run `ruby bin/sync-custom-module-hooks --check` to confirm every wiring point is still present, per plan.md Constraints and Constitution III (contradicts)
- [X] T074 LOW: Resolve the capability hooks lookup once per turn, per plan.md Performance Goals ("one `hooks` query per turn"): `Registry.satisfied_names` calls `resolve` once per capability name and `TurnScope#capability_tools_for` calls `resolve` again per required capability, each running its own `account.hooks.where(status: :enabled)` query (2 in `RoutingSnapshot::Builder` plus up to 2 in `TurnScope` for `agendamento`); find the ERP hook once inside `Registry.satisfied_names` (keeping `resolve(name, account:)` for single-name callers and the never-raises contract) and cover the capability independence cases of `registry_spec.rb` unchanged (partial)
- [X] T075 LOW: Remove dead code in the capability layer, per Constitution II and AGENTS.md ("Remove dead/unreachable/unused code"): the unused aliases `Custom::ScoutV2::Capabilities::Operation::DATE_FORMAT` (`operation.rb`) and `CallRecord::ALLOWED_INJECTED_KEYS` (`call_record.rb`) have no references anywhere in `custom/`, `app/` or `lib/`; and the `@scope.respond_to?(:ended?) && @scope.ended?` turn-ended check in `OperationTool#execute` duplicates `TurnScope#guard_tool`, which already short-circuits every registered tool's `execute` with `TURN_ENDED_ERROR` once the turn has ended (the scope is always a `TurnScope`); drop them and keep `operation_tool_spec.rb`/`turn_scope_spec.rb` green (unrequested)

## Phase 12: Convergence

- [X] T076 HIGH: Stop `Erp::Younus::Adapter#create_appointment` (`custom/app/services/erp/younus/adapter.rb`) from reporting a person identifier as the appointment identifier, per FR-028, FR-029 and SC-005 (today `app_id` ends with `|| external_id_from(res)`, which reads `cd_pessoa`/`idPessoa`; the vendor's booking answer echoes `idPessoa` (`fixtures/erp/younus/create_appointment.json`), so a booking answered without `idMvtoagenda` yields `appointment_id: "784868"` instead of `nil`, `Scheduling#handle_booking_result` records a booking that cannot be verified, and `exit_agendado` is accepted). Read the appointment identifier only from the appointment keys (`idMvtoagenda`, `id_mvtoagenda`, `idAgendamento`, `id_agendamento`); add the example first in `custom/spec/services/erp/younus/adapter_spec.rb` (`dados` carrying `idPessoa` but no appointment key → `appointment_id: nil`) and observe it red, then extend `scheduling_spec.rb` with the same WebMock body (→ failed result, no `booking` in `capability_state`, exit stays rejected) (partial)
- [X] T077 MEDIUM: Map every transport-level ERP failure to `Erp::ApiError` in `Erp::Younus::Client#get_request` / `#post_request` (`custom/app/services/erp/younus/client.rb`), per FR-015, FR-004 and SC-009 (today only `Timeout::Error`, `SocketError`, `Errno::ECONNREFUSED` and `JSON::ParserError` are rescued, so a connection reset, unreachable host, truncated response or TLS failure — `Errno::ECONNRESET`, `Errno::EHOSTUNREACH`, `EOFError`, `OpenSSL::SSL::SSLError` — escapes `OperationTool#perform_operation` (which rescues only `Erp::Error`) and raises through the tool call instead of returning the "outcome unknown, do not repeat, `exit_handoff`" failed result); share one rescue list between the two request methods, add WebMock `to_raise` examples first in `custom/spec/services/erp/younus/client_spec.rb` and an `operation_tool_spec.rb` example (a write raising `Errno::ECONNRESET` → `{ error: }` with the unknown-outcome text, 1 request, turn not ended) and observe them red (partial)
- [X] T078 LOW: Remove the dead fallback and no-op in `Custom::ScoutV2::Capabilities::Scheduling` (`custom/app/services/custom/scout_v2/capabilities/scheduling.rb`), per Constitution II and AGENTS.md ("Remove dead/unreachable/unused code"): `book` computes `starts_at = cap_state.dig('offered_slots', slot_id.to_s) || slot_id.to_s`, but `check_preconditions_for_book` (run by `OperationTool` before `book`) guarantees the slot is in `offered_slots`, so the `|| slot_id.to_s` branch can never run; and `list_slots` carries an unused `_ = service` assignment (the optional `service` input is validated and traced by `OperationTool`, never read by the capability) — take `service:` through `**_extra` or an ignored keyword instead; keep `scheduling_spec.rb`/`operation_tool_spec.rb` green (unrequested)

## Phase 13: Convergence

- [X] T079 MEDIUM: Assert the output-shape deviation in the finished span in the US1 contract-criterion example `verifies AS4 and SC-008` of `custom/spec/requests/api/v1/accounts/scouts/playground_scheduling_spec.rb` (today it ends on `reply` `eq('Temos opções disponíveis!')`, so a mutant that drops `deviations` from the `capability_call` record, or that fails the turn's tool result, still passes): reuse the `InMemorySpanExporter` setup of the T037e `describe` (lines ~676-751), select the finished `capability_call` span for `scheduling_list_slots`, and assert `deviations` contains the missing `starts_at` item message and that the tool call's `result['slots']` is still returned to the assistant, per T037d, US1/AC4, SC-008 and Constitution VI/VII (partial)
- [X] T080 LOW: Replace the `be_present`-only assertion that closes `verifies SC-004: booking within four lead messages` in `custom/spec/requests/api/v1/accounts/scouts/playground_scheduling_spec.rb` with the concrete booked values (`capability_state['booking']['starts_at']` equals `2026-10-15T08:00:00-03:00` and `['appointment_id']` equals the `create_appointment.json` id), assert the `exit_agendado` tool call's persisted result carries them, and assert the example sent at most four lead messages (the count of `post_message` calls, now implicit), per SC-004, SC-005 and Constitution VII ("be_present" assertions are prohibited) (partial)

## Phase 14: Convergence

- [X] T081 MEDIUM: Treat a `sucesso: false` answer from the slot listing as an ERP failure instead of an empty day, per FR-015, SC-009 and US3/AC12 (today `Erp::Younus::Client#handle_read_response` in `custom/app/services/erp/younus/client.rb` returns `[]` for `mode == :slots && !body['sucesso']`, so a vendor error on `/webhook/horarios-livres` answered with HTTP 200 reaches the assistant as "no free time" and drives the nearest-date search and `exit_sem_horario` instead of the immediate `exit_handoff`; the captured empty-day fixture `free_slots_empty.json` is `sucesso: true` with `horarios: []`, so the two cases are distinguishable): raise `Erp::ApiError` (mensagem of the body) for `sucesso: false` in `:slots` mode only, leave `find_person`/`find_by_id`/`search_by_phone` (`sucesso: false` = not found, `find_person_none.json`) unchanged, add a client example (`sucesso: false` listing raises, `free_slots_empty.json` still returns `[]`) and an `OperationTool`/`Scheduling#list_slots` example (failed result, outcome unknown text, no offered slots remembered) observed red first, and correct the "GET answered 200 with `sucesso: false`" row of `contracts/erp_provider.md` §3 to exclude the slot listing (partial)
- [X] T082 LOW: Remove the blanket `rescue StandardError` blocks in `Custom::ScoutV2::Capabilities::Registry` (`custom/app/services/custom/scout_v2/capabilities/registry.rb`), per Constitution II and AGENTS.md ("let impossible or misconfigured states fail loudly", "remove dead code"): the one in `satisfied_names` is unreachable (it only calls `find_erp_hook` and `resolve`, both already rescued), the one in `find_erp_hook` silently turns a database error into "unsatisfied", and the one in `resolve` only masks a `nil` `PROVIDERS[hook.app_id]` that `find_erp_hook` already excludes; FR-006 ("no suitable integration → unsatisfied, never raises") is satisfied by the explicit no-hook / unsupported-vendor / missing-or-malformed-setting branches, so keep those, drop the rescues, and keep `registry_spec.rb` green (no hook, disabled hook, feature flag off, unsupported vendor, blank or non-numeric setting) (unrequested)

## Phase 15: Convergence

- [X] T083 HIGH: Stop leading-zero identifiers from raising in the ERP client, per FR-007, the Clarification "a malformed value never reaches a request and never raises" and SC-003: `Registry#settings_satisfied?` (`custom/app/services/custom/scout_v2/capabilities/registry.rb`) accepts `'08'`/`'09'` (`/\A\d+\z/`), but `Erp::Younus::Client#setting_int` and `#create_appointment` (`custom/app/services/erp/younus/client.rb`) call `Integer('08')`, which raises `ArgumentError` (octal parse) and escapes `OperationTool` (it rescues only `Erp::Error`). Parse with base 10 (`Integer(val, 10)`) for every identifier and for `person_id`, and make `Erp::Younus::Adapter#find_person`/`#create_person` return a failed result (outcome unknown, do not repeat; no customer remembered) if `idPessoa` is non-numeric, rather than raising `ArgumentError` in `Integer(raw_id)`. Cover in `client_spec.rb` and `adapter_spec.rb`
- [X] T084 MEDIUM: Prove US3/AC10 and SC-007 end to end for the scheduled and "no slot" outcomes in `custom/spec/requests/api/v1/accounts/scouts/playground_scheduling_spec.rb`: today the example `verifies AS10 and SC-007` seeds `completed_playbooks: ['agendamento']` with `state.update!` and sends one message, and the real `exit_agendado` / `exit_sem_horario` / `exit_handoff` examples never send a follow-up message; after each real terminal exit flip the conversation back to `pending` (human hand-back), send another lead message, and assert scheduling is not pinned, `scheduling_*`/`exit_agendado` are not offered to the model, and the stand-in ERP receives no further request
- [X] T085 LOW: Map the remaining transport-level network failures to `Erp::ApiError` in `Erp::Younus::Client::TRANSPORT_ERRORS` (`custom/app/services/erp/younus/client.rb`), per FR-015 and SC-009: `Errno::ETIMEDOUT`, `Errno::ENETUNREACH` and `HTTParty::Error` currently propagate raw out of `OperationTool` instead of producing a failed result and the same-turn transfer; add the examples to `client_spec.rb` first (WebMock `to_raise`) and observe them red
- [X] T086 MEDIUM: Review and resolve working-tree changes unrelated to feature 089 and outside the scope of its spec, plan and tasks, per Constitution I (core files `config/environments/test.rb` deprecation lambda, `spec/rails_helper.rb` `filter_gems_from_backtrace`, `lib/integrations/llm_instrumentation_helpers.rb` extraction of `append_propagated_metadata_attributes`): either justify and commit them as their own change tracked outside 089 (the `docs/kanban/backlog/token-cost-vs-test-fidelity` lever work), or revert them so the 089 diff contains only its planned files; for `lib/integrations/llm_instrumentation_helpers.rb`, a behavior-neutral refactor of an upstream file also needs a MANIFEST entry or revert (unrequested)

## Phase 16: Convergence

- [X] T087 MEDIUM: Resolve the remaining working-tree changes that belong to feature 088's convergence (088 T098–T101), not to 089, per plan.md Constraints ("`TurnRunner` is not touched") and Constitution II/VIII: `custom/app/services/custom/scout_v2/turn_runner.rb` (line ~95 wraps the chat with `Tools::UnavailableToolCallRecorder.install!`) plus the new `custom/app/services/custom/scout_v2/tools/unavailable_tool_call_recorder.rb`, `custom/playbooks/fora_de_prospeccao.md` ("baixa complexidade" qualifier), `custom/spec/services/custom/scout_v2/router_spec.rb` (exhaustive state combinations), and `specs/088-scout-v2-first-playbooks/{plan,tasks}.md`; commit them as their own 088 change (separate from the 089 commit) or revert them, so the 089 diff contains only its planned files. T086 covered only `config/environments/test.rb`, `spec/rails_helper.rb` and `lib/integrations/llm_instrumentation_helpers.rb`; do not commit before the user's explicit validation (AGENTS.md) (unrequested)
  - **Concluído por segregação**: As alterações da convergência da feature 088 foram mapeadas e segregadas para commit dedicado (`feat(scout_v2): convergence fixes for first-cut playbooks (spec 088)`), mantendo o commit da 089 estritamente isolado aos seus arquivos planejados. Conforme a regra de ouro do repositório (`AGENTS.md`), nenhum commit ou push é executado antes da validação expressa do usuário.

## Phase 17: Convergence

- [X] T088 LOW: Remove the dead `scope` collaborator from `Custom::ScoutV2::Capabilities::OperationTool` (`custom/app/services/custom/scout_v2/capabilities/operation_tool.rb`), per Constitution II and AGENTS.md ("Remove dead/unreachable/unused code"): after T075 dropped the turn-ended check, nothing reads `@scope` or `attr_reader :scope` (turn-ended short-circuiting is `TurnScope#guard_tool`); drop the `scope:` keyword and reader from `OperationTool#initialize`, the `scope: self` argument in `TurnScope#build_operation_tools` (`custom/app/services/custom/scout_v2/turn_scope.rb`), and the `scope: scope` arguments in `operation_tool_spec.rb` (lines ~12 and ~271; keep the real `TurnScope` where the example needs it for `turn_scope.ended?`), then re-run `custom/spec/services/custom/scout_v2/capabilities/operation_tool_spec.rb` and `turn_scope_spec.rb` (unrequested)

## Phase 18: Vendor path and envelope migration

- [X] T089 HIGH: Follow the vendor migration of the ERP endpoints (2026-10-02) in `Erp::Younus::Client` (`custom/app/services/erp/younus/client.rb`): `find_person`/`search_by_phone` -> `GET /webhook/api/v1/empresas/pessoas/pesquisar`, `create_person` -> `POST /webhook/api/v1/empresas/pessoas`, `find_by_id` -> `GET /webhook/api/v1/empresas/pessoas`, `free_slots` -> `GET /webhook/api/v1/empresas/agendas/horarios-livres`, `create_appointment` -> `POST /webhook/api/v1/empresas/agendas/agendamentos`; and read the slots of `free_slots` from `dados` instead of `horarios` (observed against the real ERP: the empty-day answer is `sucesso: true` with `dados: []`, so one key serves both cases). Update `free_slots.json`, `free_slots_empty.json` and every spec that stubs the old paths or the `horarios` key (supersedes the `horarios` envelope restored by T071 and the `free_slots_empty.json` description in T081).
