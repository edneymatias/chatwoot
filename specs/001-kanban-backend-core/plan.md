# Implementation Plan: Kanban Backend Core — Opportunities & Pipeline Stages

**Branch**: `001-kanban-backend-core` | **Date**: 2026-07-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-kanban-backend-core/spec.md`

## Summary

Build the persisted data model and manual CRUD API for a Kanban-style Opportunity/Pipeline
Stage system, isolated in a `custom/` top-level tree (mirroring the `enterprise/` overlay
convention) so it never conflicts with upstream Chatwoot merges. An `Opportunity` belongs to a
`Contact` (not a `Conversation`) and moves through admin-configured `PipelineStage`s, scoped per
account. No automation, frontend, or realtime broadcast is built in this phase — verification is
via Rails console/`rails runner` and request/model specs only.

## Technical Context

**Language/Version**: Ruby (Rails 7.1, matches repo's existing `Gemfile`/`schema.rb` version)

**Primary Dependencies**: Rails (ActiveRecord, ActionController), Pundit (existing policy
framework — see `app/policies/*`), existing `Featurable` account concern
(`app/models/concerns/featurable.rb`) for the feature flag

**Storage**: PostgreSQL (existing `db/schema.rb`), two new additive tables:
`matias_pipeline_stages`, `matias_opportunities`

**Testing**: RSpec (`bundle exec rspec`), run inside the `rails` container per `CLAUDE.md`
(`docker compose exec rails bundle exec rspec ...`); no JS/Vue testing needed this phase (no
frontend code)

**Target Platform**: Existing Chatwoot Rails monolith, Docker/Podman Compose dev stack

**Project Type**: Web application (Rails API layer only, this phase — no frontend)

**Performance Goals**: N/A — no performance targets beyond existing API conventions
(standard per-request Pundit scoping, paginated `index`); this phase has no realtime or
bulk-load requirements (deferred to Phase 4)

**Constraints**: Zero edits to existing core tables; the only core-file edit permitted is the
`config/application.rb` eager-load-path wiring (FR-001); all new code lives under `custom/`
except the two Rails-mandated migrations under `db/migrate/`

**Scale/Scope**: Single account-scoped pipeline (no multi-pipeline support this phase); 2 models,
2 policies, 2 controllers, 2 migrations, 1 concern, 1 feature flag entry

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First (NON-NEGOTIABLE)**: PASS. All new domain code lives under
  `custom/app/**`, wired via a 3-line addition to `config/application.rb` mirroring the existing
  `enterprise/` block exactly (FR-001). Tables use a `matias_` prefix to avoid future upstream
  collisions (FR-010). The only files outside `custom/` are the two mandatory `db/migrate/`
  migrations (the one constitution-sanctioned exception) and the `config/application.rb`/
  `config/features.yml` edits, both additive line-level changes, not restructuring. `Contact`
  gains `has_many :opportunities` via the existing `include_mod_with('Concerns::Contact')` hook
  already present at the bottom of `app/models/contact.rb` — zero edits to that file (FR-011).
- **II. Smallest Production-Ready Change**: PASS. Scope is deliberately capped to data model +
  manual CRUD + policies; no automation, frontend, or realtime code is introduced (explicitly out
  of scope, deferred to Phases 2–4). No speculative multi-pipeline support, no reordering API
  beyond simple `update`, no state-machine validation for `status` (per clarified answers).
- **III. Adhere to Established Conventions**: PASS. Controllers/policies mirror existing patterns
  (`MacrosController`/`CustomAttributeDefinitionsController` shape for nested `accounts` routes,
  `CustomAttributeDefinitionPolicy` shape for admin-only Pundit policies, `ConversationPolicy`'s
  `inbox_access?`/`team_access?` reused — not reimplemented — for FR-006).
- **IV. Safe, Reversible Change Management**: PASS. Both migrations are `create_table` with a
  `drop_table` `down` (or plain reversible `change`), touching no existing table.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS (no Enterprise action needed). This is a
  personal-fork-only feature under `custom/`, not a core OSS feature Enterprise would extend or
  override; no `enterprise/` counterpart is required. Documented here per the constitution's
  requirement to make this decision explicit.

No violations. Nothing to record in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/001-kanban-backend-core/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   └── opportunities-api.md
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
custom/
├── app/
│   ├── models/
│   │   ├── pipeline_stage.rb
│   │   ├── opportunity.rb
│   │   └── custom/
│   │       └── concerns/
│   │           └── contact.rb            # Contact.include_mod_with('Concerns::Contact') hook
│   ├── policies/
│   │   ├── pipeline_stage_policy.rb
│   │   └── opportunity_policy.rb
│   └── controllers/
│       └── api/v1/accounts/
│           ├── pipeline_stages_controller.rb
│           └── opportunities_controller.rb
└── lib/                                   # present for parity with enterprise/lib; empty unless needed

db/migrate/
├── <timestamp>_create_matias_pipeline_stages.rb
└── <timestamp>_create_matias_opportunities.rb

config/
├── application.rb        # +3 lines: custom/lib, custom/app/** eager_load_paths (mirrors enterprise/ block)
└── features.yml           # +1 entry: `opportunities` flag (feature_flags_ext_1 column)

config/routes.rb           # +2 nested `resources` under existing `accounts` member block

spec/
├── models/ (opportunity_spec.rb, pipeline_stage_spec.rb)
├── policies/ (opportunity_policy_spec.rb, pipeline_stage_policy_spec.rb)
└── requests/api/v1/accounts/
    ├── opportunities_controller_spec.rb
    └── pipeline_stages_controller_spec.rb
```

**Structure Decision**: Follows the existing Chatwoot Rails monolith layout, isolating all new
domain code under a sibling `custom/` tree to the existing `enterprise/` overlay (per constitution
Principle I). No `frontend/`/`backend/` split applies — this is a backend-only phase within the
single existing Rails app. The two Rails-mandated migrations are the only files that cannot live
under `custom/` (Rails only loads migrations from `db/migrate/`).

## Complexity Tracking

*No violations — this section intentionally left without entries.*
