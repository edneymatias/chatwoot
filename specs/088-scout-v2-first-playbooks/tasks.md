---
description: "Task list for Scout V2 First-Cut Playbooks and Degradation on Missing Capabilities"
---

# Tasks: Scout V2 First-Cut Playbooks and Degradation on Missing Capabilities

**Input**: Design documents from `/specs/088-scout-v2-first-playbooks/`  
**Prerequisites**: `plan.md`, `spec.md`, `data-model.md`, `research.md`, `contracts/`, `quickstart.md`  
**Tests**: TDD is MANDATORY (constitution Principles VI–VIII). Inside every phase, the test tasks come first and are observed failing for the missing behavior (the "Run … confirm red" task) before any implementation task of that phase starts. Test runs are targeted (Principle IX).

**Organization**: Tasks are grouped by the plan's functional slices (plan.md Constitution Check VIII), which follow the user stories. The qualified outcome of US1 (`qualificado`, US1-AS9/AS10/AS14) ships in US3 together with `agendamento`, because boot validation rejects a transition to a playbook that does not exist yet (`Playbook::Validator#validate_transition_target`).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel with the other [P] tasks of the same group (different files, no dependency between them). Any prerequisite outside the group is stated in the description.
- **[Story]**: Which user story this task belongs to (e.g., `[US1]`, `[US2]`, `[US3]`)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Migration & Fixture Cutovers)

**Purpose**: Add the column and move the 085/087 mechanism specs off the shipped catalog before it changes (research §12). Cutovers are contract changes, not red-first claims.

- [X] T001 Create database migration `db/migrate/21260928000000_add_completed_playbooks_to_ichatr_scout_conversation_states.rb` adding `completed_playbooks` (`jsonb`, default `[]`, null `false`), reversible
- [X] T002 Run `docker compose exec rails bundle exec rails db:migrate` and `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rails db:migrate`; confirm the `db/schema.rb` diff is exactly the new column line plus the schema version, with no `n8n` or other foreign objects (quickstart §0; clean the dev DB instead of committing a contaminated schema)
- [X] T003 Create the frozen pre-088 fixture `custom/spec/fixtures/scout_v2/qualificacao_procedure.md` (copy of the current shipped `qualificacao.md`: `when_state [opportunity_open, pending_required_fields]`, `tools [manage_opportunity]`, no exits)
- [X] T004 [P] Cutover `custom/spec/services/custom/scout_v2/turn_runner_spec.rb` (after T003): add one `around` hook to `describe '#perform'` that runs every example with `SCOUT_V2_PLAYBOOKS_DIR` set to a `Dir.mktmpdir` holding the frozen fixture (the argument-less `Loader.load_all` calls in 'includes every loaded catalog playbook under [Playbook Index]' and 'executes open_playbook during the turn…' then read it); in 'dynamically reflects newly added playbooks in [Playbook Index] across subsequent turns', which builds its own tmp catalog, copy the frozen fixture instead of `custom/playbooks/qualificacao.md`
- [X] T005 [P] Cutover `custom/spec/requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb` (after T003): the two `around` blocks that build `scout_v2_procedure_only_catalog` and `scout_v2_fixture_catalog` copy the frozen fixture instead of the shipped `qualificacao.md`
- [X] T006 [P] Cutover `custom/spec/jobs/custom/scout/process_message_job_spec.rb` (after T003): run the context 'with the real Scout V2 engine and exits (US1)' inside the frozen-fixture dir (an `around` hook, as the US2–US4 contexts already do)
- [X] T007 Run the three cutover specs on the unchanged engine; confirm green (the cutover alone changes no behavior)

---

## Phase 2: Foundational — storage, snapshot, conditions, validation (slice 0)

**Purpose**: Everything every story reads: the completed list on the model, the snapshot members, the five conditions, and boot validation of arguments, business facts and markers.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

### Tests (write first)

- [X] T008 [P] Model examples in `custom/spec/models/scout_conversation_state_spec.rb`: `record_transition!(…, completed:)` success adds the name to `completed_playbooks` in the same write (set semantics, insertion order kept, idempotent); the limit-refused branch ignores `completed:`; `record_terminal_exit!(…, completed:)` adds the name; `completed: nil` adds nothing; existing columns unchanged
- [X] T009 [P] Snapshot examples in `custom/spec/services/custom/scout_v2/routing_snapshot_spec.rb`: `completed_playbooks` and `satisfied_business_facts` members, frozen, default `[]`
- [X] T010 [P] Builder examples in `custom/spec/services/custom/scout_v2/routing_snapshot/builder_spec.rb`: no active opportunity → `pending_fields` are the scout's qualification requirement keys (L120–123 contract change, FR-009b); `completed_playbooks` read from the state row; `satisfied_business_facts == []` (L216–218)
- [X] T011 [P] `custom/spec/services/custom/scout_v2/predicates/contact_identity_incomplete_spec.rb`: placeholder name (same detection as `ContactIdentityService`), blank phone, both, neither; reads contact data only (FR-006)
- [X] T012 [P] `custom/spec/services/custom/scout_v2/predicates/contact_has_phone_spec.rb` (FR-008)
- [X] T013 [P] `custom/spec/services/custom/scout_v2/predicates/in_qualification_spec.rb`: no opportunity → true; open with pending fields → true; open without pending → false; closed → false (FR-009b)
- [X] T014 [P] `custom/spec/services/custom/scout_v2/predicates/opportunity_in_stage_spec.rb`: each role (`qualified`, `unqualified`, `initial`) matches only its configured stage; no opportunity → false (FR-007)
- [X] T015 [P] `custom/spec/services/custom/scout_v2/predicates/playbook_not_completed_spec.rb`: true when the name is absent from `completed_playbooks`, false when present (FR-009)
- [X] T016 [P] Validator examples in `custom/spec/services/custom/scout_v2/playbook/validator_spec.rb` (contracts/state_conditions.md "Boot validation", one example per row): unknown condition name, argument-taking condition without argument (bare `opportunity_in_stage`), argument given to a condition that takes none (`contact_has_phone: x`), invalid stage role, `playbook_not_completed` naming a playbook not in the catalog, `playbook_not_completed` naming a situational playbook of the catalog, unknown business fact (FR-020), empty `[[depends:]]` marker, marker naming something outside the playbook's own `requires`/`needs` — all reported in one `ValidationError` (FR-009a)
- [X] T017 Run T008–T016; confirm each example fails for the missing behavior (not for a load or syntax error)

