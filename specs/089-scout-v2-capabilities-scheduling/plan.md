# Implementation Plan: Scout V2 Capabilities and End-to-End Scheduling

**Branch**: `089-scout-v2-capabilities-scheduling` | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/089-scout-v2-capabilities-scheduling/spec.md`

## Summary

`scheduling` and `customer_registry` stop being names in a catalog and become real. A small
capability layer under `custom/app/services/custom/scout_v2/capabilities/` gives each capability a
declared contract (operations, typed/required/optional inputs, output shape). A per-account
`Capabilities::Registry` resolves a capability to a provider — today only the account's enabled
ERP hook of vendor `younus`, via `Erp::Younus::Adapter` — and answers "unsatisfied" (never raises)
when the hook, the vendor mapping or any setting the capability needs is missing. The routing
snapshot's `satisfied_capabilities` (hard-coded `[]` since Brief 06) is filled from that registry,
which by itself flips the Brief 06 machinery (pending markers, exit withholding, unsatisfied
record) to the satisfied path.

Each operation is exposed to the model as one generic `Capabilities::OperationTool`
(`scheduling_list_slots`, `scheduling_book`, `customer_registry_find_by_phone`,
`customer_registry_create`) registered by `TurnScope#actions_for` under the same
"playbook in effect + all `requires` satisfied" scoping as the playbook's other tools. The tool
validates the model's input strictly before anything leaves the process (missing/mistyped input →
`{ error: }` result, turn continues), injects the phone from the contact and every configuration
identifier from the hook settings inside the provider, and treats the vendor's answer leniently
(shape deviations go to the trace, the data still reaches the model; an answer missing the identifier it must carry is a failed result, `contracts/capabilities.md` §1a). Conversation-scoped facts the
spec requires — the resolved customer, the slots offered, the successful booking — live in one new
jsonb column `capability_state` on `ichatr_scout_conversation_states`; `book` only accepts an offered
slot, a resolved customer and no earlier booking, and the `agendado` exit gets a declarative `precondition: booking`
precondition so it is rejected (no state change, not marked completed) unless a booking succeeded.
`agendamento.md` loses the policy step and `politica_reagendamento`, its `agendado` exit loses the
model-supplied `inicio` field (the booked start and reference come from the stored booking), and its
body gains the ERP-failure handoff rules, while `ContentBuilder` appends a phone-missing notice (blank contact phone ∧ `requires: customer_registry`) so a phoneless lead is handed off with zero capability calls. The ERP hook's settings schema grows six
optional identifiers (`id_usuario`, `id_convenio`, `nr_convenio`, `id_origem_pessoa`, `id_agenda`,
`id_servico`), delivered through the existing MANIFEST-injected `younus` block of
`config/integration/apps.yml`.

Spec → code names: "operation" → `Capabilities::Operation`; "capability call record" →
`Capabilities::CallRecord` (tool-span attribute `langfuse.observation.metadata.capability_call`);
"resolved customer / offered slots / booking" → keys of `ScoutConversationState#capability_state`;
"configuration identifiers" → the seven hook settings `id_empresa … id_servico`.

## Technical Context

**Language/Version**: Ruby 3.4.4, Rails 7.2.3.1

**Primary Dependencies**: existing v2 engine from Briefs 01–06/11 (`TurnScope`, `TurnRunner`,
`RoutingSnapshot::Builder`, `Exits::{ExitTool,Terminal,Transition}`, `Playbook::{Loader,Validator,
DependencyRules,ContentBuilder}`, `UnsatisfiedItems`, `Capabilities::Catalog`); RubyLLM 1.15.0
(dynamic `params_schema`, the pattern `ExitTool` already uses); `Erp::{BaseAdapter,Younus::Adapter,
Younus::Client}` and `Erp::{ApiError,AuthenticationError}`; HTTParty (already used by the client);
`Integrations::Hook` / `Integrations::App` (category `erp`); `opentelemetry-sdk` for span attributes.
No new gem.

**Storage**: PostgreSQL — one additive migration: `ichatr_scout_conversation_states.capability_state`
(`jsonb`, default `{}`, not null). Hook settings stay in the existing `integrations_hooks.settings`
jsonb (schema-validated by `settings_json_schema`, no migration). See [data-model.md](./data-model.md).

