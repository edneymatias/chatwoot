# Implementation Plan: Scout Response Auditor

**Branch**: `058-scout-response-auditor` | **Date**: 2026-08-28 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/058-scout-response-auditor/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Real production testing surfaced two failure patterns the Phase 08 prompt guardrail doesn't cover:
Scout's drafted reply claiming an opportunity/stage update already happened when the corresponding
tool was never called (or was called and failed), and Scout promising a human handoff (or other
future work) that never actually occurred, leaving the conversation stuck `pending` indefinitely.
The fix adds a second, independent audit pass — grounded in the turn's *real* tool activity, not
just the reply text — that runs once, from inside `Custom::Scout::AgentRunner#process_response`
(the single interception point Phase 08 already established), after the structured reply parses
successfully and before it is dispatched to the customer. Two new LLM-backed classifiers
(`Custom::Scout::ActionClassifierService` for explicit-handoff-intent, adapted from Captain's
`AssistantActionClassifierService` reference architecture but with Scout's own commercial reasons;
`Custom::Scout::ClaimConsistencyService` for reply-vs-reality grounding, adapted from Captain's
`AssistantFalsePromiseService` but — unlike Captain's purely textual detector — fed the turn's
actual recorded tool calls so it can catch both a broken future promise *and* a false claim of
completed action) are orchestrated by a new `Custom::Scout::ResponseAuditor`, which owns the
repair-and-reverify loop (regenerate once via the same live `chat` object, reverify, escalate to
the existing fail-safe handoff path if still inconsistent). Tracking what tools actually ran during
a turn — including failures — is extracted from `PlaygroundRunner#execute_and_record`'s existing
`execute`-wrapping pattern into a shared `Custom::Scout::Tools::CallRecorder` module, included by
both `AgentRunner` (new) and `PlaygroundRunner` (refactored, not behaviorally changed). All of this
is gated by one new boolean column, `feature_response_auditor` on `ichatr_scouts` (mirroring the
existing `feature_memory` column/pattern), defaulting to `false` so existing accounts see zero
behavior change.

## Technical Context

**Language/Version**: Ruby 3.4.4 (Rails, per `Gemfile`/`.ruby-version`)

**Primary Dependencies**: `ruby_llm` 1.15.0 and `ruby_llm-schema` 0.3.0 (already direct `Gemfile`
dependencies, already used by `AgentRunner`/`BaseTool`/`Custom::Scout::ResponseSchema` since Phase
057 — `chat.with_schema(...)` is an established pattern in this codebase, no new dependency).
`Scout#llm_chat(temperature:)` (existing model method, already used by `AgentRunner`) is the only
LLM entry point the two new classifiers use — per the spec's constraint that Scout has one
provider/model per account (`ScoutAccountConfig`), not Captain's per-feature model routing
(`Llm::BaseAiService`/`Llm::FeatureRouter`, which are Captain-only and out of scope to reuse here).

**Storage**: One new boolean column, `feature_response_auditor` on `ichatr_scouts`
(`db/migrate/`), `null: false, default: false` — same shape as the existing `feature_memory`
column added in `db/migrate/21260819000005_add_pipeline_fields_to_ichatr_scouts.rb`. No other new
tables/columns; classifier decisions are not persisted (logged only, per spec's explicit
out-of-scope note on a dedicated reporting UI/history table).

**Testing**: RSpec, per repo convention (`custom/spec/services/custom/scout/...`), run via
`docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/...`

**Target Platform**: Rails app server (self-hosted, this fork's Docker/Podman stack)

**Project Type**: Web service (Rails monolith backend feature; no new endpoint, no frontend change
— the feature flag is a plain DB column with no dedicated settings-UI toggle, matching the existing
`feature_memory` precedent, which also ships with no UI switch and is set via API/console/seed)

**Performance Goals**: No explicit latency target set by the spec beyond "never leaves the customer
waiting indefinitely" (edge case) and "at most one repair-and-reverify cycle per turn" (spec
Assumptions) — worst case is 4 extra LLM calls in a single turn (action classifier, claim
consistency check, one regeneration, one reverification), matching the order of magnitude already
estimated for the Captain-derived architecture this adapts. Not a design driver beyond that hard
cap; no new async/background processing is introduced (the audit runs synchronously inside the
same request/job cycle `AgentRunner#perform` already runs in).

