---
description: "Task list for feature implementation"
---

# Tasks: Scout V2 Trigger-Based Playbook Interruption over an Active Procedure

**Input**: Design documents from `/specs/085-scout-trigger-interruption/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: MANDATORY per Constitution Principles VI–VIII. Every acceptance scenario is exercised through the real
entry point (`POST …/playground_messages`, `type: :request`) with the real engine. The only test double is WebMock at
Gemini's `generateContent` HTTP endpoint (plan.md "Testing", research.md §9). Each test task states the reason it
fails first on the code it precedes; that reason is always the absence of the behavior, never a signature mismatch.
Examples marked **guard** protect behavior that already exists and must survive (they are not claimed red-first);
they exist to kill the mutants in quickstart §6.

**Organization**: A behavior-free foundation, then two cohesive functional slices (Principle VIII):
- **Phase 2 (foundation)**: test fixtures, plus `OpenPlaybook`'s signature cutover (`openable:`, `turn_setup:`)
  together with its only production caller, with no behavior change.
- **Phase 3 (US1)**: openable set, gating, rejection, index wording, and the `TurnRunner` wiring (openable set and
  baseline computed once from the openable set, injected into `OpenPlaybook`).
- **Phase 4 (US2 + US3)**: `OpenPlaybook`'s two paths — takeover without persistence, and unchanged Path B.
  US2 and US3 are one slice because the same `takeover!` branch delivers both; US3's tests would pass without
  implementation if they were written after it.

The spec's user stories stay independently testable, but they **ship together**: US1 alone is not releasable (spec
Assumptions).

**Terms**:
- **Pinned** = `decision.playbook.present?` (spec Key Entity "Pinned Procedure": a fresh state match, or a stored pin
  of either `activation_reason`).
- **Path A** = opening a situational playbook (`when_state.blank?`) → takeover, no state write.
- **Path B** = opening a procedure playbook (`when_state.present?`, only reachable with nothing pinned) → Brief 04's
  additive tools + `trigger` persisted.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task in the same phase)
- **[Story]**: User story the task delivers (US1, US2, US3)

## Shared test fixtures (referenced below)

- **Fixture catalog** (request spec). Built inside an `around` hook, following the existing pattern at
  `turn_runner_spec.rb:221-224`:
  - `Dir.mktmpdir` + `FileUtils.cp` of the shipped `custom/playbooks/qualificacao.md` (a `when_state` procedure,
    `tools: [manage_opportunity]`, priority 10);
  - inline `File.write` of two situational fixtures, full frontmatter (`IndexBuilder` calls `pb.trigger.squish`, so
    `trigger:` is required):
    - `pausa.md`: `name: pausa`, `title: Pausa solicitada`, `priority: 20`,
      `trigger: O cliente pede para pausar ou continuar a conversa mais tarde.`, no `tools:`; body
      `## Passos\n1. Confirme a pausa com gentileza.`;
    - `duvida_comercial.md`: `name: duvida_comercial`, `title: Dúvidas Comerciais`, `priority: 5`,
      `trigger: O cliente tem dúvidas sobre preços, planos ou serviços comerciais.`, `tools: [manage_opportunity]`;
      body `## Passos\n1. Esclareça as dúvidas comerciais do cliente.`;
  - activated with `with_modified_env SCOUT_V2_PLAYBOOKS_DIR:`.

  Two variants: a **procedure-only catalog** (tmp dir with only the copied `qualificacao.md`) and an **empty
  catalog** (empty tmp dir).
- **Pinned**: `qualificacao` pinned by state. The scout gets a required opportunity attribute
  (`scout.sync_required_attribute_ids!`), and an open `Opportunity` for the sandbox conversation leaves it empty
  (pattern: `turn_runner_spec.rb:616-641`).
- **Nothing pinned**: no opportunity.
- **Provider stub**:
  - `stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})`;
  - `.with { |req| provider_requests << JSON.parse(req.body) }`;
  - `.to_return(*provider_responses)`, with `provider_responses` a per-example `let` of Gemini JSON bodies
    (`functionCall` parts, then a final `text` part).

  Observable assertions on `provider_requests[n]`:
  - system text: `contents[0].parts[0].text`;
  - offered tools: `tools[0].functionDeclarations.map { _1['name'] }`;
  - tool calls and results: the later `contents` entries (`functionCall` / `functionResponse` parts).

  Every request example also asserts `provider_requests.size == provider_responses.size` per POST: a sequenced
  WebMock stub keeps returning its last response, so an extra provider call would otherwise go unnoticed (plan.md
  "Performance Goals": still exactly one top-level `chat.ask`).