**Testing**: RSpec in the `rails` container, targeted files only (Principle IX). Doubles only at the
external boundary: WebMock on `https://wfh.ichatr.com.br/webhook/*` (stand-in ERP, incl. request
inspection for identifiers/credential) and on Gemini `generateContent`; the OTel in-memory exporter
pattern from the 088 trace context for FR-017.
- **Contract/unit**: `capabilities/{operation,base,registry,scheduling,customer_registry,
  operation_tool}_spec.rb`, `erp/younus/{client,adapter}_spec.rb` extensions, `exits/exit_tool_spec`
  (precondition), `playbook/{loader,validator}_spec` (exit `precondition`), `scout_conversation_state_spec`,
  `routing_snapshot/builder_spec` (satisfied names), `turn_scope_spec`.
- **Acceptance (real engine, shipped catalog, stand-in ERP)**: new
  `custom/spec/requests/api/v1/accounts/scouts/playground_scheduling_spec.rb` — happy path, no-slot
  path, handoff paths, no-phone path, ERP-failure path, post-outcome non-re-pinning, degraded account
  (Brief 06 behavior preserved), trace context (FR-017/FR-004/SC-008). Story-level request examples (Principle VI): US1 = strict input error and soft-output deviation inside a real turn (T037d), US2 = configured identifiers/phone in the ERP requests and no token in the span (T037e), US3 = the paths above (T037a–c). Multi-turn scripts drive Gemini
  via WebMock exactly as `playground_first_cut_catalog_spec.rb` does.
- **Cutovers** (contract changes, research §11): the 088 specs that count markers/pendings and the
  `inicio` field of `agendamento` (`playbook/catalog_spec`, `playground_first_cut_catalog_spec`,
  `unsatisfied_items_spec`, `turn_scope_spec`, `content_builder_spec` shipped-catalog examples) move to
  the new body; `hook_spec`/`app_spec` visible-properties expectation grows; the MANIFEST `younus`
  insert changes.
- **Model-behavior scenarios** (natural-language options, ≤3 times, two-failure transfer, nearest-date search bounded to three following
  days) asserted as key-phrase body invariants of the shipped `agendamento.md` (research §10, as 088 does) +
  the manual playground pass (SC-010).
- **Mutation resistance**: deliberate-mutant table in [quickstart.md](./quickstart.md) §5.

**Target Platform**: Rails app server + Sidekiq (containerized, rootless Podman)

**Project Type**: Web application backend module (fork-owned `custom/` tree + one fork-table
migration + one MANIFEST-tracked config edit); no frontend code — the hook form is rendered from
`settings_form_schema` by `NewHook.vue` (`FormKit v-for="item in formItems"`).

**Performance Goals**: no added top-level model call. Per turn: one `hooks` query (+ `app` lookup,
in-memory) to compute satisfied capabilities. Per capability call: one ERP request (5 s timeout, the
existing client default) and at most one `update!` of `capability_state`.

**Constraints**: v1 (`Custom::Scout::*`) and the existing engine untouched (FR-026); `call_custom_api`
and `ScoutTool` not referenced by v2; `Erp::AdapterFactory`, `Api::V1::…::ErpController`,
`Erp::BaseAdapter#fetch_data` and the contact-data card unchanged; `Playbook::Validator` (≈175) and
`TurnRunner` (≈164) are at `Metrics/ClassLength` 175 — the exit-`precondition` check goes into
`Playbook::DependencyRules`/`Loader` (not the Validator body) and `TurnRunner` is not touched;
`TurnScope` stays ≤ 175; no `.rubocop_todo.yml` additions; no `return` inside transaction blocks;
no retries (FR-015); credentials never enter a record (FR-017); Portuguese model-facing text outside
i18n files.

**Scale/Scope**: 1 migration. New: `capabilities/{base,operation,registry,scheduling,customer_registry,
operation_tool,call_record}.rb`, `exits/preconditions.rb`. Changed: `capabilities/catalog.rb`
(unchanged names; stays the single startup catalog), `scout_conversation_state.rb`,
`routing_snapshot/builder.rb`, `turn_scope.rb`, `exits/{exit_tool,terminal}.rb`,
`playbook/{exit_declaration,loader,dependency_rules,content_builder}.rb`, `playbooks/agendamento.md`, `erp/younus/{client,
adapter}.rb`, `erp/base_adapter.rb` (visibility of `normalize_phone_digits` and default `operation_identifier_keys`), `config/integration/apps.yml` + `bin/sync-custom-module-hooks` (MANIFEST `younus`
entry).

