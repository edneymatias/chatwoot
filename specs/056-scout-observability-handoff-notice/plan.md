# Implementation Plan: Scout Observability & Handoff Notice

**Branch**: `056-scout-observability-handoff-notice` | **Date**: 2026-08-28 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/056-scout-observability-handoff-notice/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Give Scout (the fork's own AI assistant) the same operational visibility Captain already has, and
close the silent-handoff gap in both of Scout's exit paths. Concretely: wrap Scout's main LLM call
and every tool call with the existing `Integrations::LlmInstrumentation` module (the same
OTel/Langfuse pipeline `Captain::Assistant::AgentRunnerService` and `Captain::ToolInstrumentation`
already use, gated by `ChatwootApp.otel_enabled?` so it is a no-op when unconfigured), and add one
fixed, translated public `Messages::MessageBuilder` message — sent before `conversation.bot_handoff!`
— to both `Custom::Scout::AgentRunner#perform_fail_safe_handoff` and
`Custom::Scout::HandoffService#perform`. The fail-safe half of this mirrors an existing, direct
precedent (`enterprise/app/services/enterprise/message_templates/hook_execution_service.rb#perform_handoff`);
the explicit-handoff half has no such precedent to mirror — Captain V2's own explicit handoff tool
still only creates a private note today, so Scout is closing a gap Captain hasn't closed either,
not copying an existing behavior for that specific path (see `research.md` §3).
No new UI, endpoint, or persisted data model — instrumentation surfaces exclusively through the
existing external Langfuse UI, and the transfer message reuses the existing private-note flow's
sibling (`Messages::MessageBuilder`, `private: false`) already used for Scout's normal replies.

## Technical Context

**Language/Version**: Ruby 3.4.4 (Rails, per `Gemfile`/`.ruby-version`)

**Primary Dependencies**: `Integrations::LlmInstrumentation` (`lib/integrations/llm_instrumentation.rb`,
OpenTelemetry → Langfuse export, already used by Captain), `RubyLLM::Tool` (base class for all
`Custom::Scout::Tools::*`), `Messages::MessageBuilder` (existing message-creation service, already
used by Scout for its own replies and by `AgentRunner`/`HandoffService` for private notes)

**Storage**: N/A — no new tables/models. Trace data is exported externally to Langfuse via the
existing OTel exporter (same account-configured `OTEL_PROVIDER`/`LANGFUSE_*` `InstallationConfig`
keys Captain already uses); the transfer message is a normal `Message` row via the existing
`Messages::MessageBuilder` path.

**Testing**: RSpec, per repo convention (`custom/spec/services/custom/scout/...`), run via
`docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/...`

**Target Platform**: Rails app server (self-hosted, this fork's Docker/Podman stack)

**Project Type**: Web service (Rails monolith backend feature; explicitly no new frontend UI per
spec FR-008 — Out of Scope)

**Performance Goals**: Zero added latency/cost when the trace integration is not configured —
reuses the existing `return yield unless ChatwootApp.otel_enabled?` short-circuit already present
in `Integrations::LlmInstrumentation`, so this is inherited for free rather than re-implemented
(spec FR-007, SC-004)

**Constraints**: Must not change the request/response contract of `Custom::Scout::Tools::*#execute`
(the string/hash each tool returns is consumed directly by `RubyLLM` and, ultimately, the model) —
instrumentation wraps the call, it does not alter what it returns. Must not edit the shared
`lib/integrations/llm_instrumentation.rb` or `app/builders/messages/message_builder.rb` bodies —
both are used purely as existing extension points, consistent with how Captain already consumes
them (Constitution Principle I).

**Scale/Scope**: Single-tenant self-hosted install. Touches three existing Scout files
(`Custom::Scout::AgentRunner`, `Custom::Scout::Tools::BaseTool`, `Custom::Scout::HandoffService`)
plus additive keys in `config/locales/en.yml` and `config/locales/pt_BR.yml`. No migrations.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. No upstream/core file body is edited. The feature
  consumes two already-shared extension points exactly as Captain does today:
  `Integrations::LlmInstrumentation` (`include` + `instrument_llm_call`/`instrument_agent_session`/
  `instrument_tool_call`, same shape as `agent_runner_service.rb` and `Captain::ToolInstrumentation`)
  and `Messages::MessageBuilder` (same call shape Scout already uses for its own outgoing replies).
  All modified files (`AgentRunner`, `BaseTool`, `HandoffService`) are Scout's own fork-owned
  classes under `custom/`, not upstream files.
- **II. Smallest Production-Ready Change** — PASS. Instrumentation is added at the one existing
  choke point each concern already has (`AgentRunner#execute_chat` for the LLM call,
  `Custom::Scout::Tools::BaseTool` for every tool call — inherited by all seven tools, so no
  per-tool edits), reusing the `otel_enabled?` guard that already exists rather than adding a new
  one. No speculative configurability is introduced (handoff text stays fixed, per spec FR-004).
- **III. Adhere to Established Conventions** — PASS. RuboCop line-length/complexity limits apply
  to the three modified files; i18n additions go in `en.yml` and `pt_BR.yml` together, per this
  fork's translation convention (no Crowdin); specs extend the existing
  `custom/spec/services/custom/scout/{agent_runner,handoff_service}_spec.rb`.
- **IV. Safe, Reversible Change Management** — PASS. No migrations, no destructive operations; the
  change is a pure code addition wrapped in an existing feature-flag-equivalent gate (`otel_enabled?`).
- **V. Dual-Tree Awareness (OSS + Enterprise)** — N/A/PASS. Scout (`custom/`) has no Enterprise
  counterpart to keep in sync — it is fork-exclusive, not an upstream/Enterprise feature pair. The
  two shared files it calls into (`lib/integrations/llm_instrumentation.rb`,
  `app/builders/messages/message_builder.rb`) are consumed unchanged, so there is no contract to
  keep stable across editions beyond "don't edit them."

No violations. Complexity Tracking is not needed.

**Post-Phase 1 re-check**: `data-model.md` confirms no new tables, columns, or models (the three
"Key Entities" from the spec are an OTel trace, an OTel span, and a plain `Message` row created via
the already-used `Messages::MessageBuilder`), `research.md` confirms every integration point is an
existing extension point already consumed the same way by Captain, and `quickstart.md` introduces
no new endpoint or contract. All five gates above still PASS unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/056-scout-observability-handoff-notice/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

No `contracts/` directory: this feature adds no new endpoint, public API, or frontend contract —
it only wraps existing internal call points (see Outline step 2, "Skip if project is purely
internal").

### Source Code (repository root)

```text
custom/app/services/custom/scout/
├── agent_runner.rb                 # MODIFIED: include Integrations::LlmInstrumentation;
│                                    #   wrap execute_chat (instrument_agent_session /
│                                    #   instrument_llm_call) and perform_fail_safe_handoff
│                                    #   (public transfer message before bot_handoff!)
├── handoff_service.rb              # MODIFIED: public transfer message before bot_handoff!
│                                    #   in perform / perform_handoff
└── tools/
    └── base_tool.rb                # MODIFIED: override #call with instrument_tool_call,
                                     #   inherited by all Custom::Scout::Tools::* subclasses

custom/spec/services/custom/scout/
├── agent_runner_spec.rb            # EXTENDED: assert public message sent on fail-safe path;
│                                    #   assert instrumentation is invoked / no-ops correctly
├── handoff_service_spec.rb         # EXTENDED: assert public message sent on explicit handoff
└── tools/
    └── base_tool_spec.rb           # NEW (or extended if present): assert instrument_tool_call
                                     #   wraps #execute for a representative tool

config/locales/
├── en.yml                          # ADDITIVE: new key for the fixed handoff transfer message
└── pt_BR.yml                       # ADDITIVE: same key, pt-BR translation
```

**Structure Decision**: This is a backend-only change inside the existing Rails monolith, entirely
within the fork's isolated `custom/` tree (Constitution Principle I) plus additive i18n keys in the
two locale files already used for Scout-facing strings. No `frontend/`, `backend/`, or mobile split
applies — Scout has no dedicated UI for this feature, and the two shared library files it calls
into (`lib/integrations/llm_instrumentation.rb`, `app/builders/messages/message_builder.rb`) are
consumed as-is, not modified.

## Complexity Tracking

No violations to record — the Constitution Check above passed cleanly with no gates requiring
justification.
