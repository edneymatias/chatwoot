# Implementation Plan: Stage Dwell-Time Tracking

**Branch**: `014-stage-dwell-time-tracking` | **Date**: 2026-08-04 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/014-stage-dwell-time-tracking/spec.md`

## Summary

Add a per-opportunity stage-transition history table plus an optional per-stage
staleness threshold, and surface a "time in current stage" badge on the kanban
card (switching to an alert style when the stage's threshold is exceeded).
`Opportunity` gains `after_create`/`after_update` callbacks that write to the
new history table; `PipelineStage` gains a nullable `stale_after_days` column;
the existing pipeline stage update endpoint permits the new field; `KanbanCard.vue`
renders the badge using the existing `dynamicTime` helper and existing badge
color tokens. No new endpoints are needed — dwell time is derived at read time
from the transition table, not stored/edited directly.

## Technical Context

**Language/Version**: Ruby 3.x (Rails 7.1), Vue 3 (Composition API, `<script setup>`)

**Primary Dependencies**: Rails/ActiveRecord, Vuex (`pipelineStages` store module),
`vue-i18n`, existing `dynamicTime`/`shortTimestamp` helpers (`shared/helpers/timeHelper.js`)

**Storage**: PostgreSQL — new table `matias_opportunity_stage_changes`; new
column `matias_pipeline_stages.stale_after_days`

**Testing**: RSpec (`bundle exec rspec`) for model callbacks/controller params;
no JS unit tests planned beyond what the repo's lint/type checks already cover
(per CLAUDE.md, specs are not written unless explicitly asked)

**Target Platform**: Existing Chatwoot web dashboard (Rails API + Vue SPA)

**Project Type**: Web application (Rails backend + Vue frontend), fork-specific
feature living in the isolated `custom/` tree per constitution Principle I

**Performance Goals**: N/A beyond existing kanban board rendering performance —
dwell time is a single derived timestamp comparison per card, no additional
queries beyond the existing per-opportunity data already loaded

**Constraints**: Must not touch upstream/core tables or files; new table uses
the `matias_` prefix; hook into `Opportunity` uses existing model (already a
fork-owned model in `custom/`, so no `prepend_mod_with` needed) per constitution
Principle I

**Scale/Scope**: Single account's opportunity volume (source doc: zero
opportunities currently in the target account — no backfill needed)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. New table lives under the
  `matias_` prefix (mirrors `matias_opportunities`, `matias_pipeline_stages`).
  `Opportunity` and `PipelineStage` are already fork-owned models under
  `custom/app/models/`, so adding callbacks/columns to them is direct
  ownership, not a core-file edit — no `prepend_mod_with` indirection needed.
  The new migration is additive only (new table, new nullable column); no
  existing core table is altered.
- **II. Smallest Production-Ready Change**: PASS. No backfill job, no new
  CRUD endpoints for the transition table (it's write-only via callbacks,
  read-only via association), no historical dwell-time recalculation
  infrastructure — matches the source doc's explicit non-goals.
- **III. Adhere to Established Conventions**: PASS. Reuses `dynamicTime`
  helper, existing badge Tailwind tokens (`n-ruby-*`/amber equivalent),
  `<script setup>` Composition API, i18n keys in `en.yml`/`en.json`, strong
  params pattern already used in `PipelineStagesController`.
- **IV. Safe, Reversible Change Management**: PASS. Standard additive Rails
  migration, no destructive operations.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS (N/A). This entire
  feature lives in `custom/` and `matias_`-prefixed tables/routes, which is
  already outside both `app/` (OSS) and `enterprise/` — no enterprise
  override or extension point is needed since no OSS/Enterprise core surface
  is touched.

No violations — Complexity Tracking section not needed.

## Project Structure

### Documentation (this feature)

```text
specs/014-stage-dwell-time-tracking/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command) — N/A, no new endpoints
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
db/migrate/
├── <timestamp>_create_matias_opportunity_stage_changes.rb
└── <timestamp>_add_stale_after_days_to_matias_pipeline_stages.rb

custom/app/models/
├── opportunity.rb                      # add after_create/after_update callbacks
├── opportunity_stage_change.rb         # new model
└── pipeline_stage.rb                   # add has_many :stage_changes (via to_stage), stale_after_days attr already present via schema

custom/app/controllers/api/v1/accounts/
└── pipeline_stages_controller.rb       # permit :stale_after_days in pipeline_stage_params

app/javascript/dashboard/routes/dashboard/settings/pipelineStages/
└── EditPipelineStage.vue               # add "stale after N days" numeric input

app/javascript/dashboard/components-next/Opportunities/
└── KanbanCard.vue                      # add dwell-time badge, alert styling

app/javascript/dashboard/i18n/locale/en/
└── (pipeline stage / opportunities locale files)  # new i18n keys

spec/models/  (custom/spec mirrors app/spec convention used elsewhere, e.g. custom/spec/models)
└── opportunity_stage_change_spec.rb, opportunity_spec.rb (callback coverage) — only if explicitly requested
```

**Structure Decision**: Follows the existing fork convention: backend
additions live entirely under `custom/app/**` and `db/migrate/` (additive
only), keyed to `matias_`-prefixed tables; frontend additions are made
in-place to the two existing Vue files that already own kanban card rendering
and pipeline stage editing (`KanbanCard.vue`, `EditPipelineStage.vue`), since
this feature extends existing UI surfaces rather than introducing a new page
or route. No `contracts/` artifacts are produced — no new API endpoints are
introduced; the existing `PATCH /pipeline_stages/:id` endpoint's permitted
params list simply grows by one field.

## Complexity Tracking

*No constitution violations — section not applicable.*