All Technical Context items are resolved in [research.md](./research.md); no `NEEDS CLARIFICATION`
remains. One input is **not observable from this environment**: the vendor's response bodies for the
three new read/write endpoints (the ERP host timed out at 85 s from the `rails` container during
planning). This is contained, not open: the output side of the contract is deliberately soft
(FR-004), and T001 of the implementation captures real bodies into WebMock fixtures before the
client parsers are written (research §9).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Upstream Compatibility First | PASS (one tracked exception) | All code under `custom/`. Migration in `db/migrate/` (Rails-required location): additive column on the fork-prefixed `ichatr_scout_conversation_states`, reversible. The only edit outside `custom/` is to the `younus:` block of `config/integration/apps.yml`, which is **not** upstream text: it is a MANIFEST-injected fork block (`bin/sync-custom-module-hooks`, anchor after the last upstream app entry, `transcript_activity_score`). Its `settings_json_schema`/`settings_form_schema`/`visible_properties` change, so the MANIFEST `insert` for it is updated in the same commit (AGENTS.md "Every accepted direct-upstream edit MUST get a MANIFEST entry" — here the entry already exists and must stay byte-consistent, else `--check` reports `missing` and `apply` would reinsert the old block). No upstream Ruby/JS file is edited. |
| II. Smallest Production-Ready Change | PASS | One provider (Younus), no provider plug-in interface beyond a one-line `PROVIDERS` map and the adapter's `capability_settings`; no HTTP-tool provider; no retry, no output blocking; `service` is accepted and recorded but never sent (research §6); exit `precondition` is one declarative key, not a general guard language; capability state is one jsonb column, not three tables; `politica_reagendamento` catalog entry and the generic business-fact mechanism stay untouched (spec FR-024). |
| III. Established Conventions | PASS (one tracked deviation) | `Data.define` value objects, `Custom::` namespaces with compact class definitions, `{ error: }` tool results, dynamic `params_schema` as in `ExitTool`, Loader-shape/Validator-semantics split, Portuguese model-facing text, tests with `let`/per-example setup. The six new `younus` form labels are plain English strings like the existing `API Token`/`Company ID`: FormKit renders `settings_form_schema` labels verbatim and `SingleIntegrationHooks.vue` special-cases only the two existing keys (new keys display their raw key name), so translating them needs a frontend change (Principle II) → justified deviation from the pt-BR rule (Personalization Boundaries), accepted by the user on 2026-09-30, see Complexity Tracking. RuboCop limits handled by extraction (Constraints). |
| IV. Safe, Reversible Change | PASS | Reversible migration; no destructive command. Rollback = disable `scout_v2` + roll back the migration; the hook settings additions are optional keys (old hooks stay valid). Dev-DB contamination check before committing `db/schema.rb` (quickstart §0). Verification against the real ERP performs real writes → test company/agenda only (spec Assumptions; quickstart §4). |
| V. Dual-Tree Awareness | PASS | `grep -rnE "Erp::|ScoutV2|integrations/hook" enterprise/` → no matches (2026-09-30). No OSS class edited, so no Enterprise override/extension point is needed; `Custom::Integrations::Hook` (prepended module) is untouched. Decision recorded here and in the PR description. |
| VI. TDD | PASS | Tests written and observed failing before each slice's code (tasks.md will order them; the migration-dependent examples fail on the missing column first). Every acceptance scenario maps to an example through its claim's entry point: decisions/predicates (registry resolution, input validation, `precondition`, slot/customer preconditions, ambiguity) by direct calls to the real deciding class; the effect criteria (requests carry configured identifiers/phone, credential absent from records) by the operation tool against a WebMock ERP; the wiring criteria (US3, US2-AS6 no ERP request on degraded accounts, trace) by the real `type: :request` playground spec. Every user story has ≥1 contract-criterion (request) test. |
| VII. Observable Behavior / Mutation Resistance | PASS | Doubles only at the ERP HTTP boundary (WebMock), the Gemini endpoint (WebMock) and OTel in-memory exporter. Real `Integrations::Hook`, `Account`, `Contact`, `Conversation`, `ScoutConversationState` rows; no stub of `Erp::Younus::Adapter`, the registry or the tool. Assertions: request bodies/queries received by WebMock (`have_requested … with`), persisted `capability_state`/`completed_playbooks`/`last_exit`, `tool_calls`, finished-span attributes. Mutants listed in quickstart §5. |
| VIII. Functional Slices | PASS | (0) contract + registry + storage (migration, model methods, snapshot wiring); (1) US1 — operation tool strictness, soft output, unsatisfied resolution; (2) US2 — hook settings, client/adapter, identifier injection, phone, preconditions on `book`; (3) US3 — `precondition`, `agendamento.md` rewrite, end-to-end request specs, cutovers. Each slice: tests first, observed red, then code. No step journals. |
| IX. Surgical Execution Scope | PASS | Quickstart §1/§2 are targeted file lists; full suite only at pre-release. |

