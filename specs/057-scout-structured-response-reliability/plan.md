# Implementation Plan: Scout Structured Response Reliability

**Branch**: `057-scout-structured-response-reliability` | **Date**: 2026-08-28 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/057-scout-structured-response-reliability/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Real testing showed Scout failing to parse the model's structured response on effectively every
turn (3/3 conversations), because today's guardrail (Phase 08) only *instructs* the JSON
`{"reasoning": ..., "response": ...}` format in the prompt text — nothing enforces it at the API
level, so the model is free to drift into plain text. The fix: define
`Custom::Scout::ResponseSchema < RubyLLM::Schema` (two string fields, `reasoning`/`response` —
same two fields the prompt already asks for) and call `chat.with_schema(...)` in
`Custom::Scout::AgentRunner`, so the configured provider enforces that shape at the API level
instead of hoping the model complies. This exact pattern — `RubyLLM::Schema` subclass +
`chat.with_schema(...)` — is already used by Captain's own main agent response
(`Captain::ResponseSchema`, wired through `Agentable#agent_response_schema`), so this is not a new
architecture for the codebase, only a new consumer of an existing one. The `ruby_llm-schema` gem is
already a direct Gemfile dependency (no new dependency to add). The existing "fail closed" contract
(never show raw/malformed content, fall back to the existing fail-safe handoff) is preserved
unchanged — the only code change needed is teaching `parse_structured_response` to accept the
already-parsed `Hash` that `RubyLLM` returns when schema mode succeeds, in addition to the raw
`String` it already handles for the fallback/unsupported-provider case.

## Technical Context

**Language/Version**: Ruby 3.4.4 (Rails, per `Gemfile`/`.ruby-version`)

**Primary Dependencies**: `ruby_llm` 1.15.0 (already used by `AgentRunner`/`BaseTool`), `ruby_llm-schema`
0.3.0 (`RubyLLM::Schema` DSL — already a direct `Gemfile` dependency, confirmed in `Gemfile.lock`,
no new dependency needed), `RubyLLM::Chat#with_schema` (existing gem API, confirmed present and
already consumed the same way by `Captain::BaseTaskService#build_chat` and `Captain::ResponseSchema`)

**Storage**: N/A — no new tables/models. The schema is a plain Ruby class (`RubyLLM::Schema`
subclass), not a persisted entity.

**Testing**: RSpec, per repo convention (`custom/spec/services/custom/scout/...`), run via
`docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/...`

**Target Platform**: Rails app server (self-hosted, this fork's Docker/Podman stack)

**Project Type**: Web service (Rails monolith backend feature; no new UI/endpoint)

**Performance Goals**: No explicit latency target set by the spec; schema-constrained decoding is a
standard capability of both providers Scout supports (OpenAI Structured Outputs, Gemini
`responseSchema`/`responseJsonSchema`) and is not expected to meaningfully change response latency
relative to today's prompt-only approach — not a design driver for this feature.

**Constraints**: Must preserve FR-003's fail-closed guarantee exactly (Constitution alignment with
the prior Phase 08 decision, "falha de parsing = falha fechada" — never expose raw/malformed model
text to the customer). Must not break tool-calling (FR-004) — confirmed via gem source that both
supported providers accept `schema` and `tools` in the same request without conflict. Must not
edit the shared `ruby_llm`/`ruby_llm-schema` gems or `enterprise/lib/captain/response_schema.rb` —
consumed as extension points/precedent only.

**Scale/Scope**: Single-tenant self-hosted install. Touches one new file
(`Custom::Scout::ResponseSchema`) and two existing Scout files (`AgentRunner`'s chat setup and its
`parse_structured_response`). No migrations.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. No upstream/core file is edited. The new
  `Custom::Scout::ResponseSchema` lives in `custom/`, structurally mirroring (not copying text
  from, same licensing caveat as prior Scout phases) `Captain::ResponseSchema` — an existing
  extension point (`RubyLLM::Schema` + `chat.with_schema`) already consumed the same way by
  `Captain::BaseTaskService#build_chat`. The `ruby_llm-schema` gem is already vendored — no new
  dependency introduced.
- **II. Smallest Production-Ready Change** — PASS. One new small schema class (mirrors an existing
  one almost field-for-field) plus a type-check branch in the one place responses are already
  parsed (`parse_structured_response`). No speculative per-provider capability-detection code is
  added in Scout — the gem itself already handles per-provider schema support/fallback internally
  for both providers Scout can be configured with (confirmed by reading the provider adapters).
- **III. Adhere to Established Conventions** — PASS. RuboCop applies to the new/modified files;
  specs extend `custom/spec/services/custom/scout/agent_runner_spec.rb` and add a spec for the new
  schema class, per repo convention.
- **IV. Safe, Reversible Change Management** — PASS. No migrations, no destructive operations.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — N/A/PASS. Scout (`custom/`) has no Enterprise
  counterpart. `ruby_llm-schema` is a plain (non-enterprise-gated) Gemfile dependency.

No violations. Complexity Tracking is not needed.

**Post-Phase 1 re-check**: `data-model.md` confirms the only "entity" is a plain Ruby schema class,
no new tables/columns; `research.md` confirms `with_schema` + `with_tool` coexist without conflict
in both providers Scout supports, and that this exact pattern already runs in production for
Captain's own main agent response; `quickstart.md` introduces no new endpoint or contract. All
five gates above still PASS unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/057-scout-structured-response-reliability/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

No `contracts/` directory: this feature adds no new endpoint, public API, or frontend contract —
it only changes how Scout talks to the LLM provider it already calls.

### Source Code (repository root)

```text
custom/app/services/custom/scout/
├── response_schema.rb              # NEW: Custom::Scout::ResponseSchema < RubyLLM::Schema
│                                    #   (string :reasoning, string :response) — mirrors the shape
│                                    #   of enterprise/lib/captain/response_schema.rb
└── agent_runner.rb                 # MODIFIED: chat.with_schema(Custom::Scout::ResponseSchema)
                                     #   in generate_and_process_response; parse_structured_response
                                     #   accepts an already-parsed Hash (schema mode) in addition to
                                     #   the existing String/fenced-JSON fallback path

custom/spec/services/custom/scout/
├── response_schema_spec.rb         # NEW: schema shape/field assertions
└── agent_runner_spec.rb            # EXTENDED: schema is applied to the chat; parsing handles both
                                     #   Hash (schema mode) and String (fallback) response.content;
                                     #   tool-calling still works with schema active; fail-closed
                                     #   behavior (FR-003) unchanged when a usable response still
                                     #   can't be obtained
```

**Structure Decision**: Backend-only change, entirely inside the fork's isolated `custom/` tree
(Constitution Principle I). No `frontend/`, `backend/`, or mobile split applies — this changes how
`Custom::Scout::AgentRunner` talks to the already-integrated `ruby_llm` gem, nothing user-facing
beyond conversations succeeding instead of failing over to a human.

## Complexity Tracking

No violations to record — the Constitution Check above passed cleanly with no gates requiring
justification.