- **Unit fixtures** (`open_playbook_spec.rb`):
  - in-memory `Custom::ScoutV2::Playbook` values with every field set (`name`, `title`, `trigger`, `priority`,
    `when_state`, `requires: []`, `needs: []`, `tools`, `exits: {}`, `body`, `file_path`, `load_errors: []`,
    as the current spec does):
    - `pausa`: `when_state: []`, `tools: []`;
    - `duvida_comercial`: `when_state: []`, `tools: ['manage_opportunity']`;
    - `qualificacao`: `when_state: [['opportunity_open', nil]]`, `tools: ['manage_opportunity']`;
  - `let(:openable)`, a `Catalog` of the three (overridden per example where a narrower set is needed), and
    `let(:baseline_instructions) { 'BASELINE' }`;
  - `ScoutAccountConfig` for the account (`api_key: 'test-key'`, `model_name: 'gemini-2.0-flash'`):
    `Scout#llm_chat` raises without it (`custom/app/models/scout.rb:60-62`);
  - a real chat from `scout.llm_chat` (it builds offline; `ask` is never called);
  - `baseline_tools` = `[Custom::Scout::Tools::SearchKnowledgeBase.new(scout, conversation, playground: false)]`;
  - `tool_wrapper` = the real `CallRecorder`: `let(:recorder) { Object.new.extend(Custom::Scout::Tools::CallRecorder) }`
    and `let(:tool_wrapper) { ->(tool) { recorder.wrap_tool(tool, simulated: false) } }` — no recording lambda, and
    no example asserts that the wrapper was called;
  - from T005 on, `let(:turn_setup) { Custom::ScoutV2::Tools::OpenPlaybook::TurnSetup.new(baseline_instructions:, baseline_tools:, tool_wrapper:) }`
    (the constructor is `OpenPlaybook.new(scout, conversation, chat:, openable:, turn_setup:)`, five parameters, the
    RuboCop `Metrics/ParameterLists` limit; contracts/open_playbook_tool.md "Construction");
  - turn-setup registration done in a per-context `before` through the real chat API. It mirrors what `TurnRunner`
    registers for that turn state:
    - **pinned** context: `ScoutConversationState` pre-created with `record_state_activation!('qualificacao')`;
      registers `baseline_tools`, the tool itself, a `manage_opportunity` instance, and the instructions
      `'PROCEDURE BODY'`;
    - **nothing pinned** context: no state row; registers `baseline_tools` and the tool itself, and the instructions
      `'INITIAL'` (no procedure tool);
  - `chat.tools` is keyed by symbol (`tool.name.to_sym`, research.md §3). Assert key sets with symbols
    (`expect(chat.tools.keys).to contain_exactly(:search_knowledge_base, :open_playbook)`) and index with symbols
    (`chat.tools[:manage_opportunity]`). The `{sKB, open_playbook, manage_opportunity}` sets below are those symbols.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Validate the execution environment and confirm a green baseline

- [x] T001 Validate Docker Compose stack, Ruby 3.4.4 in the `rails` container, and the prefixed rspec command (`env -u FRONTEND_URL RAILS_ENV=test`) per AGENTS.md
- [x] T002 Baseline run after T001, all green before any change: quickstart.md §4 and §5, plus `custom/spec/services/custom/scout_v2/playbook/index_builder_spec.rb`, `custom/spec/services/custom/scout_v2/tools/open_playbook_spec.rb` and `custom/spec/requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Test setup both slices build on, plus the behavior-free `OpenPlaybook` signature cutover, each done on a green suite

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T003 [P] In `custom/spec/requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb`, add a new `context 'with the real Scout V2 engine (trigger interruption)'`:
  - its setup comes from "Shared test fixtures": a scout with pipeline stages (mirror `turn_runner_spec.rb:9-19`), features `scout`/`scout_v2`/`opportunities`, `ScoutAccountConfig` (`api_key: 'test-key'`, `model_name: 'gemini-2.0-flash'`), sandbox conversation, fixture-catalog `around` hook, and provider stub;
  - no `TurnRunner`/`RubyLLM::Chat` doubles and no custom helper methods (`let` + per-example setup, AGENTS.md);
  - no examples yet;
  - the file's pre-existing `TurnRunner`-doubling examples stay untouched.
- [x] T004 [P] In `custom/spec/services/custom/scout_v2/tools/open_playbook_spec.rb`, rewrite the setup to the unit fixtures, **against the current signature**:
  - subject built with today's keywords, `catalog: openable, tool_wrapper:` (T005 moves it to the final signature);
  - `ScoutAccountConfig` created for the account, so `scout.llm_chat` builds;
  - real chat instead of `instance_double(RubyLLM::Chat)`, real `CallRecorder` wrapper instead of the recording lambda;
  - the pinned and nothing-pinned `before` blocks from "Unit fixtures";
  - port the two existing behaviors to the new fixtures: body returned; unknown name → error with no tool, instruction, or state change;
  - drop the "persists `trigger`" assertion on a `when_state: []` playbook (superseded by FR-001/FR-011, research.md §6);
  - drop the "wraps them" / `have_received(:with_tool)` assertions (interaction checks, Principle VII).

  **Guard**: a test-only refactor (Principle VI). Run the file: it stays green on the current code. Keep it as its own commit, ahead of any production change (commit only after the user's explicit OK, AGENTS.md).
- [x] T005 Signature cutover, after T004, as one behavior-free refactor commit on a green suite (Constitution Principle VI: the spec subject moves with the signature, and no caller is left on the old one):
  - in `custom/app/services/custom/scout_v2/tools/open_playbook.rb`, define `TurnSetup = Data.define(:baseline_instructions, :baseline_tools, :tool_wrapper)` inside the class, and change `initialize` to `(scout, conversation, chat:, openable:, turn_setup:)` (`catalog:` → `openable:`, `tool_wrapper:` → `turn_setup:`). Five parameters: RuboCop's `Metrics/ParameterLists` limit, no `rubocop:disable` (research.md §6);
  - lookup and the error's `Disponíveis:` list come from `@openable`; the success path keeps Brief 04's body (wrapping through `@turn_setup.tool_wrapper`) until T016;
  - no dual signature (research.md §6);
  - in `custom/app/services/custom/scout_v2/turn_runner.rb`, move the only production caller in the same change with **no behavior change**: `build_tools` keeps its `if decision.playbook` gate and passes `openable: catalog` (still the full catalog), plus `turn_setup: OpenPlaybook::TurnSetup.new(baseline_instructions: build_instructions(nil, nil, catalog), baseline_tools: always_on_tools, tool_wrapper: ->(tool) { wrap_tool(tool, simulated: false) })`, where `always_on_tools` is the existing `[search_knowledge_base]` array pulled into a local. That array is the same one registered at turn start and **not** wrapped by hand: the `setup_chat` loop wraps every registered tool in place (`CallRecorder#wrap_tool` redefines `execute` on the same object), so the instances in `baseline_tools` are already wrapped when a takeover re-registers them. Never call `wrap_tool` on them a second time: each call would then be recorded twice (M11, M12). `baseline_instructions`/`baseline_tools` are unused until T016;
  - move `open_playbook_spec.rb`'s subject to the final keywords (`chat:, openable:, turn_setup:`) using the `turn_setup` let from "Unit fixtures". No assertion changes.

  **Guard**: run `open_playbook_spec.rb`, `turn_runner_spec.rb` and `playground_messages_controller_spec.rb`; all stay green (only the structure changed). Own commit, after T004's (commit only after the user's explicit OK, AGENTS.md).