**Constraints**: Must run from exactly one call site (`AgentRunner#process_response`, after
`parse_structured_response` succeeds, before `dispatch_outgoing_reply`) — no new message-creation
call site (spec FR-010). Must never block/alter delivery of the original reply on an auditor-side
failure (spec FR-009) — `rescue StandardError` + `ChatwootExceptionTracker` + log, matching the
existing `AgentRunner#perform` top-level rescue pattern. Must not increment
`responses_consumed` more than once per turn regardless of how many auditor/regeneration calls
happen (spec FR-012) — the existing single increment in `dispatch_outgoing_reply` already
satisfies this as long as no new code path calls it. Must not edit
`enterprise/app/services/captain/llm/assistant_action_classifier_service.rb`,
`assistant_false_promise_service.rb`, or `enterprise/lib/captain/assistant_false_promise_schema.rb`
— read as architecture reference only (same licensing caveat recorded in the spec's source
document), never copied as product text; Scout's classes mirror the *shape* (schema class +
`with_schema` + `instrument_llm_call`), not the Captain-specific reasons or Captain's
`Llm::BaseAiService`/model-routing infrastructure.

**Scale/Scope**: Single-tenant self-hosted install. New files: 1 migration, 2 classifier services +
2 `RubyLLM::Schema` subclasses, 1 orchestrator service, 1 shared tool-call-recording module.
Modified files: `AgentRunner` (wire in `CallRecorder` + call `ResponseAuditor` once) and
`PlaygroundRunner` (refactored to include the extracted `CallRecorder` module instead of its
private `wrap_tool`/`execute_and_record` methods — no behavior change, same recorded-call shape).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. No upstream/core or `enterprise/` file is edited; the
  two new classifiers and the orchestrator live entirely in `custom/`, mirroring (not copying text
  from — same licensing caveat already recorded in the spec's source document) the *shape* of
  Captain's `AssistantActionClassifierService`/`AssistantFalsePromiseService`/response-builder-job
  orchestration, an already-proven extension pattern in this codebase (also the precedent Phase 057
  followed for `chat.with_schema`). The one migration is additive (`null: false, default: false`)
  and touches only the fork-owned `ichatr_scouts` table, per the constitution's stated exception
  for `db/migrate/` infrastructure.
- **II. Smallest Production-Ready Change** — PASS. One flag gates all new behavior; no
  speculative per-provider or per-account branching beyond what `Scout#llm_chat` already handles.
  The `CallRecorder` extraction is not speculative — it is a prerequisite the spec's source document
  explicitly calls for (grounding the consistency check in real tool activity, which the existing
  purely-textual Captain-style detector cannot do), and reuses `PlaygroundRunner`'s already-working
  `execute`-wrapping pattern rather than inventing a second mechanism (e.g. inspecting
  `chat.messages`/`RubyLLM::ToolCall`).
- **III. Adhere to Established Conventions** — PASS. RuboCop applies to all new/modified Ruby
  files (compact `Custom::Scout::X` class definitions, matching `agent_runner.rb`/
  `playground_runner.rb`); specs added under `custom/spec/services/custom/scout/...` per
  convention, favoring `let`/per-example setup over bespoke helpers.
- **IV. Safe, Reversible Change Management** — PASS. The migration is additive and reversible
  (`down` removes the column, mirroring `AddPipelineFieldsToIchatrScouts`). No destructive
  operations. The flag defaults `false`, so the change is inert until an operator opts in.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — N/A/PASS. Scout (`custom/`) has no Enterprise
  counterpart; this feature reads Captain's enterprise code as reference only and adds nothing to
  `enterprise/`.

No violations. Complexity Tracking is not needed.

**Post-Phase 1 re-check**: `data-model.md` confirms the only schema change is the one additive
boolean column plus two new plain-Ruby `RubyLLM::Schema` subclasses (not persisted entities);
`research.md` confirms the `CallRecorder` extraction preserves `PlaygroundRunner`'s existing
recorded-call shape and hooks at the same `execute`-wrapping layer already proven in production,
and that `with_schema` + `with_tool` + `instrument_llm_call` compose the same way Phase 057 already
validated for `AgentRunner`'s own chat; `quickstart.md` introduces no new endpoint or contract. All
five gates above still PASS unchanged. A parallel cross-validation pass (fork/upstream code
re-read, `ruby_llm`/`ruby_llm-schema` docs, and public-code search) corrected one shape detail
(`CallRecorder`'s `simulated:` key, now reflected in `data-model.md`) and flagged one pre-existing,
out-of-scope risk worth an empirical check during implementation — Gemini's API-level tolerance of
`with_schema` + `with_tool` together, inherited unchanged from Phase 057 (see research.md §4's
"Flagged risk" note) — neither changes this feature's design or Constitution Check outcome.

## Project Structure

### Documentation (this feature)

```text
specs/058-scout-response-auditor/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

No `contracts/` directory: this feature adds no new endpoint, public API, or frontend contract —
it only changes what happens inside `AgentRunner`'s existing turn-processing flow before the
already-existing reply-dispatch/handoff mechanisms fire.

### Source Code (repository root)

```text
db/migrate/
└── <timestamp>_add_response_auditor_flag_to_ichatr_scouts.rb
                                     # NEW: feature_response_auditor boolean, null: false,
                                     #   default: false — same shape as the existing
                                     #   feature_memory column (21260819000005_...)

custom/app/services/custom/scout/
├── tools/
│   └── call_recorder.rb            # NEW: Custom::Scout::Tools::CallRecorder — module extracted
│                                    #   from PlaygroundRunner's wrap_tool/execute_and_record;
│                                    #   wraps each tool's #execute (below BaseTool#call's existing
│                                    #   instrument_tool_call layer) and appends
│                                    #   {tool_name:, arguments:, simulated:, result:} or
│                                    #   {..., error:} to a recorded_tool_calls list scoped to the
│                                    #   caller — simulated: is supplied by the includer (Playground
│                                    #   passes its existing tool_name != 'call_custom_api' rule,
│                                    #   AgentRunner always passes false)
├── action_classifier_service.rb    # NEW: Custom::Scout::ActionClassifierService — independent
│                                    #   LLM call (@scout.llm_chat(temperature: 0.0)) deciding
│                                    #   continue/handoff via with_schema; Scout-specific commercial
│                                    #   reasons (not Captain's support-domain reason list)
├── action_classifier_schema.rb     # NEW: Custom::Scout::ActionClassifierSchema < RubyLLM::Schema
│                                    #   (action: continue|handoff, action_reason: enum)
├── claim_consistency_service.rb    # NEW: Custom::Scout::ClaimConsistencyService — independent LLM
│                                    #   call grounded in message history + drafted reply text +
│                                    #   the turn's recorded_tool_calls; decides
│                                    #   safe|false_promise|false_completed_action via with_schema
├── claim_consistency_schema.rb     # NEW: Custom::Scout::ClaimConsistencySchema < RubyLLM::Schema
├── response_auditor.rb             # NEW: Custom::Scout::ResponseAuditor — orchestrates both
│                                    #   classifiers + the repair-and-reverify loop; called once
│                                    #   from AgentRunner#process_response
├── agent_runner.rb                 # MODIFIED: includes CallRecorder, wraps build_tools' tools for
│                                    #   recording, and calls ResponseAuditor once in
│                                    #   process_response (after parse succeeds, before
│                                    #   dispatch_outgoing_reply) when @scout.feature_response_auditor?
└── playground_runner.rb            # MODIFIED: replaces private wrap_tool/execute_and_record with
                                     #   `include Custom::Scout::Tools::CallRecorder` — no behavior
                                     #   change, same recorded_tool_calls shape consumers rely on

custom/spec/services/custom/scout/
├── tools/
│   └── call_recorder_spec.rb       # NEW
├── action_classifier_service_spec.rb   # NEW
├── claim_consistency_service_spec.rb   # NEW
├── response_auditor_spec.rb            # NEW
├── agent_runner_spec.rb                # EXTENDED: flag on/off behavior, repair-and-reverify
│                                        #   escalation, no-extra-message-creation, single
│                                        #   responses_consumed increment
└── playground_runner_spec.rb           # RE-RUN as regression check: recorded_tool_calls shape
                                         #   unchanged after the CallRecorder extraction
```

**Structure Decision**: Backend-only change, entirely inside the fork's isolated `custom/` tree
(Constitution Principle I), plus one additive migration under the constitution's stated `db/migrate/`
exception. No `frontend/`, `backend/`, or mobile split applies — this changes what
`Custom::Scout::AgentRunner` does with the reply it already gets from the already-integrated
`ruby_llm` gem before dispatching it, using the same `RubyLLM::Schema`/`with_schema` pattern Phase
057 established and the same tool-call-recording pattern `PlaygroundRunner` already uses in
production for simulation.

## Complexity Tracking

No violations to record — the Constitution Check above passed cleanly with no gates requiring
justification.
