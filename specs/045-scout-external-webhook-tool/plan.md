# Implementation Plan: Scout External REST/Webhook Tool

**Branch**: `045-scout-external-webhook-tool` | **Date**: 2026-08-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/045-scout-external-webhook-tool/spec.md`

## Summary

Add a native `call_custom_api(tool_id, payload)` LLM tool, following the existing
`Custom::Scout::Tools::BaseTool` pattern, that resolves an account-scoped, enabled `ScoutTool`,
validates the LLM-supplied payload against its `parameters_schema`, executes the configured HTTP
call through the app's centralized `SafeFetch` fetcher (reusing the same timeout/response-size
limits already proven in production by `Captain::Tools::HttpTool`), and returns either the
external response or a structured failure description to the LLM within the same conversation
turn — never raising an unhandled error out of the tool-calling loop. Because the tool is a single
static `call_custom_api` entry point rather than one generated `RubyLLM` tool per external
integration, the tool itself is also responsible for making the LLM aware of which `tool_id`s are
currently callable: `CallCustomApi` overrides its instance-level `description` to list the calling
account's enabled `ScoutTool`s (id, name, description, parameter schema) at call time, reusing the
same account-scoped, `enabled: true` query as tool resolution (see [research.md](research.md) §6).

## Technical Context

**Language/Version**: Ruby (Rails, matching repo-wide version)

**Primary Dependencies**: `RubyLLM::Tool` (Scout tool-calling base, via `Custom::Scout::Tools::BaseTool`), `SafeFetch` (`lib/safe_fetch.rb`, centralized HTTP fetcher already used by `Captain::Tools::HttpTool`), `ActiveRecord` (existing `ScoutTool` model), `JSONSchemer` (already a project dependency, used elsewhere via `app/models/concerns/json_schema_validator.rb`) for `parameters_schema` validation

**Storage**: PostgreSQL via existing `ichatr_scout_tools` table (`ScoutTool` model) — no schema changes

**Testing**: RSpec (`bundle exec rspec`), following existing `custom/spec/` conventions for Scout tool specs

**Target Platform**: Server-side Rails app (Sidekiq/Puma), no client-facing surface

**Project Type**: Single Rails app — backend service addition under `custom/`

**Performance Goals**: External call must resolve within the SafeFetch-enforced bound (2s connect + 20s read) so the conversation turn completes within a predictable, bounded wait

**Constraints**: 2-second connection timeout, 20-second read timeout, 1 MB response size cap (all inherited from `SafeFetch`/`Captain::Tools::HttpTool` precedent per spec Clarifications); must never raise out of the tool call; must never cross account boundaries

**Scale/Scope**: One new native tool class plus its wiring into the existing Scout tool registry/loop; no new tables, no new UI, no new background jobs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. New code lives entirely under `custom/app/services/custom/scout/tools/`, mirroring the existing native tool files (`create_private_note.rb`, `handover_to_human.rb`, etc.). No upstream/core file is modified. `ScoutTool` (the data model this feature executes against) already exists from a prior phase; this feature only adds a service class and its registration.
- **II. Smallest Production-Ready Change**: PASS. No retries, circuit breakers, queues, or new UI are introduced (explicitly out of scope per spec Assumptions). Timeout/size limits are reused as-is from `SafeFetch` defaults rather than inventing new configuration.
- **III. Adhere to Established Conventions**: PASS. Follows the existing `Custom::Scout::Tools::BaseTool` subclass pattern, RuboCop conventions, and RSpec `let`-based spec style already used by sibling tool specs.
- **IV. Safe, Reversible Change Management**: PASS. Purely additive — new tool class, no destructive migrations, no changes to existing tool behavior.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS with a documented decision — Scout is a `custom/`-only, non-Enterprise feature (per the fork's explicit architectural decision in `spec60.md`), so there is no `enterprise/` counterpart to extend. The closest Enterprise analog, `Captain::Tools::HttpTool`, is treated as a read-only precedent for config values (timeout/size), not a shared code path — the two tools intentionally remain independent implementations on separate tool-calling frameworks (`RubyLLM::Tool` vs `Agents::Tool`), consistent with prior phases of this initiative.

No violations requiring Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/045-scout-external-webhook-tool/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── checklists/
    └── requirements.md  # Spec quality checklist (/speckit-specify command)
```

No `contracts/` directory: this feature exposes no public API or endpoint. It is an internal
LLM-callable tool consumed only by `Scout::AgentRunner`'s existing tool-calling loop, matching the
precedent set by sibling Scout-tool phases (042/043/044), none of which produced a `contracts/`
artifact either.

### Source Code (repository root)

```text
custom/
├── app/
│   ├── models/
│   │   └── scout_tool.rb                              # existing, unchanged
│   └── services/
│       └── custom/
│           └── scout/
│               ├── agent_runner.rb                     # existing; registers native tools
│               └── tools/
│                   ├── base_tool.rb                     # existing, unchanged
│                   ├── create_private_note.rb           # existing, sibling pattern
│                   ├── handover_to_human.rb              # existing, sibling pattern
│                   ├── manage_opportunity.rb            # existing, sibling pattern
│                   ├── move_opportunity_stage.rb        # existing, sibling pattern
│                   ├── update_contact.rb                # existing, sibling pattern
│                   └── call_custom_api.rb               # NEW — this feature
└── spec/
    └── services/
        └── custom/
            └── scout/
                └── tools/
                    └── call_custom_api_spec.rb          # NEW — this feature (if specs requested)
```

**Structure Decision**: Single Rails app, fork-isolated `custom/` tree (per Constitution Principle
I). The new tool is one additional sibling file inside the already-established
`custom/app/services/custom/scout/tools/` directory, registered into the existing native-tool set
wherever `Scout::AgentRunner` (or its tool-list builder) currently enumerates the other five
native tools — no new top-level directory or wiring pattern is introduced.

## Complexity Tracking

*No Constitution Check violations — this section is intentionally empty.*