**Checkpoint**: Foundation ready. Every spec file is green, `open_playbook_spec.rb` included, and `OpenPlaybook` already has its final signature.

---

## Phase 3: User Story 1 — reach a situational playbook while a procedure is in progress (Priority: P1)

**Goal**: One openable set per turn: the full catalog with nothing pinned, situational-only with something pinned. It drives both the `[Playbook Index]` and `open_playbook`'s acceptance. The tool is offered iff that set is non-empty. An empty set renders `EMPTY_INDEX_LINE`. A name outside the set gets a tool error and the turn continues.

**Independent Test**: See spec US1. Every example below goes through `POST …/playground_messages`.

### Tests for User Story 1 ⚠️ (write first, observe red for the stated reason)

- [x] T006 [P] [US1] Create `custom/spec/services/custom/scout_v2/playbook/openable_set_spec.rb`:
  - nothing pinned → a `Catalog` whose members equal the catalog's (`to_a == catalog.to_a`);
  - pinned → a `Catalog` with only `when_state.blank?` members, in catalog order;
  - pinned with no situational member → empty (`none?`);
  - empty catalog → empty in both states.

  **Red**: `NameError` (class absent).
- [x] T007 [P] [US1] In `open_playbook_spec.rb`, add an example for a name outside the set (FR-005):
  - setup: pinned `before`, `openable` = situational-only `Catalog([duvida_comercial, pausa])`, then `execute(name: 'qualificacao')`;
  - returns `{ error: 'Playbook desconhecida: qualificacao. Disponíveis: duvida_comercial, pausa' }`;
  - `chat.tools.keys`, the system message and `ScoutConversationState` are unchanged.

  **Guard**: the lookup-and-error logic already exists (T005 already reads `@openable`); only its input changes. FR-005's red-first proof is T009 AC3.
- [x] T008 [P] [US1] In `custom/spec/services/custom/scout_v2/playbook/index_builder_spec.rb`, change the empty-catalog example's expectation to `lines[1] == 'Nenhum playbook disponível para abrir neste turno.'` and rename its description from "stating none are enabled" to "stating no playbook is available to open this turn" (FR-003, Edge Cases 1 and 2).

  **Red**: the current constant renders "Nenhum procedimento específico habilitado no catálogo.".