### Implementation

- [X] T018 Add `completed:` to `record_transition!` (success branch only) and `record_terminal_exit!` in `custom/app/models/scout_conversation_state.rb`
- [X] T019 [P] Add `completed_playbooks` and `satisfied_business_facts` to `custom/app/services/custom/scout_v2/routing_snapshot.rb`
- [X] T020 [P] Extract `RoutingSnapshot::PendingFields.call(scout:, opportunity:)` into `custom/app/services/custom/scout_v2/routing_snapshot/pending_fields.rb`, returning the scout's qualification requirement keys when `opportunity` is nil
- [X] T021 Update `custom/app/services/custom/scout_v2/routing_snapshot/builder.rb` to fill the two new members and call `PendingFields` (after T019, T020)
- [X] T022 [P] Implement `custom/app/services/custom/scout_v2/predicates/contact_identity_incomplete.rb`
- [X] T023 [P] Implement `custom/app/services/custom/scout_v2/predicates/contact_has_phone.rb`
- [X] T024 [P] Implement `custom/app/services/custom/scout_v2/predicates/in_qualification.rb` (composes `OpportunityOpen` and `PendingRequiredFields`)
- [X] T025 [P] Implement `custom/app/services/custom/scout_v2/predicates/opportunity_in_stage.rb` (`ROLES`)
- [X] T026 [P] Implement `custom/app/services/custom/scout_v2/predicates/playbook_not_completed.rb`
- [X] T027 Register the five conditions, the `ARGUMENTS` map and `argument_kind` in `custom/app/services/custom/scout_v2/predicates/registry.rb` (after T022–T026)
- [X] T028 [P] Create `custom/app/services/custom/scout_v2/business_facts/catalog.rb` (`politica_reagendamento`, `known?` shape of `Capabilities::Catalog`)
- [X] T029 Implement `custom/app/services/custom/scout_v2/playbook/dependency_rules.rb` (condition arguments, `requires`, `needs`, markers) (after T027, T028)
- [X] T030 Delegate `when_state`/`requires`/`needs`/marker checks from `custom/app/services/custom/scout_v2/playbook/validator.rb` to `DependencyRules` (after T029)
- [X] T031 Run T008–T016, the cutover specs and `spec/config/scout_v2_playbooks_spec.rb`; confirm green

**Checkpoint**: Storage, snapshot, conditions and validation are in place; the shipped catalog is still the pre-088 one.

---

## Phase 3: User Story 1 — Identification and qualification (Priority: P1) (slice 1)

**Goal**: `identificacao` and `qualificacao` (qualification requirements context, opportunity creation on commercial interest, `desqualificado`, escalation), completion marking in every exit, and rendered playbook content (`content_for`) everywhere guidance reaches the model. The qualified outcome (`qualificado` → `agendamento`, US1-AS9/AS10/AS14) lands in Phase 5.

**Independent Test**: Scripted multi-turn playground and inbox conversations on the shipped catalog: `identificacao` pinned by state, scoped to `update_contact`, answers recorded, `exit_identificado` pins `qualificacao` and marks `identificacao` completed, later turns never re-pin it; `qualificacao` scoped to `manage_opportunity`, pinned by state without an opportunity, `desqualificado` and escalation mark it completed.

### Tests for User Story 1 (write first) ⚠️