**Post-design re-check (after Phase 1)**: PASS — design added one fork-table column (planned), one
MANIFEST-tracked config edit (planned), no upstream code edit, no new gem, no internal-class test
double. Complexity Tracking: one tracked deviation (English-only form labels, accepted 2026-09-30).

## Project Structure

### Documentation (this feature)

```text
specs/089-scout-v2-capabilities-scheduling/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── capabilities.md
│   ├── erp_provider.md
│   └── turn_assembly.md
├── checklists/requirements.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
db/migrate/
└── 21260930000000_add_capability_state_to_ichatr_scout_conversation_states.rb   # NEW
config/integration/apps.yml           # younus block: +6 optional settings, +form items, +visible_properties (MANIFEST-tracked)
bin/sync-custom-module-hooks          # MANIFEST younus insert updated to match
custom/
├── playbooks/
│   └── agendamento.md                # REWRITTEN — no policy step/need; agendado without fields, precondition: booking; phone/ERP-failure rules
├── app/models/
│   └── scout_conversation_state.rb   # + remember_customer!/remember_slots!/remember_booking!
├── app/services/erp/base_adapter.rb   # normalize_phone_digits: private → public (no behavior change)
├── app/services/erp/younus/
│   ├── client.rb                     # + settings kwarg; find_person/create_person/free_slots/create_appointment
│   └── adapter.rb                    # + capability_settings; provider methods (normalize vendor → contract shapes)
└── app/services/custom/scout_v2/
    ├── capabilities/
    │   ├── catalog.rb                # unchanged (single startup catalog, FR-027)
    │   ├── operation.rb              # NEW — Data: name, inputs, output; #problems_for(inputs), #deviations_for(data), #params_schema
    │   ├── base.rb                   # NEW — DSL: capability_name, operation(:x) { input …; output … }, operations
    │   ├── scheduling.rb             # NEW — contract + #list_slots/#book (conversation-side rules)
    │   ├── customer_registry.rb      # NEW — contract + #find_by_phone/#create
    │   ├── registry.rb               # NEW — resolve(name, account:), satisfied_names(account:), PROVIDERS
    │   ├── operation_tool.rb         # NEW — RubyLLM tool: validate → call → normalize → record
    │   └── call_record.rb            # NEW — Data + #to_span_json (no credential)
    ├── exits/
    │   ├── preconditions.rb          # NEW — REGISTRY { 'booking' => … }
    │   ├── exit_tool.rb              # precondition check before dispatch
    │   └── terminal.rb               # success message carries booked start/reference
    ├── playbook/
    │   ├── exit_declaration.rb       # + precondition: keyword
    │   ├── loader.rb                 # ALLOWED_EXIT_KEYS + 'precondition'
    │   ├── dependency_rules.rb       # validates exit precondition against Exits::Preconditions
    │   └── content_builder.rb        # + PHONE_MISSING_NOTICE for requires customer_registry ∧ blank contact phone
    ├── routing_snapshot/builder.rb   # satisfied_capabilities: Capabilities::Registry.satisfied_names(account:)
    └── turn_scope.rb                 # actions_for adds capability OperationTools
custom/spec/
├── services/custom/scout_v2/capabilities/{operation,base,registry,scheduling,customer_registry,operation_tool}_spec.rb   # NEW
├── services/erp/younus/{client,adapter}_spec.rb                                     # extended
├── requests/api/v1/accounts/scouts/playground_scheduling_spec.rb                    # NEW — acceptance + trace context
├── fixtures/erp/younus/*.json                                                      # NEW — captured vendor bodies (T001)
└── (cutovers listed in Technical Context)

# Unchanged: v1 (AgentRunner, ScoutTool, CallCustomApi, SystemPromptsService), Router, Predicates::*,
# Playbook::{OpenableSet,IndexBuilder}, Exits::{Transition,Escalation,StageMove,PayloadValidator},
# Erp::{AdapterFactory,Errors}, Erp::BaseAdapter (except `normalize_phone_digits` visibility), ErpController, ErpDataCard and the whole frontend.
```