- [x] T009 [P] [US1] [US3] In the T003 context, add request examples (US3 AC4 lives here because its red reason is the pre-feature gate this phase removes):
  - **AC1 / FR-002 / FR-003 / SC-001 / SC-002** — pinned + fixture catalog → `provider_requests[0]` offers `open_playbook`, and its index lists `pausa` and `duvida_comercial` but not `qualificacao`. **Red**: pre-feature gate hides `open_playbook` while pinned, and the index lists the full catalog.
  - **AC2** — nothing pinned + fixture catalog → index lists all three and `open_playbook` is offered. **Guard**.
  - **AC3 / FR-005 / SC-003** — pinned; the model calls `open_playbook(name: 'qualificacao')`:
    - the tool result in `provider_requests[1]` is the `Playbook desconhecida … Disponíveis: duvida_comercial, pausa` error;
    - HTTP 200 with the final `reply`;
    - state is `qualificacao` / `state` (written by the router at turn start), never `trigger`.

    **Red**: pre-feature, RubyLLM's "unavailable tool" error.
  - **AC4 / Edge Case 2 / FR-003 / FR-004** — pinned + procedure-only catalog:
    - `open_playbook` not offered (**guard**, kills M2);
    - the index block is `[Playbook Index]` + `Nenhum playbook disponível para abrir neste turno.`, with no `- qualificacao:` line (**red**: pre-feature the index lists the full catalog, kills M9).
  - **Edge Case 1 / FR-003 / FR-004** — nothing pinned + empty catalog → `open_playbook` not offered, and the index shows `Nenhum playbook disponível para abrir neste turno.`. **Red**: pre-feature offers it whenever nothing is pinned, and renders the old line.
  - **US3 AC4 / FR-014** — pinned; the model calls `open_playbook(name: 'pausa')` → the response `tool_calls` has **exactly one** entry: `tool_name: 'open_playbook'`, `arguments: { 'name' => 'pausa' }`, with `pausa`'s body as the result. This entry is the turn's per-action review record (spec FR-014; research.md §7). The exact count also catches a double-wrapped `open_playbook` (M11). **Red**: pre-feature the tool is unavailable while pinned, so it is never recorded.

### Implementation for User Story 1