- [X] T032 [P] [US1] Shipped-catalog examples in `custom/spec/services/custom/scout_v2/playbook/catalog_spec.rb` for `identificacao` and `qualificacao` (contracts/playbook_catalog.md): `when_state` including `playbook_not_completed` naming itself (FR-028c), tools `[update_contact]` / `[manage_opportunity]`, exit `identificado` (transition → `qualificacao`), exit `desqualificado` (terminal, unqualified role, `motivo`), priority `identificacao` above `qualificacao` (FR-003), no private-note tool (FR-004), `qualificacao` trigger does not require an open opportunity (FR-011b), catalog validates clean
- [X] T033 [P] [US1] New `custom/spec/services/custom/scout_v2/playbook/content_builder_spec.rb`: pending-fields block appended when `when_state` reads `in_qualification` or `pending_required_fields` (scout requirements when there is no opportunity); missing-contact-data block (`nome` with the placeholder warning, `telefone`) when it reads `contact_identity_incomplete`; no block for situational playbooks; body verbatim otherwise
- [X] T034 [P] [US1] New `custom/spec/services/custom/scout_v2/turn_scope_spec.rb` with a real `scout.llm_chat`: `setup_initial_tools!(…, ctx:)` keeps the turn's snapshot; `content_for(playbook)` returns the `ContentBuilder` rendering for that snapshot
- [X] T035 [US1] Cutover in `custom/spec/services/custom/scout_v2/turn_runner_spec.rb` (after T004), example 'executes open_playbook during the turn, registering declared tools on live chat, returning body, and persisting trigger activation': remove the `qualificacao_body` load and the `expect(open_pb_tool_result).to eq(body: qualificacao_body)` expectation, and change `expect(open_pb_call[:result]).to eq(body: qualificacao_body)` to `expect(open_pb_call[:result]).to eq(open_pb_tool_result)` (the 085 parity between the recorded and the returned result); keep its tool-registration and trigger-activation expectations. The example runs with `scout.llm_chat` stubbed and `instance_double(RubyLLM::Chat)`, so the 088 rendered-result contract is not written there (P…
- [X] T035a [P] [US1] Cutover `custom/spec/services/custom/scout_v2/exits/exit_tool_spec.rb` and `custom/spec/services/custom/scout_v2/tools/open_playbook_spec.rb` (contract change: `TurnScope#content_for` reads the turn snapshot, which only `setup_initial_tools!(…, ctx:)` provides — contracts/turn_assembly.md §4, data-model.md "Turn scope"): give each spec's scope its snapshot through `setup_initial_tools!(decision:, ctx:, scout:, conversation:, openable:)` with a real `RoutingSnapshot::Builder.call(conversation:, catalog:)` snapshot and the real routing decision for it, instead of hand-added baselines; rewrite the registered-tool expectations that change because the production baseline also registers `exit_handoff` (open_playbook_spec L228, L238); keep the…
- [X] T036 [P] [US1] New `custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb` (shipped catalog): US1-AS1–AS6, AS8 (offered: `manage_opportunity` + `exit_desqualificado`, no `update_contact`; `exit_qualificado` is added in T064), AS11, AS13, AS15–AS18; the `exit_identificado` tool result carries `qualificacao`'s rendered body with its pending-fields block (US1-AS4); FR-028c re-opening (real-name contact with phone, open opportunity with a pending field, `completed_playbooks == ['qualificacao']` on the row → nothing pinned by state; scripted `open_playbook('qualificacao')` returns the rendered body plus the pending-fields block and pins it with reason `trigger`); preemption edge (`qualificacao` pinned for a contact with real name …
- [X] T037 [P] [US1] New shipped-catalog real-engine context in `custom/spec/jobs/custom/scout/process_message_job_spec.rb`: US1-AS7 (new conversation for the same incomplete contact pins `identificacao`; B's list `[]`, A's unchanged), US1-AS12 (`exit_handoff` with `qualificacao` pinned → transferred, `completed_playbooks ∋ qualificacao`) and escalation with nothing in effect (contact with a real name and a phone, open opportunity without pending fields so nothing matches by state, no opening, `exit_handoff` → transferred, `completed_playbooks == []`, FR-026); in the existing 087 fixture context 'with Scout V2 declared exits on inbox (US2)', the example 'verifies US2-AS6 and US1-AS7: declared escalation transfers with note reason in declaration order and set…
- [X] T038 [US1] Run T032–T037 and T035a; confirm each fails for the missing behavior

### Implementation for User Story 1

- [X] T039 [P] [US1] Implement `custom/app/services/custom/scout_v2/playbook/contact_gaps_formatter.rb`
- [X] T040 [US1] Implement `custom/app/services/custom/scout_v2/playbook/content_builder.rb`: rendered body plus context blocks by `when_state` (markers and notice come in T070) (after T039)
- [X] T041 [US1] Update `custom/app/services/custom/scout_v2/turn_scope.rb`: `setup_initial_tools!(…, ctx:)` and `content_for` (after T040)
- [X] T042 [US1] Update `TurnRunner#build_instructions` in `custom/app/services/custom/scout_v2/turn_runner.rb`: pinned procedure content via `TurnScope#content_for` (replaces body + `PendingFieldsFormatter`); pass `ctx:` to `setup_initial_tools!` (after T041)
- [X] T043 [P] [US1] Update `custom/app/services/custom/scout_v2/tools/open_playbook.rb`: procedure and takeover results return `{ body: scope.content_for(playbook) }` (after T041)
- [X] T044 [P] [US1] Update `custom/app/services/custom/scout_v2/exits/transition.rb`: pass `completed: @scope.active_procedure_name` (captured before the target becomes active) and return `@scope.content_for(target)` (after T018, T041)
- [X] T045 [P] [US1] Update `custom/app/services/custom/scout_v2/exits/terminal.rb`: pass `completed: @scope.active_procedure_name` (after T018)
- [X] T046 [P] [US1] Update `custom/app/services/custom/scout_v2/exits/escalation.rb`: pass `completed: @scope.active_procedure_name` in the inbox and playground branches (after T018)
- [X] T047 [P] [US1] Create `custom/playbooks/identificacao.md` per contracts/playbook_catalog.md, FR-002, FR-003, FR-010 (body ported from research §9 sources)
- [X] T048 [P] [US1] Rewrite `custom/playbooks/qualificacao.md` per contracts/playbook_catalog.md, FR-002, FR-003, FR-011, FR-011b — `when_state [in_qualification, playbook_not_completed: qualificacao]`, exit `desqualificado`, outcome guidance for `desqualificado` and `exit_handoff`; the `qualificado` exit and its guidance are added in T069
- [X] T049 [US1] Run T032–T037, T035a and the cutover specs; confirm green

**Checkpoint**: Validation point, not a release point — until Phase 5, `qualificacao` has no qualified outcome. The feature ships after Phase 5.

---

## Phase 4: User Story 2 — Three situational playbooks (Priority: P2) (slice 2)

**Goal**: `fora_de_prospeccao`, `duvida_comercial`, `pausa`: no data-changing tools, never pinned by state, opening never changes the pinned procedure, which resumes next turn.

**Independent Test**: With `qualificacao` (or `identificacao`) pinned, open each situational playbook mid-turn; check offered tools, outcome (transfer for out-of-scope, none otherwise), unchanged stored procedure, same pending fields next turn, and that routing never pins any of the three.

### Tests for User Story 2 (write first) ⚠️

- [X] T050 [P] [US2] Shipped-catalog examples in `custom/spec/services/custom/scout_v2/playbook/catalog_spec.rb`: the three situational playbooks have no `when_state`, tools, `requires`, `needs` or exits; `fora_de_prospeccao` has the highest priority of the catalog; none declares the private-note tool; the `duvida_comercial` and `fora_de_prospeccao` triggers each exclude the other's situation (FR-005, US2-AS7)
- [X] T051 [P] [US2] Exhaustive routing example in `custom/spec/services/custom/scout_v2/router_spec.rb` on the shipped catalog (US2-AS6, SC-004): first assert the three situational names are in the catalog (so it cannot pass vacuously), then the product of identity × phone × opportunity (none / open-pending / open-complete / each role) × completed subsets never yields a situational winner
- [X] T052 [P] [US2] In `custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb` (SC-002, SC-003), with `qualificacao` and `identificacao` pinned: US2-AS2–AS5, each opening leaving `completed_playbooks` unchanged (FR-026), the `duvida_comercial`/`pausa` opening results containing their contract key phrases and none of their "must not" strings (FR-013, FR-014); after the `pausa` opening, as after the `duvida_comercial` one, the next turn is routed to the same procedure with the same activation reason and pending block (SC-003); `pausa` opened with nothing pinned leaves nothing pinned (edge case); US2-AS7 at the entry point — the provider request's `[Playbook Index]` lines for `duvida_comercial` and `fora_de_prospeccao` each name the …
- [X] T053 [P] [US2] US2-AS1 in `custom/spec/jobs/custom/scout/process_message_job_spec.rb` with `identificacao` and with `qualificacao` pinned: `open_playbook('fora_de_prospeccao')` then `exit_handoff` → only baseline after the opening, the opening result contains the `fora_de_prospeccao` key phrases and none of its "must not" strings (FR-012), transferred, `completed_playbooks ∋` the pinned procedure (the `agendamento` variant is in T065)
- [X] T054 [US2] Run T050–T053; confirm each fails for the missing behavior

### Implementation for User Story 2

- [X] T055 [P] [US2] Create `custom/playbooks/fora_de_prospeccao.md` per contracts/playbook_catalog.md, FR-002, FR-003, FR-005, FR-012
- [X] T056 [P] [US2] Create `custom/playbooks/duvida_comercial.md` per contracts/playbook_catalog.md, FR-002, FR-003, FR-005, FR-013
- [X] T057 [P] [US2] Create `custom/playbooks/pausa.md` per contracts/playbook_catalog.md, FR-002, FR-003, FR-014
- [X] T058 [US2] Run T050–T053 and the Phase 3 specs; confirm green

**Checkpoint**: Situational handling works on top of the US1 procedures.

---

## Phase 5: User Story 3 — Scheduling degrades visibly (Priority: P3) (slice 3)

**Goal**: `agendamento` with `[[depends: …]]` markers, `qualificacao`'s `qualificado` exit, pending-step rendering, exit withholding while `requires` are unsatisfied, and the turn-completion unsatisfied-items record in `unsatisfied_flags` and trace metadata.

**Independent Test**: A contact with a phone and an opportunity in the qualified stage: `agendamento` pinned by state, dependent steps shown as `PENDENTE`, own exits withheld (`exit_handoff` offered), the record lists the three items in the row and the trace; with satisfied lists (component level, FR-019 design property) the markings and withholding disappear with the same file.

### Tests for User Story 3 (write first) ⚠️

- [X] T059 [P] [US3] Shipped-catalog examples in `custom/spec/services/custom/scout_v2/playbook/catalog_spec.rb`: `agendamento` (`when_state [opportunity_in_stage: qualified, contact_has_phone, playbook_not_completed: agendamento]`, no tools, `requires [scheduling, customer_registry]`, `needs [politica_reagendamento]`, terminal `agendado(inicio)`/`sem_horario(motivo)` with no stage role, and a raw body carrying exactly the five markers contracts/playbook_catalog.md lists — `[[depends: customer_registry]]` once, `[[depends: scheduling]]` three times, `[[depends: politica_reagendamento]]` once — no other marker and no literal `PENDENTE`, FR-015); `qualificacao`'s `qualificado` (transition → `agendamento`, qualified role); whole catalog (needs Phase 4's situati…
- [X] T060 [P] [US3] Marker examples in `custom/spec/services/custom/scout_v2/playbook/content_builder_spec.rb`: (a) mechanism, on an in-spec playbook with `requires`/`needs` and markers — unsatisfied → `(PENDENTE — indisponível: …)` on each marked step plus one `PENDING_STEPS_NOTICE`; satisfied lists → markers stripped, no notice (FR-016); (b) the unmodified shipped `agendamento.md` rendered with empty and with full satisfaction lists (FR-019)
- [X] T061 [P] [US3] Withholding examples in `custom/spec/services/custom/scout_v2/turn_scope_spec.rb`: (a) on an in-spec playbook with `requires` and declared exits — `actions_for` omits the declared exits while any `requires` is unsatisfied and keeps `exit_handoff`; `needs` alone withholds nothing (FR-017); (b) the shipped `agendamento`: `exit_agendado`/`exit_sem_horario` withheld with empty lists, offered with satisfied lists (FR-019)
- [X] T062 [P] [US3] New `custom/spec/services/custom/scout_v2/unsatisfied_items_spec.rb`: (a) on an in-spec procedure — `.call` returns the record for the last procedure in effect (`procedure`, fresh `pending_fields`, `unmet_requires`, `unmet_needs`); no procedure → `procedure: nil` and empty lists; (b) the shipped `agendamento` with satisfied lists → empty lists (FR-019). The span attribute set by `.trace!` is asserted at the entry point (T066); persistence by T063 and the entry-point examples
- [X] T063 [P] [US3] `record_unsatisfied_items!` example in `custom/spec/models/scout_conversation_state_spec.rb`: overwrites `unsatisfied_flags` with the given record
- [X] T064 [P] [US3] In `custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb`: US3-AS1–AS7 (SC-005), with the system text of the `agendamento` turn containing every `agendamento` key phrase (including `chame exit_handoff neste mesmo turno`), exactly five `(PENDENTE — indisponível: …)` lines and none of its "must not" strings (FR-015, FR-016); US1-AS8 now also offers `exit_qualificado`, and the system text of every `qualificacao` turn now also contains `exit_qualificado` and `siga no mesmo turno`; US1-AS9, AS10, AS14 and US3-AS2 (qualified outcome with and without a phone, SC-006), each asserting `completed_playbooks` on the sandbox row (FR-029), and each asserting that the `exit_qualificado` tool result carries `agendamento`'s re…
- [X] T065 [P] [US3] In `custom/spec/jobs/custom/scout/process_message_job_spec.rb`: US3-AS8; US3-AS9 / SC-010 (escalate with `agendamento` in effect, hand back, "obrigado" → nothing pinned, no new transfer); US2-AS1 with `agendamento` pinned, where the provider request after the opening carries no `PENDENTE` text (edge case); fail-safe edge (empty final output with `qualificacao` pinned → fail-safe transfer, `completed_playbooks` unchanged, `active_playbook` still `qualificacao`, `unsatisfied_flags` written for `qualificacao` — FR-018, FR-026); a turn stopped before the model call — quota exhausted and missing API key — leaves `unsatisfied_flags` untouched (FR-018); a Gemini HTTP error that makes `chat.ask` raise writes no record (contracts/turn_assembly.md…
- [X] T066 [US3] Trace metadata at the entry point (plan Constitution Check VI/VII, research §11), in a new trace context of `custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb` (after T064, same file): real `InstallationConfig` rows (`OTEL_PROVIDER=langfuse`, `LANGFUSE_BASE_URL`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`), `SimpleSpanProcessor(InMemorySpanExporter)` on the provider `OpentelemetryConfig.initialize!` configures, Langfuse OTLP endpoint stubbed with WebMock, previous global provider and `OpentelemetryConfig.reset!` restored afterwards. Both instrumentation layers name their span `llm.scout_v2.turn_runner`: the agent-session span is the parent, the LLM-call span its child (`parent_span_id == agent span's span_id`…
- [X] T066a [US3] FR-018 cutover of the 085/087 state assertions (after T065, same job spec file; contract change — spec FR-018 supersedes "writes nothing", research §12 cutover rule). In `custom/spec/jobs/custom/scout/process_message_job_spec.rb`: 'verifies US1-AS8 variant (a): human takes over mid-turn so escalation is refused and writes nothing' and 'verifies US1-AS8 variant (b): blank reason refuses escalation and leaves state identical' (row absent today); 'verifies US1-AS8 with declared escalation: invalid data refuses escalation and leaves state identical', 'verifies US3-AS4: customer picks an offered option and no exit is called…', 'verifies US1-AS8 stage variant (a): stage checks fail…' and 'verifies US1-AS8 stage variant (b): human takes over mid-t…
- [X] T067 [US3] Run T059–T066a; confirm each fails for the missing behavior: the (a) examples of T060–T062 and T063, T066 for the missing rendering/withholding/record/trace; T066a because no turn writes `unsatisfied_flags` yet; T059, T064, T065 and the (b) examples because `agendamento.md` is not in the catalog yet (the missing FR-015/FR-019 deliverable) — never for a load or syntax error in the spec itself

### Implementation for User Story 3

- [X] T068 [P] [US3] Create `custom/playbooks/agendamento.md` with `[[depends: …]]` markers per contracts/playbook_catalog.md, FR-002, FR-003, FR-015
- [X] T069 [US3] Add the `qualificado` exit (transition → `agendamento`, qualified stage role) and its outcome guidance to `custom/playbooks/qualificacao.md` per FR-011, FR-011a (after T068 — boot validation needs the target)
- [X] T070 [P] [US3] Add marker rendering and `PENDING_STEPS_NOTICE` to `custom/app/services/custom/scout_v2/playbook/content_builder.rb`
- [X] T071 [P] [US3] Withhold declared exits in `TurnScope#actions_for` while any `requires` is unsatisfied, in `custom/app/services/custom/scout_v2/turn_scope.rb`
- [X] T072 [P] [US3] Implement `record_unsatisfied_items!` in `custom/app/models/scout_conversation_state.rb`
- [X] T073 [P] [US3] Implement `custom/app/services/custom/scout_v2/unsatisfied_items.rb`: `.call` builds the record (uses `RoutingSnapshot::PendingFields` with a fresh `reload_active_opportunity`); `.trace!` builds it, sets `langfuse.trace.metadata.unsatisfied_flags` on the current span and returns it — no write (contracts/turn_assembly.md §6)
- [X] T074 [US3] Update `TurnRunner#execute_chat` in `custom/app/services/custom/scout_v2/turn_runner.rb`: inside `instrument_agent_session`, right after `instrument_llm_call` returns, keep `UnsatisfiedItems.trace!`'s record while the block still returns the response; after the block returns and before the final-reply/fail-safe decision, persist it with `ScoutConversationState.for_conversation(conversation).record_unsatisfied_items!` (never inside the block — a raise there would re-run the whole turn, research §7); drop the start-of-turn `unsatisfied_flags` metadata key (after T072, T073)
- [X] T075 [US3] Run the full quickstart §1 targeted list; confirm green

**Checkpoint**: All three user stories are complete and verified; the feature is shippable.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T076 Boot validation of the shipped catalog (quickstart §3): `Validator.call!(Loader.load_all)` prints `ok`; a broken copy under `SCOUT_V2_PLAYBOOKS_DIR` (`needs: [politica_inexistente]`) raises `Unknown business fact: politica_inexistente`
- [X] T077 v1 regression (FR-024, SC-008, quickstart §2): v1 specs green and `git diff --stat "$(git merge-base ichatr-main HEAD)" -- custom/app/services/custom/scout/` lists no file (covers committed and uncommitted changes of the branch)
- [X] T078 Deliberate-mutant checks from quickstart §5: each mutation turns its listed specs red; revert each mutation
- [X] T079 RuboCop on the quickstart §6 paths: zero offenses, no `.rubocop_todo.yml` change
- [X] T080 Manual playground pass with the user (quickstart §4, SC-007): all six playbooks show the expected activation reason in the Langfuse trace; report observations in the session/PR description (no log file)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none.
- **Foundational (Phase 2)**: after Setup (column migrated, mechanism specs on the frozen fixture). Blocks all stories.
- **US1 (Phase 3)**: after Foundational.
- **US2 (Phase 4)**: after US1 (resumption and the `fora_de_prospeccao` escalation are proven on US1's procedures; `completed:` marking lands in US1).
- **US3 (Phase 5)**: after US1 (`qualificacao.md`, `content_for`, completion marking) and US2: T059's whole-catalog assertions (exactly six playbooks, full priority order, no private-note tool anywhere) and T065's US2-AS1 `agendamento` variant need Phase 4's situational files.
- **Polish (Phase 6)**: after all stories.

### Within Each Phase

- Test tasks first → "Run … confirm red" task → implementation tasks → "Run … confirm green" task.
- Playbook files that are transition targets before the playbooks that declare the transition (T068 before T069).
- Services before runner integration (T041 before T042; T072/T073 before T074).

### Parallel Opportunities

- **Setup**: T004–T006 after T003.
- **Foundational**: tests T008–T016; then T019/T020, T022–T026, T028.
- **US1**: tests T032–T034, T035a, T036, T037; then T039, T047, T048; then T043–T046 after T041.
- **US2**: tests T050–T053; then T055–T057.
- **US3**: tests T059–T065; then T066 and T066a (after T064/T065, same files); then T068, T070–T073.

---

## Parallel Example: User Story 1

```bash
# Tests first, in parallel:
Task: "Shipped-catalog examples for identificacao/qualificacao in custom/spec/services/custom/scout_v2/playbook/catalog_spec.rb"
Task: "Context-block examples in custom/spec/services/custom/scout_v2/playbook/content_builder_spec.rb"
Task: "content_for examples in custom/spec/services/custom/scout_v2/turn_scope_spec.rb"
Task: "exit_tool_spec/open_playbook_spec snapshot cutover in custom/spec/services/custom/scout_v2/{exits,tools}/"
Task: "US1 acceptance in custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb"
Task: "US1-AS7/AS12 in custom/spec/jobs/custom/scout/process_message_job_spec.rb"

# After the red run, playbook authoring in parallel:
Task: "Create custom/playbooks/identificacao.md"
Task: "Rewrite custom/playbooks/qualificacao.md (without qualificado)"
```

## Parallel Example: User Story 2

```bash
Task: "Situational catalog examples in custom/spec/services/custom/scout_v2/playbook/catalog_spec.rb"
Task: "Exhaustive routing example in custom/spec/services/custom/scout_v2/router_spec.rb"
Task: "US2-AS2–AS5 in custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb"
Task: "US2-AS1 in custom/spec/jobs/custom/scout/process_message_job_spec.rb"
```

## Parallel Example: User Story 3

```bash
Task: "agendamento/qualificado/whole-catalog examples in custom/spec/services/custom/scout_v2/playbook/catalog_spec.rb"
Task: "Marker examples in custom/spec/services/custom/scout_v2/playbook/content_builder_spec.rb"
Task: "Withholding examples in custom/spec/services/custom/scout_v2/turn_scope_spec.rb"
Task: "New custom/spec/services/custom/scout_v2/unsatisfied_items_spec.rb"
Task: "record_unsatisfied_items! example in custom/spec/models/scout_conversation_state_spec.rb"
Task: "US3 and qualified-outcome acceptance in custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb"
Task: "US3-AS8/AS9, fail-safe and quota examples in custom/spec/jobs/custom/scout/process_message_job_spec.rb"
```

---

## Implementation Strategy

1. Setup → Foundational: column, conditions, validation; mechanism specs isolated from the shipped catalog.
2. US1: identification and qualification with completion marking and rendered content — validation checkpoint.
3. US2: situational playbooks — validation checkpoint.
4. US3: scheduling, qualified outcome, degradation and unsatisfied-items record — the feature becomes shippable here (a qualified lead is transferred in the same turn, as in v1).
5. Polish: boot check, v1 regression, mutants, lint, manual playground pass.

---

## Notes

- `[P]` tasks = different files, no dependencies inside their group
- `[Story]` label (`[US1]`, `[US2]`, `[US3]`) maps task to specific user story for traceability; US1-AS8 (offered exit), AS9, AS10, AS14 are verified in Phase 5 with `qualificado`
- `turn_runner_spec.rb` keeps its pre-existing `fake_chat`/`scout.llm_chat` doubles in the untouched 085/087 mechanism examples (Principle VI restraint) and receives no 088 assertion: T035 moves its `open_playbook` result-body expectation to T036's re-opening example, and T066 moves the trace assertions to the request spec
- Strict adherence to Constitution Principles: Upstream Compatibility (I), Smallest Change (II), TDD (VI), Observable Behavior (VII), Functional Slices (VIII), Surgical Execution (IX)
- Never create intermediate accounting files or cycle logs
- Commit after each task or logical group only upon explicit user approval

---

## Phase 7: Convergence

- [X] T081 Add a chained job-spec example (`custom/spec/jobs/custom/scout/process_message_job_spec.rb`) that pins `qualificacao` by state, scripts `exit_qualificado` then `exit_handoff` in the same turn, and asserts `completed_playbooks` contains both `qualificacao` and `agendamento`, `unsatisfied_flags` attributes the three unsatisfied items to `agendamento`, and `last_exit == 'handoff'`; extend the T066 trace context in `custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb` with the same chained scenario, asserting `metadata.playbook == 'qualificacao'` and `metadata.activation_reason == 'state'` alongside the trace `unsatisfied_flags` attribute naming `agendamento` per US3-AS8 (missing; Constitution Principle VI requires an entry-point test per acceptance scenario)
- [X] T082 Add request-level assertions in `custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb` proving US3-AS3 (a scripted turn against the real `agendamento.md` `when_state`, with no phone on record and separately with the opportunity outside the qualified stage, confirming `agendamento` is not pinned by state) and US3-AS5 (a `functionDeclarations` tool-name assertion confirming `exit_agendado`/`exit_sem_horario` are absent while `exit_handoff` is present) per US3-AS3, US3-AS5 (missing; Constitution Principle VI — currently proven only at the unit level in `turn_scope_spec.rb` and the predicate specs, not at the real entry point)
- [X] T083 Add a request-level example in `custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb` opening `duvida_comercial` and `pausa` with `identificacao` pinned (mirroring the existing `qualificacao`-pinned US2-AS2–AS5 coverage) per US2-AS4 (partial)
- [X] T084 Update `quickstart.md` §2's v1-diff-scope note and T077's documented command to acknowledge the two 087-introduced additive members (`custom/app/services/custom/scout/handoff_service.rb#transfer!`, `custom/app/services/custom/scout/opportunity_stage_transition_service.rb#moved?`) so the literal `git diff --stat "$(git merge-base ichatr-main HEAD)" -- custom/app/services/custom/scout/` gate's expected output (currently documented as "lists no file") matches the reviewed, already-accepted state instead of appearing to show an unreviewed v1 change per T077, FR-024 (contradicts)

## Phase 8: Convergence

- [X] T085 Rewrite `custom/spec/jobs/custom/scout/process_message_job_spec.rb`'s `scout_v2` feature-flag coverage to use real `Custom::ScoutV2::TurnRunner` with WebMock-stubbed Gemini (COMPLETE: 7 examples green, T081 chained-exit example passing)
- [X] T086 Wire `Custom::ScoutV2::TurnRunner` to real `Custom::ScoutV2::TurnScope`/`Playbook::ContentBuilder` pipeline, fix Escalation section placement, all 326 Scout V2 tests passing (COMPLETE)
- [X] T087 Compute `TurnRunner`'s trace-metadata `unsatisfied_flags` (`metadata_for`/`instrumentation_params`, called before `chat.ask` from the turn-start `decision.playbook`) from the same post-turn `active_procedure_name` source `exits/escalation.rb` already uses for the conversation-state copy, not from the fixed pre-turn routing decision — a mid-turn transition (`qualificado` → `agendamento`) leaves the trace's `unsatisfied_flags.procedure` naming the turn-start playbook instead of the transition target, contradicting FR-018's 'last procedure in effect' rule and diverging from the conversation-state copy; reproduced by the currently-failing 'verifies T081: chained exits…' example (`playground_first_cut_catalog_spec.rb:819`, expected `'agendamento'`, got `'qualificacao'`) per FR-018, US3-AS8 (contradicts)
- [X] T088 Call `ScoutConversationState#record_unsatisfied_items!` from `exits/transition.rb` and `exits/terminal.rb`, and from a plain turn completion with a pinned procedure and no exit fired (today it is called only from `exits/escalation.rb:50,70`), so `unsatisfied_flags` is refreshed on every turn completion as FR-018 requires, not only on an escalation exit — the US3-AS4/AS6 baseline scenario ('scheduling in effect, capabilities unsatisfied, turn completes normally') never persists a record today per FR-018, US3-AS4, US3-AS6, SC-005 (missing)
- [X] T089 Implement the infrastructure fail-safe transfer for an unreadable or empty final model output for the v2 engine (spec.md Edge Cases: 'a turn ends in the infrastructure fail-safe transfer… it is not an exit, so no playbook is recorded as completed and the pinned procedure is left as it was'): `ProcessMessageJob#dispatch_scout_v2` currently returns silently on a blank `result[:reply]` with no handoff, no `last_exit`, and no unsatisfied-items effect (`TurnRunner#handle_infra_failure` only covers the separate pre-call quota/missing-API-key case, not an unreadable/empty post-call reply) per FR-018 (fail-safe clause), Edge Cases (missing)
- [X] T090 Update plan.md's Constitution Check table rows for Principle VI (TDD/real entry point) and Principle VII (Observable Behavior — no mocking the component under test) from `PASS` once T085/T086 land and the acceptance spec (`playground_first_cut_catalog_spec.rb`) is actually green end-to-end — today both rows claim PASS while the real-entry-point acceptance spec is 11/25 red and the cited passing coverage (`turn_scope_spec.rb`, `content_builder_spec.rb`) exercises `TurnScope`/`ContentBuilder` directly, classes production `TurnRunner` never calls, and `process_message_job_spec.rb` mocks the component under test per plan.md Constitution Check VI/VII (contradicts)
- [X] T091 Add an explicit 'nunca como fechamento do negócio' (or equivalent) clause to `custom/playbooks/qualificacao.md`'s `desqualificado`-outcome guidance (item 7) alongside its existing 'fila de revisão humana' framing — FR-011 requires both halves ('treat the unqualified stage as a human review queue, never as closing the deal') and only the first is currently present per FR-011 (partial)
- [X] T092 Strengthen the US2-AS7/FR-005 entry-point assertion in `custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb` (~line 556-568) to check for the actual exclusion-phrase content in the rendered `[Playbook Index]` (e.g. the 'isso é duvida_comercial'/'isso é fora_de_prospeccao' clauses), not only that both playbook names co-occur in a given order — the current assertion would still pass if the exclusion sentences were deleted from both playbook files per US2-AS7, FR-005 (partial)

## Phase 9: Convergence

- [X] T093 Remove (or otherwise neutralize) the tool-preservation guard in `TurnRunner#persist_state_activation_if_needed` (`custom/app/services/custom/scout_v2/turn_runner.rb`) — `return if ctx.active_playbook.present? && ctx.active_playbook.tools.present?` — which silently discards `Router.call`'s decision whenever the currently pinned playbook declares any tool, so once `identificacao` or `qualificacao` is pinned no higher-priority state match is ever persisted again; `Router#resolve_selected_playbook` (`router.rb:33-39`) already implements FR-003's priority-based preemption/persistence correctly (`winner.priority > active.priority`), so this extra guard only contradicts it. Reproduced by 'Preemption edge case pins identificacao by state when phone is removed post-qualificacao…' (`playground_first_cut_catalog_spec.rb:391`, expected `active_playbook == 'identificacao'`, got `'qualificacao'`) per FR-003, spec.md Edge Cases ("A procedure preempted by a higher-priority state match…") (contradicts)
- [X] T094 Wire `TurnRunner#build_instructions` (`custom/app/services/custom/scout_v2/turn_runner.rb`) to render the pinned procedure through `TurnScope#content_for` / `Playbook::ContentBuilder` instead of the pre-088 raw `playbook.body.strip` + `Playbook::PendingFieldsFormatter` — today `content_for` is reached only from `exits/transition.rb:58` and `tools/open_playbook.rb:40,51` (a playbook reached by transition or opened as a trigger), never for a playbook pinned by state at turn start, so FR-016's marker rendering (`(PENDENTE — indisponível: …)`, `PENDING_STEPS_NOTICE`) and FR-006's contact-gaps block never reach the model for the common case. Reproduced by 'US1-AS3: system text of identificacao turn contains all asserted key phrases…' (`playground_first_cut_catalog_spec.rb:139`, expects `'- nome (o nome registrado é um identificador gerado pelo sistema…)'` and `'- telefone'`, gets neither) and 'verifies US3-AS1/SC-005: agendamento system text has asserted phrases, 5 pending lines, no must-nots' (`playground_first_cut_catalog_spec.rb:572`, expects 5 `(PENDENTE — indisponível: …)` lines, gets 0) per FR-016, FR-006, US1-AS3, US3-AS1, SC-005 (missing)
- [X] T095 Add the US1 inbox-entry-point acceptance coverage tasks.md T037 records as complete but `custom/spec/jobs/custom/scout/process_message_job_spec.rb` does not contain (the file's only `scout_v2`-flag examples today are a baseline dispatch smoke test and the T081 chained-exit example): US1-AS7 (a new conversation for the same incomplete contact pins `identificacao` again; a second, unrelated conversation's state is unaffected), US1-AS12 (`qualificacao` pinned by state, the assistant uses `exit_handoff`, the conversation is transferred, `completed_playbooks` includes `qualificacao`), and the FR-026 zero-completed escalation scenario (a contact with a real name and a phone, an open opportunity with no pending fields so nothing matches by state, no playbook opened, `exit_handoff` → transferred, `completed_playbooks == []`) — per plan.md's Complexity Tracking, `ProcessMessageJob#perform` is the only entry point that can exercise these inbox-only effects (Constitution Principle VI) per US1-AS7, US1-AS12, FR-026 (missing)
- [X] T096 Add the US2 inbox-entry-point coverage tasks.md T053 records as complete but is absent from `custom/spec/jobs/custom/scout/process_message_job_spec.rb`: US2-AS1, opening `fora_de_prospeccao` mid-turn once with `identificacao` pinned and once with `qualificacao` pinned — only baseline tools offered for the rest of the turn, the turn ends transferred through the built-in escalation exit, and `completed_playbooks` includes the procedure that was pinned — per plan.md's Complexity Tracking (Constitution Principle VI) per US2-AS1 (missing)
- [X] T097 Add the US3 inbox-entry-point coverage tasks.md T065/T066a record as complete but is absent from `custom/spec/jobs/custom/scout/process_message_job_spec.rb`: the US2-AS1 `agendamento`-pinned variant (opening `fora_de_prospeccao` while `agendamento` is pinned leaves no `PENDENTE` text in the follow-up provider request); US3-AS9/SC-010 (a qualified lead with a phone transferred through the built-in escalation exit while `agendamento` was in effect, a human hand-back, then "obrigado" — nothing pinned by state, no second transfer); the fail-safe edge (an unreadable/empty final model output with `qualificacao` pinned — pair with T089 — asserting a fail-safe transfer, `completed_playbooks` unchanged, `active_playbook` still `qualificacao`, and `unsatisfied_flags` written for `qualificacao`); the quota-exhausted and missing-API-key edges (`unsatisfied_flags` left untouched); a Gemini HTTP error mid-turn (writes no record); and the six named FR-018 state-assertion cutover examples T066a lists (each must assert every conversation-state column except `unsatisfied_flags`/`updated_at` unchanged, plus the FR-018 record, instead of the pre-088 "writes nothing") — per plan.md's Complexity Tracking (Constitution Principle VI) per US2-AS1, US3-AS9, SC-010, FR-018 (missing)