**Structure Decision**: single Rails monolith; production code in the fork-owned
`custom/app/services/custom/scout_v2/capabilities/` tree and `custom/app/services/erp/`, one model
change in `custom/app/models/`, one additive migration on a fork-prefixed table, one
MANIFEST-tracked settings-schema edit.

## Risks

- **Vendor bodies unobserved**: the three new endpoints' response envelopes (and whether
  `/webhook/api/v1/empresas/pessoas/pesquisar` matches the `sucesso`/`dados[].json` envelope the
  existing person lookup returns) were not observable at planning time. Mitigation: soft output by
  design; T001 captures real bodies into fixtures before parsers are written; the request-shape
  side (query/body keys) is known from the four `ScoutTool` schemas and asserted with WebMock.
- **`nr_convenio` is required for `customer_registry`** (FR-007 "every setting the operations
  need"; AS 2.3 sends it). An account whose agreement has no card number must still enter a value
  or the capability stays unsatisfied (degrades safely to handoff). Revisit only if a real account
  needs it blank.
- **Write timeout ambiguity**: `create_appointment` timing out at 5 s may have created the
  appointment. FR-015 forbids auto-retry; the model is told the outcome is unknown and transfers,
  leaving reconciliation to the human. Observed through `capability_call` spans.
- **Fixed UTC-03:00 offset**: slot normalization and `dtIniAgenda` use `-03:00` (Brasília, no DST); a Younus account in another timezone would book at the wrong instant. Recorded as a spec Assumption; deriving the offset from the account timezone is a separate change.
- **Model tool-calling is load-bearing** for "≤3 options in natural language", the two-failure
  transfer and the phone-missing handoff; structure bounds the damage: `book` only accepts offered
  slots and only once per conversation, `exit_agendado` only follows a real booking, and a no-phone contact cannot reach the ERP.
- **Playground sandbox persists per scout**: `capability_state`/`completed_playbooks` survive across
  playground sessions, and the sandbox contact has no phone until `identificacao` captures one
  (quickstart §4 reset + setup script). A reset feature is out of scope.
- **`instrument_agent_session` re-runs its block on exception** (088 risk, unchanged): capability
  writes happen inside tool calls, not inside the session block, so a failing `remember_*` write
  raises from the tool call; the fail-loud behavior is accepted (Principle II, AGENTS.md "let it
  fail loudly") and no rescue is added.
- **Registry well-formedness**: satisfaction requires digit-only `id_*` values (`id_empresa` included), so a
  pre-existing hook with a non-numeric company id resolves as unsatisfied instead of raising in the client
  (`Integer()`); the contact-data card is unaffected because it does not use the capability path.
- **Implementation prerequisite (user input)**: T001 needs a test company/agenda from the user and a
  reachable capture path for vendor bodies. Until then only T002–T008, T011–T018, the contract-only
  capability classes (T024, T025), `Adapter.capability_settings` (T020a) and the registry/snapshot wiring (T021, T022) can proceed;
  T009/T010, the client (T019) and the adapter provider methods (T020) wait.

## Complexity Tracking

| Deviation | Why needed | Simpler alternative rejected because |
|---|---|---|
| New `younus` form labels are English-only (Personalization Boundaries: fork-owned strings need `en` + `pt-BR`) | The hook form renders `settings_form_schema` labels verbatim; the two existing labels are already English-only; the connected-hook summary in `SingleIntegrationHooks.vue` shows the raw key (`id_usuario`, …) for the new settings, accepted as cosmetic | i18n for the labels needs changes to `NewHook.vue`/`SingleIntegrationHooks.vue` (upstream frontend files) for six labels: out of proportion (Principle II) and worse for upstream mergeability (Principle I) |