- [x] T010 [P] [US1] Implement `Custom::ScoutV2::Playbook::OpenableSet.call(catalog:, pinned:)` in `custom/app/services/custom/scout_v2/playbook/openable_set.rb` (data-model.md §3)
- [x] T011 [P] [US1] In `custom/app/services/custom/scout_v2/playbook/index_builder.rb`, rename `EMPTY_CATALOG_LINE` → `EMPTY_INDEX_LINE` and reword it to `'Nenhum playbook disponível para abrir neste turno.'` (research.md §1; no other reference in the repo)
- [x] T012 [US1] In `custom/app/services/custom/scout_v2/turn_runner.rb` (the behavior change on top of T005's wiring):
  - compute `openable = OpenableSet.call(catalog:, pinned: decision.playbook)` once in `setup_chat`;
  - build `IndexBuilder.call(openable)` in the initial instructions;
  - register the pinned playbook's tools as today;
  - add `open_playbook` iff `openable.any?` (replacing T005's `if decision.playbook` gate), passing `openable:` and a `TurnSetup` whose `baseline_instructions` is `build_instructions(nil, nil, openable)` (was `catalog` in T005); `baseline_tools` stays `always_on_tools`, still not wrapped by hand;
  - keep per-tool `chat.with_tool` registration;
  - reword the gate comment on `build_tools` to describe the openable-set gate (`openable.any?`), saying "pinned" instead of "forced" (spec Key Entity "Pinned Procedure").
- [x] T013 [US1] Run `openable_set_spec.rb`, `index_builder_spec.rb`, `open_playbook_spec.rb`, and `playground_messages_controller_spec.rb` → green; quickstart.md §4 still green

**Checkpoint**: US1 verified. **Not releasable**: an opened situational playbook still persists `trigger` and adds tools on top until Phase 4. Continue directly to Phase 4.

---

## Phase 4: User Stories 2 + 3 — the interruption takes over the turn and leaves no trace (Priority: P2, P3)

**Goal**: Opening a situational playbook (Path A):
- replaces the system message with the baseline (Blocks 1 + 2, no Block 3);
- replaces the tools with `baseline_tools` + `open_playbook` + its own declared tools, wrapped by `turn_setup.tool_wrapper`;
- never writes `ScoutConversationState`, so the next turn starts from the stored state it had before.

A `when_state` playbook opened with nothing pinned (Path B) keeps Brief 04's behavior: additive tools, `trigger` persisted. Ordering rules: FR-016/FR-017.

**Independent Test**: See spec US2 and US3.

### Tests for User Stories 2 + 3 ⚠️ (write first; red reasons are against the Phase 3 code)

- [x] T014 [P] [US2] [US3] In `open_playbook_spec.rb`, add examples, each under the pinned or nothing-pinned `before` from "Unit fixtures" (symbol keys throughout):
  - **Path A `pausa`, pinned** (FR-006/007/008/011):
    - system message content == `baseline_instructions`;
    - `chat.tools.keys` contain exactly `:search_knowledge_base` and `:open_playbook`;
    - returns `{ body: }`;
    - `ScoutConversationState.attributes` byte-for-byte unchanged.

    **Red**: Phase 3 keeps `'PROCEDURE BODY'` and `manage_opportunity`, and persists `pausa`/`trigger`.
  - **Path A `pausa`, nothing pinned** → no `ScoutConversationState` row is created. **Red**: Phase 3 persists.
  - **Path A `duvida_comercial`, pinned** (FR-006/007/011):
    - system message content == `baseline_instructions`;
    - `chat.tools.keys` contain exactly `:search_knowledge_base`, `:open_playbook`, `:manage_opportunity`;
    - `chat.tools[:manage_opportunity]` is a `Custom::Scout::Tools::ManageOpportunity` that is `not_to equal` the
      instance registered in `before` (the interruption's own declared tool, not the procedure's);
    - `ScoutConversationState.attributes` byte-for-byte unchanged.

    **Red**: Phase 3 keeps `'PROCEDURE BODY'` as the system message and persists `duvida_comercial`/`trigger`. (Its
    additive `with_tool` also replaces the `:manage_opportunity` entry by key, so the tool assertions alone would
    pass on Phase 3; the instructions and state assertions carry the red.)
  - **FR-009 / FR-010 / Edge Cases 3 and 4, pinned** — `pausa` → `duvida_comercial` → `pausa` → `pausa`:
    - tools after each call are {sKB, open_playbook}, then {sKB, open_playbook, manage_opportunity}, then
      {sKB, open_playbook}, then {sKB, open_playbook};
    - every call returns `{ body: }` of the playbook it names — the immediate re-open of `pausa` included (Edge
      Case 3: no "already open" short-circuit);
    - `open_playbook` stays registered throughout.

    **Red**: Phase 3 tools only grow.
  - **Path B `qualificacao`, nothing pinned** (FR-013):
    - the system message is still `'INITIAL'`;
    - `chat.tools.keys` go from {sKB, open_playbook} to {sKB, open_playbook, manage_opportunity};
    - state is `qualificacao`/`trigger`, `activated_at` = `Time.current` under `freeze_time`.

    **Guard** (kills M5).
  - **FR-017 B→A, nothing pinned** (`qualificacao`, then `pausa`) → state `qualificacao`/`trigger`; tools {sKB, open_playbook}. **Red**: Phase 3 overwrites the state to `pausa` and keeps `manage_opportunity`.
  - **FR-017 A→B, nothing pinned** (`pausa`, then `qualificacao`) → state `qualificacao`/`trigger`; tools {sKB, open_playbook, manage_opportunity}. **Guard**.
- [x] T015 [P] [US2] [US3] In the T003 context, add request examples:
  - **US2 AC1–AC3 / FR-006–FR-008 / SC-004** — pinned + fixture catalog; responses: `open_playbook(pausa)`, then `search_knowledge_base(query: '')`, then text. `provider_requests[1]`:
    - system text still contains `[Playbook Index]`;
    - it contains neither `qualificacao`'s body (`Pergunte pelos dados de qualificação pendentes`) nor the pending-fields block;
    - offered tools == {search_knowledge_base, open_playbook};
    - the `open_playbook` tool result contains `pausa`'s body.

    The response `tool_calls` is **exactly** two entries, in order: `open_playbook` (`name: 'pausa'`), then
    `search_knowledge_base` with result `'Nenhum termo de busca fornecido.'` (a blank query returns before any embedding
    call, so no extra HTTP stub is needed). The exact count catches the baseline tool being wrapped twice, at turn
    setup (M11) or by the takeover (M12).

    **Red**: Phase 3 keeps Block 3 and `manage_opportunity`.
  - **US2 AC4 / FR-009 / FR-010 / Edge Cases 3 and 4** — responses `open_playbook(pausa)` → `open_playbook(duvida_comercial)` → `open_playbook(pausa)` → text. Offered tools in `provider_requests[1..3]`:
    - [1]: {sKB, open_playbook};
    - [2]: {sKB, open_playbook, manage_opportunity};
    - [3]: {sKB, open_playbook}.

    The response `tool_calls` is exactly three `open_playbook` entries (catches `self` re-wrapped by a takeover, M12).

    **Red**: Phase 3 tools only grow.
  - **FR-016 / Edge Case 5 / SC-004** — pinned; one response with two function calls, `open_playbook(pausa)` then `manage_opportunity(update…)`:
    - the `manage_opportunity` tool result is RubyLLM's "unavailable tool" error;
    - the opportunity is unchanged;
    - HTTP 200.

    Reverse order in a second example:
    - `manage_opportunity` runs and the opportunity is updated;
    - the next provider request's `contents` still carry the `manage_opportunity` `functionCall` and its `functionResponse` (SC-004: the transcript of actions completed before the takeover stays as it is).

    **Red** (first order): Phase 3 still executes `manage_opportunity`.
  - **FR-012 clause 3 / FR-011 / M8** — pinned, with the state pre-created and an attributes snapshot, two POSTs:
    - POST 1 responses: `open_playbook(duvida_comercial)` → `manage_opportunity(action: 'update', custom_attributes: { <required key> => <value> })` → text;
    - the response `tool_calls` contains the `manage_opportunity` entry with those arguments (the takeover-registered instance went through the real `tool_wrapper`);
    - the opportunity holds the value, and `state.reload.attributes == snapshot`;
    - POST 2 (text only): its system text contains `qualificacao`'s body (the pin survives) but no longer lists the pending field (routing sees the value the interruption's tool recorded).

    **Red**: Phase 3 persists `duvida_comercial`/`trigger`, so POST 2 is routed to `duvida_comercial`.
  - **US3 AC1 + AC2 / FR-011 / FR-012 / SC-005 / SC-006**, two POSTs:
    - setup: pinned state pre-created via `record_state_activation!('qualificacao')` inside `travel_to(1.hour.ago)`, with an attributes snapshot;
    - POST 1 opens `pausa` → `state.reload.attributes == snapshot`;
    - POST 2 (text only, next turn) → the system text of its request contains `qualificacao`'s body and the pending field.

    **Red**: Phase 3 persists `pausa`/`trigger`, and the router keeps `pausa` (priority 20 > 10).
  - **US3 AC3** — nothing pinned; POST 1 opens `pausa` → no state row / `active_playbook` nil; POST 2's system text has no playbook body. **Red**: Phase 3 persists `pausa`.
  - **US3 AC5 / FR-013** — nothing pinned; POST 1 opens `qualificacao` → state `qualificacao`/`trigger`; POST 2's system text contains `qualificacao`'s body. **Guard**.
  - **FR-017 / FR-002 / Edge Case 6** — nothing pinned; one POST opens `qualificacao`, then `pausa`, then text:
    - state `qualificacao`/`trigger`;
    - the last request offers {sKB, open_playbook};
    - the last request's `[Playbook Index]` still lists `- qualificacao:`, `- pausa:` and `- duvida_comercial:` (the
      openable set and the baseline index are fixed at turn start; Path B's mid-turn pin does not narrow them, kills
      M10).

    **Red**: Phase 3 persists `pausa` and keeps `manage_opportunity`.
  - **FR-017 A→B / Edge Case 6** — nothing pinned; one POST opens `pausa`, then `qualificacao`, then text:
    - state `qualificacao`/`trigger`;
    - the last request offers {sKB, open_playbook, manage_opportunity} (Path B adds on top of the takeover set).

    **Guard** (kills M5: with the branch inverted, `pausa` is persisted and `qualificacao` writes nothing).
  - **Edge Case 7 / FR-002 / FR-005 / FR-011** — pinned, with the state pre-created via `record_state_activation!('qualificacao')` and an attributes snapshot; responses `open_playbook(pausa)` → `open_playbook(qualificacao)` → text:
    - the second tool result (in `provider_requests[2]`) is `Playbook desconhecida: qualificacao. Disponíveis: duvida_comercial, pausa`;
    - `provider_requests[2]` offers {sKB, open_playbook} (the rejected call restores nothing);
    - HTTP 200 with the final `reply`, and `state.reload.attributes == snapshot`.

    **Red**: Phase 3 persists `pausa`/`trigger` and keeps `manage_opportunity`. The error assertion itself is a guard: the openable set has been fixed at turn start since T012.
  - **FR-011 / SC-006 over a trigger-stored pin** (spec Key Entity "Pinned Procedure": a pin stored by an earlier assistant-initiated opening) — no opportunity, so nothing matches by state; state pre-created via `record_trigger_activation!('qualificacao')` inside `travel_to(1.hour.ago)`, with an attributes snapshot; responses `open_playbook(pausa)` → text:
    - `provider_requests[0]`: system text contains `qualificacao`'s body; the index lists `pausa` and `duvida_comercial` but not `qualificacao`; offered tools == {sKB, manage_opportunity, open_playbook} (the stored `trigger` pin counts as pinned);
    - `provider_requests[1]`: system text lacks `qualificacao`'s body; offered tools == {sKB, open_playbook};
    - `state.reload.attributes == snapshot` (`activation_reason` still `trigger`, `activated_at` unchanged).

    **Red**: Phase 3 overwrites `active_playbook` with `pausa` and keeps Block 3 and `manage_opportunity`. The `provider_requests[0]` assertions are guards on Phase 3 (T012 already treats any pin as pinned).

