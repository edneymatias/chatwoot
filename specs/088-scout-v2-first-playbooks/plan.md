# Implementation Plan: Scout V2 First-Cut Playbooks and Degradation on Missing Capabilities

**Branch**: `088-scout-v2-first-playbooks` | **Date**: 2026-09-28 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/088-scout-v2-first-playbooks/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command; its definition describes the execution workflow.

## Summary

The shipped v2 catalog grows from one to six playbooks (`fora_de_prospeccao`, `duvida_comercial`,
`pausa` situational; `identificacao`, `qualificacao`, `agendamento` procedures), each declaring only
its own tools and exits, with bodies ported from the v1 always-on rules (v1 untouched). Five new
state conditions (`contact_identity_incomplete`, `contact_has_phone`, `in_qualification`,
`opportunity_in_stage(role)`, `playbook_not_completed(name)`) route them; boot validation now checks
condition arguments, `needs` against a new business-fact catalog, and `[[depends: …]]` pending-step
markers. One migration adds `completed_playbooks` to `ichatr_scout_conversation_states`; every
successful exit merges the last procedure in effect (`TurnScope#active_procedure_name`) into it in
the same write as its routing change, so each procedure runs at most once per conversation and a
hand-back never re-pins what a human took over. A new `Playbook::ContentBuilder` renders every
appearance of playbook guidance (pinned, opened, transition target): markers become visible
`PENDENTE` steps while capabilities/business facts are unsatisfied, and procedures get the context
blocks their conditions read (pending fields — scout requirements when there is no opportunity —
and missing contact data). `TurnScope#actions_for` withholds declared exits while a required
capability is unsatisfied, so `qualificado → agendamento` ends in `exit_handoff` in the same turn.
When the model turn completes, `UnsatisfiedItems` computes the last procedure's record and writes it
to the existing `unsatisfied_flags` column and to the agent span's trace metadata.

Spec → code names: "unsatisfied items" → the `unsatisfied_flags` column and the
`langfuse.trace.metadata.unsatisfied_flags` trace key; "unsatisfied capabilities" → `unmet_requires`;
"unsatisfied business facts" → `unmet_needs`; identification's transition exit → `identificado`
(offered as `exit_identificado`).

## Technical Context

**Language/Version**: Ruby 3.4.4, Rails 7.2.3.1

**Primary Dependencies**: RubyLLM 1.15.0 (tool loop, `with_tools(replace: true)` — unchanged use);
existing `Custom::ScoutV2::*` engine from Briefs 01–05/11 (`TurnRunner`, `TurnScope`, `Router`,
`RoutingSnapshot::Builder`, `Predicates::*`, `Playbook::{Loader,Validator,Catalog,OpenableSet,IndexBuilder,PendingFieldsFormatter}`,
`Exits::{ExitTool,Terminal,Transition,Escalation,StageMove}`, `Tools::{Registry,OpenPlaybook,ManageOpportunity}`,
`Capabilities::Catalog`); `Custom::Scout::ContactIdentityService`, `Custom::Scout::Tools::UpdateContact`;
`opentelemetry-sdk` (`OpenTelemetry::Trace.current_span`; `InMemorySpanExporter` in one spec).

**Storage**: PostgreSQL — one additive migration: `ichatr_scout_conversation_states.completed_playbooks`
(`jsonb`, default `[]`, not null). First writer of the existing `unsatisfied_flags` column. See
[data-model.md](./data-model.md).

**Testing**: RSpec in the `rails` container, targeted files only (Principle IX). Only doubles in the
088 examples: WebMock on Gemini `generateContent` and, in the trace context, on the Langfuse OTLP
export endpoint (plus a real in-memory OTel exporter attached to the real SDK provider).
- **Acceptance (real engine, shipped catalog)**: new
  `custom/spec/requests/api/v1/accounts/scouts/playground_first_cut_catalog_spec.rb` (US1–US3
  multi-turn scripts, plus the trace context for US3-AS6/US3-AS8 trace metadata) and a new real-engine
  context in `custom/spec/jobs/custom/scout/process_message_job_spec.rb` (transfers, hand-back,
  fail-safe, quota/API-key stops, new conversation for the same contact).
