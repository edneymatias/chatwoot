# Implementation Plan: Scout Core & Data Model

**Branch**: `042-scout-core-data-model` | **Date**: 2026-08-19 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/042-scout-core-data-model/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Phase 01 of the Scout AI agent engine: introduce the `Scout`, `ScoutInbox`, and `ScoutTool`
account-scoped data model, extend `Opportunity` with an optional `lost_reason`, and prove — via
console/seed only, no UI or message pipeline — that a Scout's stored `provider`/`model_name`/
`api_key_override` can be resolved into a working multi-provider LLM client (`ruby_llm`) capable
of completing one real tool-calling round-trip. Credentials (`Scout#api_key_override`,
`ScoutTool#auth_headers`) are encrypted at rest unconditionally, deliberately deviating from this
codebase's existing `encrypts :field if Chatwoot.encryption_configured?` guard convention so that
saves raise instead of silently persisting plaintext when encryption isn't configured. All new
tables live under the `ichatr_` prefix in `custom/`, following the same migration and model
conventions as the existing Kanban/Opportunity feature set.

## Technical Context

**Language/Version**: Ruby on Rails (repo-wide version, `custom/` module conventions per
`CLAUDE.md`)

**Primary Dependencies**: `ruby_llm` 1.15.0 (`RubyLLM.context` per-call scoping), `ruby_llm-schema`
0.3.0, Rails `ActiveRecord::Encryption` (built-in, no new gem)

**Storage**: PostgreSQL — new `ichatr_scouts`, `ichatr_scout_inboxes`, `ichatr_scout_tools` tables,
plus an added `lost_reason` column on the existing `ichatr_opportunities` table

**Testing**: RSpec (`custom/spec/models/`), run via `docker compose exec rails env -u
FRONTEND_URL RAILS_ENV=test bundle exec rspec`

**Target Platform**: Server-side only (Rails console/seed scripts) — no frontend surface in this
phase

**Project Type**: Web application backend module (`custom/` extension tree within the existing
Chatwoot Rails monolith)

**Performance Goals**: N/A — this phase is not on any request-serving hot path; success is
correctness of the one-shot console-driven round-trip (SC-001), not throughput or latency

**Constraints**: No custom multi-provider gateway/abstraction (must reuse `ruby_llm` directly, per
spec.md Assumptions); no core (non-`ichatr_`) table modifications (FR-009); migrations must apply
and roll back cleanly with zero manual cleanup (FR-010, SC-005); credential fields must fail
closed, not open, when encryption is unconfigured (FR-005/006, SC-003)

**Scale/Scope**: 3 new models + 3 migrations (2 tables + 1 pivot table) + 1 column addition on an
existing model; no controllers, jobs, or background processing introduced in this phase

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Upstream Compatibility First (NON-NEGOTIABLE) | PASS | All new tables/models live in `custom/` under the `ichatr_` prefix; `Opportunity#lost_reason` is an additive column on an existing `ichatr_` (fork-owned) table, not a core table — FR-009 makes this explicit. |
| II. Smallest Production-Ready Change | PASS | Scope is deliberately narrowed to data model + one manual LLM round-trip proof; no UI, no pipeline, no native tools, no billing enforcement are built ahead of need (see spec.md Assumptions). |
| III. Adhere to Established Conventions | PASS, with one documented deviation | Migration/model/enum conventions mirror `Opportunity`/`PipelineStage` exactly (see research.md §5–6). The one deviation — unconditional `encrypts` instead of the codebase-wide `if Chatwoot.encryption_configured?` guard — is intentional and required by FR-005/006; documented with rationale in research.md §2 rather than silently diverging. |
| IV. Safe, Reversible Change Management | PASS | Migrations follow the established `up`/`down` (non-`change`) pattern for clean rollback (FR-010); `ScoutInbox` cascade vs. `ScoutTool` independence is explicitly scoped to avoid destructive side effects on deletion. |
| V. Dual-Tree Awareness (OSS + Enterprise) | PASS | No enterprise override or extension point is needed — Scout is a wholly new `custom/` feature with no core/enterprise controller, policy, or model being modified. `ScoutInbox`/`ScoutTool` ownership rules were validated directly against Captain's enterprise precedent (research.md §4) to keep behavior consistent without touching `enterprise/` code. |

## Project Structure

### Documentation (this feature)

```text
specs/042-scout-core-data-model/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

No `contracts/` directory is generated for this feature — Phase 01 has no controller, API, or UI
surface (per spec.md Assumptions: "no user-facing UI ... created and verified via console or seed
scripts only"); the only externally-facing contract in this phase is the `ruby_llm`
provider/tool-calling API, which is a third-party dependency, not a contract this feature defines.

### Source Code (repository root)

```text
custom/
├── app/
│   └── models/
│       ├── scout.rb                  # new
│       ├── scout_inbox.rb            # new
│       ├── scout_tool.rb             # new
│       └── opportunity.rb            # modified (lost_reason accessor already inherited from column)
└── spec/
    └── models/
        ├── scout_spec.rb             # new
        ├── scout_inbox_spec.rb       # new
        └── scout_tool_spec.rb        # new

db/
└── migrate/
    ├── 21260819xxxxxx_create_ichatr_scouts.rb            # new
    ├── 21260819xxxxxx_create_ichatr_scout_inboxes.rb     # new
    ├── 21260819xxxxxx_create_ichatr_scout_tools.rb       # new
    └── 21260819xxxxxx_add_lost_reason_to_ichatr_opportunities.rb  # new
```

**Structure Decision**: Single-project layout (this is a Rails monolith, not a multi-project
repo). All new code lives inside the fork's existing `custom/app/models/` and `custom/spec/`
trees, following the exact same flat-class, `ichatr_`-prefixed-table pattern already used by
`Opportunity`/`PipelineStage`/`OpportunityActivity` (see `custom/app/models/opportunity.rb`,
`db/migrate/21260817140000_create_ichatr_opportunity_activities.rb`). No new top-level directories
are introduced.

## Complexity Tracking

*No violations — Constitution Check passed cleanly with one documented, justified convention
deviation (unconditional `encrypts`, see research.md §2), not a structural complexity violation.*