### Implementation for User Stories 2 + 3

- [x] T016 [US2] [US3] In `custom/app/services/custom/scout_v2/tools/open_playbook.rb`, `execute` branches on `playbook.when_state.blank?` (contracts/open_playbook_tool.md):
  - `takeover!`: `@chat.with_instructions(@turn_setup.baseline_instructions)` and `@chat.with_tools(*@turn_setup.baseline_tools, self, *declared tools wrapped by @turn_setup.tool_wrapper, replace: true)`; no reference to `ScoutConversationState`;
  - `activate_procedure!`: Brief 04's additive `with_tool` + `record_trigger_activation!`.
- [x] T017 [US2] [US3] Run `open_playbook_spec.rb` and `playground_messages_controller_spec.rb` → green

**Checkpoint**: All user stories verified against their acceptance scenarios

---

## Phase 5: Polish & Cross-Cutting Concerns

- [x] T018 Playground smoke test per quickstart.md §2 steps 1–5: dev fixture catalog in gitignored `tmp/scout_v2_playbooks/`, real API key, pin → interrupt → no write → resume. Leave the catalog in place for T019.
- [x] T019 Openable-set console boundary check per quickstart.md §3 against `tmp/scout_v2_playbooks/` and the shipped catalog (pinned set non-empty `["pausa"]`; shipped pinned set empty). Then run quickstart.md §2 step 6 cleanup.
- [x] T020 [P] Targeted specs per quickstart.md §1
- [x] T021 [P] Regression per quickstart.md §4 (Brief 04 + `turn_runner_spec.rb`) and §5 (v1, FR-015)
- [x] T022 Deliberate-mutant checks M1–M12 per quickstart.md §6. Apply each mutant alone, confirm the named examples fail, then revert; add any missing assertion before continuing.
- [x] T023 `docker compose exec rails bundle exec rubocop` on every changed/new file under `custom/app/services/custom/scout_v2/`, `custom/spec/services/custom/scout_v2/` and `custom/spec/requests/api/v1/accounts/scouts/` — 0 offenses; refactor instead of adding `.rubocop_todo.yml` entries (AGENTS.md)
- [x] T024 When opening the PR, record the Dual-Tree decision in its description (Constitution Principle V): the new `Custom::ScoutV2::Playbook::OpenableSet` and the changed `TurnRunner`/`OpenPlaybook` need no Enterprise counterpart (`grep -rn Scout enterprise/` → zero matches). Commit and push only after the user's explicit OK (AGENTS.md).