- **Unit**: 5 predicate specs, `routing_snapshot/builder_spec`, `router_spec` (SC-004 exhaustive),
  `playbook/validator_spec`, `playbook/catalog_spec` (shipped-catalog facts, written per story before
  that story's playbook files), new `playbook/content_builder_spec`, new `turn_scope_spec`, new
  `unsatisfied_items_spec`, `scout_conversation_state_spec`.
- **Cutovers** (contract changes, research §12): 085/087 mechanism specs switch from the shipped
  `qualificacao.md` to a frozen fixture `custom/spec/fixtures/scout_v2/qualificacao_procedure.md`;
  builder "no opportunity → []" becomes scout requirement keys; `exits/exit_tool_spec` and
  `tools/open_playbook_spec` give their `TurnScope` its snapshot through `setup_initial_tools!(…, ctx:)`;
  the 085/087 entry-point examples that assert a routing-state row absent or unchanged after a
  completed model turn (job spec L290, L307, L456, L528, L591, L616; playground spec L803, L868, L927,
  L940, L1176, L1261) assert every column except `unsatisfied_flags`/`updated_at` unchanged plus the
  FR-018 record (FR-018 supersedes "writes nothing"). Three `turn_runner_spec` expectations run with
  `scout.llm_chat` stubbed and doubles of `RubyLLM::Chat`, `ChatwootApp` or the tracer, so their 088
  contract moves to the playground spec instead of being rewritten in place (Principle VII): the
  `open_playbook` result-body expectation of 'executes open_playbook during the turn…' (asserted by
  the FR-028c re-opening example; the example keeps its recorded-result parity check) and the
  trace/metadata examples 'populates turn metadata with trigger activation_reason…' and 'wraps the
  LLM call with instrument_agent_session…' (asserted by the trace context).
- **Model-behavior scenarios** asserted as the prompt/actions contract per step + manual playground
  pass (research §10). **Satisfied path** (FR-019 — a design property, since nothing can satisfy a
  requirement before Brief 07) asserted at component level with a constructed snapshot (research §8).
- **Mutation resistance**: deliberate-mutant table in [quickstart.md](./quickstart.md) §5.

**Target Platform**: Rails app server + Sidekiq (containerized, rootless Podman)

**Project Type**: Web application backend module (fork-owned `custom/` tree + one fork-table
migration); no frontend change — the playground already renders `tool_calls`.

**Performance Goals**: unchanged one top-level model call per v2 turn (087). Added per-turn cost:
two small reads (`reload_active_opportunity` for rendering/recording) and one `update!` of
`unsatisfied_flags`.

**Constraints**: v1's existing method bodies are unchanged (FR-024) — the only additions to
`custom/app/services/custom/scout/` are two additive members from Brief 087, already reviewed and
accepted, called only from v2 code: `handoff_service.rb#transfer!` and
`opportunity_stage_transition_service.rb#moved?` (insertions only, no v1 method body touched, no other
v1 file); `completed_playbooks` written only inside the exits' existing transaction/lock, in the same
`update!` as the routing change; no `Tool::Halt`; no
`return` inside transaction blocks; `Metrics/ClassLength` ≤ 175 — `Playbook::Validator` (≈175) and
`TurnRunner` (≈164) are at the limit, so dependency checks move to `Playbook::DependencyRules` and
turn-completion recording to `UnsatisfiedItems` (`.trace!` builds the record and sets the span
attribute inside `instrument_agent_session`; `TurnRunner` persists it after that block — three lines,
contracts/turn_assembly.md §6); `Metrics/ParameterLists` ≤ 5 (`TurnScope.new` stays at 5 — satisfaction enters
through `setup_initial_tools!(ctx:)`, the only way a scope gets its snapshot); no `.rubocop_todo.yml`
additions.

**Scale/Scope**: 1 migration. New files: 5 playbooks (+1 rewritten), 5 predicates,
`business_facts/catalog.rb`, `routing_snapshot/pending_fields.rb`, `playbook/{dependency_rules,content_builder,contact_gaps_formatter}.rb`,
`unsatisfied_items.rb`. Changed: `scout_conversation_state.rb`, `routing_snapshot.rb`,
`routing_snapshot/builder.rb`, `predicates/registry.rb`, `playbook/validator.rb`, `turn_scope.rb`,
`turn_runner.rb`, `tools/open_playbook.rb`, `exits/{terminal,transition,escalation}.rb`.

All Technical Context items resolved in [research.md](./research.md); no `NEEDS CLARIFICATION`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Upstream Compatibility First | PASS | All code under `custom/` (fork-owned). One migration in `db/migrate/` (Rails-required location): additive column on the fork-prefixed `ichatr_scout_conversation_states`, reversible, no core table. `spec/config/scout_v2_playbooks_spec.rb` untouched. No upstream/Enterprise file edited → no MANIFEST entry. |
| II. Smallest Production-Ready Change | PASS | No satisfaction source, no config flag, no playground reset endpoint, no guard against transitioning into an already-completed procedure (research §2), no rescue around recording (§7). `in_qualification` is one predicate composing two existing ones, not a condition language. Satisfaction lists reuse the snapshot. |
| III. Established Conventions | PASS | Predicate classes/registry, `Data.define` snapshot, Loader-shape/Validator-semantics split, `{ error: }` tool results, Portuguese model-facing text, `Catalog.known?` shape for business facts. No user-facing UI strings → no i18n change. RuboCop limits handled by extraction (Constraints). |
| IV. Safe, Reversible Change | PASS | Reversible migration; no destructive command. Rollback = disable `scout_v2` (v1 path untouched) and roll back the migration. Dev-DB contamination check before committing `db/schema.rb` (quickstart §0). |
| V. Dual-Tree Awareness | PASS | `grep -rE 'ScoutV2\|ScoutConversationState\|Custom::Scout' enterprise/` → no matches (2026-09-28); this feature touches no shared OSS class. Decision recorded here and in the PR description. |
| VI. TDD | PASS | Every slice's tests are written and observed failing before that slice's code (tasks.md orders them so; T067 names the red reason for each Phase 5 example). Every acceptance scenario maps to an example through the real entry point (quickstart §1). FR-019's satisfied path is stated in the spec as a design property, not an acceptance scenario (no production path can reach it before Brief 07), and is verified on the three components that consume satisfaction (research §8). Entry points: the playground request spec (`type: :request`, `playground_first_cut_catalog_spec.rb`) and, for inbox scenarios (US1-AS7, US1-AS12, US2-AS1, US3-AS8, US3-AS9, SC-010, FR-026, the fail-safe edge), `Custom::Scout::ProcessMessageJob#perform`, driven with real models, the real `Custom::ScoutV2::TurnRunner` and WebMock only at the provider boundary — no mock of the component under test. Verified 2026-09-29: quickstart §1's full targeted list is green end-to-end (419 examples), except one pre-existing, unrelated gap tracked outside this feature's task list (parallel same-step function calls where the second names an already-unregistered exit tool; `playground_messages_controller_spec.rb:1598`, a pre-088 mechanism spec). |
| VII. Observable Behavior / Mutation Resistance | PASS | WebMock at the provider HTTP boundary and at the Langfuse OTLP export endpoint. The trace context (playground request spec) uses no stub of an internal class: real `InstallationConfig` rows (`OTEL_PROVIDER=langfuse`, `LANGFUSE_BASE_URL`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`) make `ChatwootApp.otel_enabled?` true and let `OpentelemetryConfig.initialize!` configure the real SDK; the context attaches a `SimpleSpanProcessor(InMemorySpanExporter)` to that provider and restores the previous global provider plus `OpentelemetryConfig.reset!` afterwards. Assertions on persisted rows, provider request bodies, `tool_calls`, finished-span attributes. No 088 example stubs `ChatwootApp`, `OpentelemetryConfig` or the tracer; `process_message_job_spec.rb`'s `scout_v2`-flag examples drive the real `TurnRunner`/`TurnScope`/`Playbook::ContentBuilder` pipeline (T085/T086), not a double of it. |
| VIII. Functional Slices | PASS | (0) storage + conditions + validation (migration, model `completed:`, predicates, snapshot, `DependencyRules`, business facts) + fixture cutovers; (1) US1 — `identificacao`, `qualificacao` (without `qualificado`), completed marking in exits, `ContentBuilder` context blocks and `content_for` plumbing; (2) US2 — situational files, resumption proof; (3) US3 — `agendamento`, `qualificacao`'s `qualificado` exit (its transition target must exist for boot validation), markers/notice, exit withholding, `UnsatisfiedItems` + trace. Each slice: tests first, observed red, then code. No step journals. |
| IX. Surgical Execution Scope | PASS | Quickstart §1/§2 are targeted file lists; full suite reserved for pre-release. |

**Post-design re-check (after Phase 1)**: PASS — the design added one fork-table column (planned),
no upstream edit, no new gem, no test double beyond WebMock and the OTel in-memory exporter.
Complexity Tracking: one justified deviation (inbox entry point, Principle VI).

## Project Structure

### Documentation (this feature)

```text
specs/088-scout-v2-first-playbooks/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
│   ├── playbook_catalog.md
│   ├── state_conditions.md
│   └── turn_assembly.md
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
db/migrate/
└── 21260928000000_add_completed_playbooks_to_ichatr_scout_conversation_states.rb   # NEW
custom/
├── playbooks/
│   ├── fora_de_prospeccao.md        # NEW — situational, priority 100
│   ├── duvida_comercial.md          # NEW — situational, priority 60
│   ├── pausa.md                     # NEW — situational, priority 50
│   ├── identificacao.md             # NEW — update_contact, exit identificado → qualificacao
│   ├── agendamento.md               # NEW — requires/needs, [[depends:]] markers, exits agendado/sem_horario
│   └── qualificacao.md              # REWRITTEN — in_qualification + not completed; exits qualificado/desqualificado
├── app/models/
│   └── scout_conversation_state.rb  # completed: on record_transition!/record_terminal_exit!; record_unsatisfied_items!
└── app/services/custom/scout_v2/
    ├── routing_snapshot.rb          # + completed_playbooks, satisfied_business_facts
    ├── routing_snapshot/
    │   ├── builder.rb               # reads completed_playbooks; uses PendingFields
    │   └── pending_fields.rb        # NEW — extracted; scout requirements when no opportunity
    ├── predicates/
    │   ├── registry.rb              # + 5 names, ARGUMENTS map, argument_kind
    │   ├── contact_identity_incomplete.rb  # NEW
    │   ├── contact_has_phone.rb     # NEW
    │   ├── in_qualification.rb      # NEW
    │   ├── opportunity_in_stage.rb  # NEW (ROLES)
    │   └── playbook_not_completed.rb # NEW
    ├── business_facts/
    │   └── catalog.rb               # NEW — politica_reagendamento
    ├── playbook/
    │   ├── validator.rb             # delegates when_state/requires/needs/markers to DependencyRules
    │   ├── dependency_rules.rb      # NEW
    │   ├── content_builder.rb       # NEW — markers, PENDING_STEPS_NOTICE, context blocks
    │   └── contact_gaps_formatter.rb # NEW
    ├── unsatisfied_items.rb         # NEW — turn-completion record: .call builds, .trace! builds + sets span attribute (no write)
    ├── turn_scope.rb                # setup_initial_tools!(ctx:), content_for, exit withholding in actions_for
    ├── turn_runner.rb               # pinned content via content_for; UnsatisfiedItems.trace! inside the agent session, persist after it; metadata w/o unsatisfied_flags
    ├── tools/open_playbook.rb       # results via content_for
    └── exits/{terminal,transition,escalation}.rb  # completed: scope.active_procedure_name
custom/spec/
├── fixtures/scout_v2/qualificacao_procedure.md   # NEW frozen pre-088 fixture (cutover)
├── models/scout_conversation_state_spec.rb
├── requests/api/v1/accounts/scouts/
│   ├── playground_first_cut_catalog_spec.rb      # NEW — shipped-catalog acceptance + trace context (in-memory exporter)
│   └── playground_messages_controller_spec.rb    # cutover: frozen fixture; FR-018 state assertions
├── jobs/custom/scout/process_message_job_spec.rb # NEW inbox context; cutover of the 087 US1 context; FR-018 state assertions
└── services/custom/scout_v2/
    ├── predicates/{contact_identity_incomplete,contact_has_phone,in_qualification,opportunity_in_stage,playbook_not_completed}_spec.rb  # NEW
    ├── routing_snapshot_spec.rb, routing_snapshot/builder_spec.rb, router_spec.rb
    ├── playbook/{validator_spec,catalog_spec}.rb, playbook/content_builder_spec.rb (NEW)
    ├── turn_scope_spec.rb (NEW), unsatisfied_items_spec.rb (NEW)
    ├── tools/open_playbook_spec.rb, exits/exit_tool_spec.rb  # cutover: scope snapshot via setup_initial_tools!(ctx:)
    └── turn_runner_spec.rb          # cutover: frozen fixture; open_playbook result-body and trace/metadata expectations moved out

# Unchanged: v1 (AgentRunner, SystemPromptsService, FunnelSectionBuilder, v1 tools), Router,
# Predicates::Evaluator, Playbook::Loader, OpenableSet, IndexBuilder, Exits::{ExitTool,StageMove},
# PlaygroundConversation, playground controller, frontend.
```

**Structure Decision**: single Rails monolith; production code in the fork-owned
`custom/app/services/custom/scout_v2/` tree and `custom/playbooks/`, one model change in
`custom/app/models/`, and one additive migration on a fork-prefixed table.

## Risks

- **Model tool-calling is load-bearing**: identification's "once" rule and the transition timing
  depend on the model following the body; the structure bounds the damage (identification can run
  at most once per conversation by state). Observed through `activation_reason` and `tool_calls` in
  Langfuse.
- **Playground sandbox persists per scout**: `completed_playbooks` (like `active_playbook` today)
  survives across playground sessions, so a finished `identificacao`/`qualificacao` will not re-run
  in the playground until the row is reset (quickstart §4 script). A reset feature is out of scope.
- **Qualified leads are transferred on qualification** (as v1), now via `agendamento`'s degraded path:
  `qualificacao` tells the model to follow `exit_qualificado`'s returned guidance in the same turn, and
  `agendamento` tells it to call `exit_handoff` in that turn while offering slots is unavailable (key
  phrases asserted, FR-011a/FR-015). If a model still skips `exit_handoff`, the lead stays with the
  assistant with `agendamento` pinned and its own exits withheld; the next turn carries the same
  instruction. Observed through `tool_calls` in Langfuse and the manual playground pass (SC-007).
- **Transition into an already-completed procedure** is allowed (research §2; FR-028c permits it);
  unreachable with the shipped catalog except after a human removes a contact's phone post-qualification.
- **`instrument_agent_session` re-runs its block on an exception raised inside it** (existing
  behavior, `lib/integrations/llm_instrumentation.rb:45-47`): a write failing there would repeat
  `chat.ask` and every exit of the turn. The new recording therefore writes nothing inside the block;
  the persist runs after it and fails loudly (research §7).

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Inbox acceptance scenarios (US1-AS7, US1-AS12, US2-AS1, US3-AS8, US3-AS9, SC-010) are exercised through `Custom::Scout::ProcessMessageJob#perform`, not a `type: :request` spec (Principle VI) | No request runs an inbox Scout turn synchronously: an incoming message reaches the engine only through `Custom::ScoutListener#message_created` → `ProcessMessageJob.enqueue_debounced` (Redis debounce keys and a `set(wait:)` re-enqueue, `process_message_job.rb:10-50`). The job is the first code that owns the inbox turn, and these scenarios need the inbox-only effects (real transfer: status, team/assignee, transfer note; hand-back; a new conversation for the same contact). The examples use the real `TurnRunner`, exits and models, WebMock only (Principle VII), and assert persisted rows and provider request bodies. | A request spec posting an incoming message would add only the listener → debounce → job wiring, which 088 does not change (`custom/spec/listeners/custom/scout_listener_spec.rb` covers the listener), at the cost of driving Redis debounce timing and delayed re-enqueues inside every multi-turn hand-back script. It would reach the same `perform` call through unrelated machinery. |

FR-019's satisfied path is a spec-level design property verified at component level (spec FR-019,
research §8), not a violation; it gains a request example when Brief 07 delivers a satisfaction source.
