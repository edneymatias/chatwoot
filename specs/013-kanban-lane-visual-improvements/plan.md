# Implementation Plan: Kanban Lane Visual Improvements

**Branch**: `013-kanban-lane-visual-improvements` | **Date**: 2026-08-03 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/013-kanban-lane-visual-improvements/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Replaces the kanban column header's misleading `cards.length` (loaded-only) badge with a true
lane-wide total of open opportunities — count or summed value, admin-configurable per lane,
defaulting to value — fed by a new backend aggregate endpoint decoupled from card pagination.
Adds an optional per-lane color accent, rendered only as the column header's bottom border, with
no propagation to card rendering. Backend adds two columns to the existing `matias_pipeline_stages`
table and one new lightweight aggregate-only controller under `custom/`; frontend adds two fields
to `EditPipelineStage.vue`, a new Vuex action/mutation pair on the existing `pipelineStages`
module, and updates `KanbanColumn.vue`'s header rendering. Aggregate refresh is surgical — scoped
to only the affected `stage_id`(s) after a card move/create/status-change/value-edit — with no
loading indicator (per explicit clarification: this is small header info, not worth dedicated
visual feedback) and no dedicated error UI (falls back to the existing global API error
interceptor). Value formatting reuses Phase 14's already-shipped currency infrastructure
(`PipelineCurrencySetting`, `formatCurrencyAmount`) unconditionally.

## Technical Context

**Language/Version**: Ruby on Rails 7.1 (backend), Vue 3 + Vuex (frontend, Composition API with
`<script setup>`)

**Primary Dependencies**: Rails, Pundit (authorization), ActiveRecord; Vue 3, Vuex,
`dashboard/components-next/colorpicker/ColorPicker.vue` (existing free-hex picker, already used by
Phase 14's `CardFieldConfig.vue`), existing `formatCurrencyAmount` from
`dashboard/constants/pipelineCurrency`

**Storage**: PostgreSQL — two new columns on the existing `matias_pipeline_stages` table
(`total_display_mode`, `accent_color`); no new tables

**Testing**: RSpec (backend model/request specs, only if requested — repo convention is to avoid
writing specs unless explicitly asked); `pnpm eslint` and `bundle exec rubocop` as mandatory
lint/quality gates regardless

**Target Platform**: Web (existing Chatwoot dashboard, server-rendered Rails API + Vue SPA)

**Project Type**: Web application (Rails API backend + Vue frontend monolith)

**Performance Goals**: The new aggregate endpoint must be a single indexed `COUNT`/`SUM` grouped
query, independent of how many cards are loaded/paginated in a lane — cost does not scale with
board size

**Constraints**: Aggregate excludes won/lost opportunities (open-status only); count and value are
never shown together (exactly one, per `total_display_mode`); lane color is header-bottom-border
only, must not alter `KanbanCard.vue` rendering or interact with its existing
`cardClass`/`hasUnmetRequirements` logic; no loading indicator on the header total; no dedicated
error UI for a failed aggregate refresh

**Scale/Scope**: Two new columns on an existing table, one new read-only aggregate controller/
route, one new Vuex action/mutation, two new fields in the existing stage-edit form, one updated
component (`KanbanColumn.vue`) — no new tables, no new settings page

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Assessment |
|---|---|
| I. Upstream Compatibility First | **PASS** — new aggregate controller lives under `custom/app/controllers/api/v1/accounts/...`; the two new `PipelineStage` columns are added via migration to the already-`matias_`-prefixed table; no core model files are edited (the model itself, `custom/app/models/pipeline_stage.rb`, already lives under `custom/`). |
| II. Smallest Production-Ready Change | **PASS** — no new tables (existing `matias_pipeline_stages` gains two columns); no new curated color palette (reuses the existing free-hex `ColorPicker.vue`/Labels convention); no speculative cross-tab real-time sync; aggregate scoped to exactly the affected `stage_id`(s), not a full board refresh. |
| III. Adhere to Established Conventions | **PASS** — Tailwind-only styling (`accent_color` is an inline `border-bottom-color`, the pre-existing Labels/Phase 14 hex-color exception, not a new one); Composition API `<script setup>`; PascalCase components; i18n for new labels; Pundit authorization via `Concerns::KanbanFeatureGuard`/`check_authorization`, mirroring `PipelineStagesController`. |
| IV. Safe, Reversible Change Management | **PASS** — purely additive migration (`add_column`), no destructive operations, no data backfill needed (new columns default to `value_sum`/`nil`). |
| V. Dual-Tree Awareness (OSS + Enterprise) | **PASS** — confirmed no `enterprise/` code references `PipelineStage`/`Opportunity`/pipeline concepts (same finding as Phase 14); no Enterprise override or extension point needed. |

No violations. Complexity Tracking table is not needed.

## Project Structure

### Documentation (this feature)

```text
specs/013-kanban-lane-visual-improvements/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md         # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── pipeline-stage-aggregates-api.md
└── tasks.md              # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
db/migrate/
└── <timestamp>_add_total_display_mode_and_accent_color_to_matias_pipeline_stages.rb

custom/app/models/
└── pipeline_stage.rb                          # add total_display_mode enum, accent_color attr

custom/app/controllers/api/v1/accounts/
└── pipeline_stage_aggregates_controller.rb     # NEW — index-only, scoped to stage_ids[]

config/routes.rb                                # add: resources :pipeline_stage_aggregates,
                                                 #   only: [:index]

app/javascript/dashboard/
├── api/
│   └── pipelineStageAggregates.js              # NEW — index(stageIds)
├── store/modules/pipelineStages/
│   ├── actions.js                              # add fetchAggregates({ stageIds })
│   └── mutations.js                            # add SET_STAGE_AGGREGATES
├── components-next/Opportunities/
│   ├── KanbanBoard.vue                         # dispatch pipelineStages/fetchAggregates after
│   │                                            # move/status-change/create/value-edit success
│   └── KanbanColumn.vue                        # replace cards.length badge with
│                                                # open_count/open_value_sum; apply accent_color
│                                                # as border-bottom-color
└── routes/dashboard/settings/pipelineStages/
    └── EditPipelineStage.vue                   # add total_display_mode select + accent_color
                                                 # ColorPicker.vue field

app/javascript/dashboard/i18n/locale/en/
└── (relevant locale file, e.g. opportunities.json or a pipeline-stages-mgmt locale) — new strings
```

**Structure Decision**: Web application monolith (existing Rails + Vue structure). The new
aggregate controller lives under `custom/app/...` per Constitution Principle I; core Rails files
(`config/routes.rb`) receive only the minimal one-line route addition already established for
sibling features (`pipeline_card_field_configs`, `pipeline_currency_setting`). Frontend additions
extend the existing `pipelineStages` Vuex module and `EditPipelineStage.vue`/`KanbanColumn.vue`
components rather than introducing new ones, since this feature is additive to an existing model
rather than a new domain concept.

## Complexity Tracking

> Not applicable — no Constitution Check violations.