---

## Requirement coverage

| Requirement | Tasks |
|---|---|
| FR-001 | T006, T010 |
| FR-002 | T006, T009, T010, T012, T015 (Edge Case 6: openable set fixed within the turn; Edge Case 7) |
| FR-003 | T006, T008, T009 (AC1, AC4, Edge Case 1), T010, T011, T012 |
| FR-004 | T009 (AC4, Edge Case 1), T012 |
| FR-005, SC-003 | T005 (lookup reads `@openable`), T007 (guard), T009 (AC3, red-first), T015 (Edge Case 7: rejected after a takeover) |
| FR-006, FR-007, FR-008, SC-004 | T014, T015 (incl. FR-016 reverse-order transcript; trigger-stored pin), T016 |
| FR-009, FR-010 | T014, T015, T016 |
| FR-011, SC-006 | T014, T015 (US3 AC1, FR-012 clause 3, Edge Case 7, trigger-stored pin), T016 |
| FR-012, SC-005 | T015 (US3 AC2/AC3, FR-012 clause 3) |
| FR-013 | T014 (Path B, A→B), T015 (US3 AC5, FR-017 A→B), T016 |
| FR-014 | T009 (US3 AC4: exactly one `open_playbook` entry in `tool_calls`), T015 (FR-012 clause 3: takeover-added tool recorded) |
| FR-015 | T002, T021 |
| FR-016 | T015 |
| FR-017 | T014 (B→A, A→B), T015 (B→A, A→B) |
| Edge Case 3 (re-open same playbook) | T014 (`pausa` → `duvida_comercial` → `pausa` → `pausa`), T015 (US2 AC4) |
| Edge Case 7 (interrupted procedure re-opened after a takeover) | T015 (Edge Case 7) |
| Key Entity "Pinned Procedure" (pin stored by `trigger`, not only by state) | T015 (trigger-stored pin) |
| SC-001, SC-002 | T006, T009, T019 |
| Wrapping exactly once (no duplicate review entries) | T009 (US3 AC4), T015 (US2 AC1–AC3, US2 AC4) |
| `OpenPlaybook#initialize` within RuboCop `Metrics/ParameterLists` (five parameters) | T005, T023 |
| Constitution V (Dual-Tree decision recorded) | T024 |

---

## Dependencies & Execution Order

- **Setup (Phase 1)** → **Foundational (Phase 2)** → **Phase 3 (US1)** → **Phase 4 (US2 + US3)** → **Polish (Phase 5)**.
- Phase 4 depends on Phase 3: its red reasons are stated against Phase 3's code (the Brief 04 success path still in `execute`).
- Within each story phase: write the tests, observe them red for the stated reason, implement, then run the phase's specs.
- T004 (test-only refactor) and T005 (signature cutover: production signature, its only production caller and the spec subject together, no behavior change) each run on a green suite and stay in their own commits, separate from any behavior change (Constitution Principle VI). No commit leaves a caller on the old signature.
- Release only after Phase 5. US1 alone is not releasable (spec Assumptions).

### Parallel Opportunities

- **Phase 1:** sequential — T002 needs the stack T001 validates.
- **Phase 2:** T003 ∥ T004 (different files). T005 after T004 (same spec file).
- **Phase 3 tests:** T006 ∥ T007 ∥ T008 ∥ T009 (four different files).
- **Phase 3 implementation:** T010 ∥ T011. T012 needs T010 (and T005's wiring).
- **Phase 4 tests:** T014 ∥ T015.
- **Phase 5:** T020 ∥ T021. T018 → T019 are sequential (shared dev catalog). T022 runs after T020 is green. T024 happens when the PR is opened, after the user validates locally.

---

## Notes

- `[P]` = different files, no dependency on an incomplete task in the same phase.
- Test doubles: WebMock at the provider HTTP boundary only. No example this feature adds stubs `Scout`, `ScoutConversationState`, `TurnRunner`, `RubyLLM::Chat` or `CallRecorder` (Principle VII). `turn_runner_spec.rb`'s pre-existing `RubyLLM::Chat` doubles are known debt and are not the proof for any behavior here (plan.md "Testing"); only T033's cutover edits one of them.
- No step journals or progress logs (Principle VIII); passing specs are the proof.
- Zero database migrations, zero schema changes, zero edits to v1 or core Chatwoot files.

## Phase 6: Convergence

- [x] T025 In `custom/spec/requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb`, add assertions to the pinned "US2 AC1–AC3" example (and to "Edge Case 7") that the post-takeover system text in `provider_requests[1]` still lists `- pausa:` and `- duvida_comercial:` and does **not** list `- qualificacao:`. Today no example fails if `TurnSetup#baseline_instructions` is built from the full `catalog` instead of `openable`, which is the behavior change T012 made. Confirm red by temporarily building the baseline from `catalog`, then revert, per FR-003 (partial)
- [x] T026 In the same request spec, add the shared-fixture invariant `expect(provider_requests.size).to eq(<responses consumed by that POST>)` (checked after each POST in two-POST examples) and `have_http_status(:ok)` where it's missing, so an extra top-level provider call can't go unnoticed. Examples: "records exactly open_playbook and search_knowledge_base", FR-016 reverse order, FR-012 clause 3, US3 AC1+AC2, US3 AC3, US3 AC5, FR-017 B→A, FR-017 A→B, Edge Case 7, and both trigger-stored-pin examples, per plan: Performance Goals (partial)
- [x] T027 In the "US2 AC1–AC3" request example, assert that the `open_playbook` `functionResponse` carried in `provider_requests[1]` contains `pausa`'s body (`Confirme a pausa com gentileza.`). This is what the model actually received as the direct result; today only the recorded `tool_calls` result is checked, per US2/AC3 (partial)
- [x] T028 In the FR-016 reverse-order request example, assert that `provider_requests[1]`'s model `contents` entry still carries the `manage_opportunity` `functionCall` part (not only its `functionResponse`), plus `provider_requests.size == 2`, per SC-004 (partial)
- [x] T029 In the "FR-012 clause 3" request example, assert that the response's `manage_opportunity` `tool_calls` entry has the exact arguments sent (`action: 'update'`, `custom_attributes: { 'orcamento' => '5000' }`), not only its `tool_name`, per FR-014 (partial)
- [x] T030 In the "Edge Case 7" request example, assert the final `reply` (`'Final.'`) so the turn is shown to continue after the rejected re-open, per FR-005 (partial)
- [x] T031 In `custom/spec/services/custom/scout_v2/tools/open_playbook_spec.rb`, make both "unknown name" examples (pinned and nothing-pinned) assert that `chat.messages.first.content` is unchanged (`'PROCEDURE BODY'` / `'INITIAL'`), as their descriptions already claim, per FR-005 (partial)

## Phase 7: Convergence

- [x] T032 In the "US3 AC3" request example of `custom/spec/requests/api/v1/accounts/scouts/playground_messages_controller_spec.rb` (nothing pinned, POST 1 opens `pausa`), strengthen the turn-2 proof that nothing is pinned: assert POST 2's system text (`provider_requests[2]`) contains no playbook body at all — also `not_to include('Confirme a pausa com gentileza.')`, not only `qualificacao`'s body — and that `ScoutConversationState.where(conversation_id: sandbox_conversation.id)` is still empty after POST 2. Today the turn-2 assertions would pass even if `pausa` had been pinned. Tag the example `:aggregate_failures` and confirm the new turn-2 assertions go red (alongside the existing turn-1 row check) by temporarily persisting `pausa` via `record_trigger_activation!` in `takeover!`, then revert, per US3/AC3 (partial)
- [x] T033 Cutover per Brief 11 §5 (review finding): in `turn_runner_spec.rb`, the pinned tool-catalog example drops Brief 04's `open_playbook`-absent assertion (keeps declared/undeclared tool checks); in the request spec, AC4 uses a `catalog: :procedure_only` tmp dir (only `qualificacao.md` copied) instead of the shipped catalog. Proof: both examples stay green with a situational playbook temporarily added to `custom/playbooks/`
