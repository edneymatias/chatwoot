# Implementation Plan: Funnel Search Filters and Live Totals

**Branch**: `042-funnel-search-filters-and-live-totals` | **Date**: 2026-09-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/042-funnel-search-filters-and-live-totals/spec.md`

## Summary

Three fixes to the Kanban funnel's top bar, all inside the existing search/filter/aggregate
mechanisms (no new subsystem):

1. Extend `OpportunitiesFilter#apply_search` to also match campaign attribution columns
   (`campaign_name`, `campaign_adset_name`, `campaign_ad_name`, `campaign_platform`), backed by a
   new GIN trigram index mirroring the one already on `contacts`.
2. Add a `contains`/`does_not_contain` operator to `apply_standard_column_filter` and expose
   campaign text fields, platform (dropdown), and `created_at`/`updated_at` as new filterable
   attributes in the existing advanced-filter builder shared with Conversations/Contacts.
3. Fix `PipelineStageAggregatesController` to run the same `OpportunitiesFilter` the card list
   already uses (instead of a hardcoded `status: :open` query) and wire the frontend to re-fetch
   aggregates whenever search/filter/status changes — closing the current gap where totals are
   fetched once on mount and never again.

## Technical Context

**Language/Version**: Ruby 3.x (Rails 7.1) backend; Vue 3 (Composition API, `<script setup>`) frontend — matches the rest of this fork, no new language/runtime.

**Primary Dependencies**: `pg_trgm` (already enabled, used by the existing `contacts` GIN index); Vuex (`pipelineStages` store module); the shared advanced-filter component tree in `app/javascript/dashboard/components-next/filter/`. No new dependency is introduced.

**Storage**: PostgreSQL. One additive migration (new GIN trigram index on `ichatr_opportunities`); no new tables, no column changes.

**Testing**: RSpec (`bundle exec rspec`) for `OpportunitiesFilter` and `PipelineStageAggregatesController`; Jest (`pnpm test`) for the frontend store/action/mutation changes. Both suites currently have **no existing spec file** for either backend target — new spec files are created, not extended.

**Target Platform**: Existing Chatwoot dashboard (web), Kanban/Opportunities feature (`feature_enabled?('opportunities')`, gated by `Concerns::KanbanFeatureGuard`).

**Project Type**: Web application (Rails API + Vue SPA dashboard) — existing monolith, no new project/service.

**Performance Goals**: Search, filter application, and totals refresh each complete in under 1 second at production data volumes ([spec.md](./spec.md) FR-002/SC-003, resolved during `/speckit-clarify`).

**Constraints**: No debouncing introduced anywhere in this flow (matches existing behavior — see spec Assumptions). `campaign_platform` is excluded from the trigram index (low-cardinality, two known values, matched via equality filter instead). Response contract for `PipelineStageAggregatesController` changes its JSON keys (`open_count`/`open_value_sum` → `count`/`value_sum`) — every consumer of that response is updated in the same change (no dual-read transition period, since it's a single fork-internal endpoint with one consumer).

**Scale/Scope**: Single-tenant-scoped queries (`account_id` already indexed); typical account opportunity volumes as seen elsewhere in this fork's Kanban module — no new scale assumption beyond what today's title/contact-name search already handles.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. All touched files are fork-owned (`custom/app/controllers/...`, `app/finders/opportunities_filter.rb` — a fork-added finder, not an upstream file) or fork-added frontend modules (`components-next/filter/`, `components-next/Opportunities/`, `store/modules/pipelineStages/`). The new migration is additive-only (new index, no altered/dropped columns) and lives in the required shared `db/migrate/` location. No upstream file is renamed/restructured.
- **II. Smallest Production-Ready Change**: PASS. Each of the three fixes reuses an existing mechanism (ILIKE search, standard-column filter dispatch, `OpportunitiesFilter`) rather than introducing a parallel one. No speculative guards added (e.g., the platform dropdown stays a fixed 2-option list per YAGNI, documented in spec Assumptions/Out-of-scope).
- **III. Adhere to Established Conventions**: PASS. RuboCop 150-char/complexity limits respected by keeping `PipelineStageAggregatesController#index` split into small private methods (mirrors today's structure); ESLint/Composition API conventions followed for Vue changes; i18n keys added to both `en`/`pt_BR` synchronously per this fork's no-Crowdin convention.
- **IV. Safe, Reversible Change Management**: PASS. Only reversible, additive changes (new index via `add_index`, new i18n keys, new filter types, extended response payload). No destructive migration, no forced push, no disabled checks.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS (N/A). `Opportunity`/`PipelineStage`/Kanban are fork-only (`custom/` + a few `app/finders`, `app/models` additions), not part of upstream OSS or Enterprise surfaces — there is no `enterprise/` overlay to check for these files (verified: no `enterprise/` files reference `Opportunity`, `PipelineStage`, or `OpportunitiesFilter`).

No violations to record in Complexity Tracking.

**Post-Phase 1 re-check**: `data-model.md` and `contracts/` introduce no new tables, no new
extension-point gaps, and no upstream file touches beyond what was already listed above — all
five principles still PASS with the design artifacts in hand.

## Project Structure

### Documentation (this feature)

```text
specs/042-funnel-search-filters-and-live-totals/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   └── pipeline_stage_aggregates.md
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

This is an existing Rails + Vue monolith (not a greenfield project), so "structure" here means the
specific existing files this feature touches — no new top-level directories are introduced.

```text
db/migrate/
└── <timestamp>_add_trigram_search_index_to_ichatr_opportunities.rb   # NEW

app/finders/
└── opportunities_filter.rb                # MODIFIED: apply_search, apply_standard_column_filter

custom/app/controllers/api/v1/accounts/
└── pipeline_stage_aggregates_controller.rb # MODIFIED: filter-aware, status-aware aggregation

app/javascript/dashboard/
├── components-next/filter/
│   └── opportunityProvider.js              # MODIFIED: new filterTypes entries
├── api/
│   └── pipelineStageAggregates.js          # MODIFIED: get(stageIds, filters)
├── store/modules/pipelineStages/
│   ├── actions.js                          # MODIFIED: fetchAggregates({ stageIds, filters })
│   └── mutations.js                        # MODIFIED: SET_STAGE_AGGREGATES field rename
├── components-next/Opportunities/
│   └── KanbanColumn.vue                    # MODIFIED: read stage.count / stage.value_sum
├── routes/dashboard/opportunities/
│   ├── Index.vue                           # MODIFIED: watch(filters) → re-dispatch fetchAggregates
│   └── components/
│       └── OpportunitiesViewBar.vue        # MODIFIED: read stage.count / stage.value_sum
└── i18n/locale/
    ├── en/advancedFilters.json             # MODIFIED: new FILTER.ATTRIBUTES.* keys
    └── pt_BR/advancedFilters.json          # MODIFIED: new FILTER.ATTRIBUTES.* keys

spec/finders/
└── opportunities_filter_spec.rb            # NEW

spec/requests/api/v1/accounts/
└── pipeline_stage_aggregates_controller_spec.rb  # NEW
```

**Structure Decision**: No new project/module structure. This is a set of additive/modifying edits
across the fork's existing Kanban/Opportunities vertical slice (`custom/app/controllers`,
`app/finders/opportunities_filter.rb`, and the shared `components-next/filter/` + `pipelineStages`
store module under `app/javascript/dashboard/`), matching how every prior Kanban phase (001–041)
in `specs/` has been structured. Backend request specs for `custom/app/controllers/...` live under
core `spec/requests/api/v1/accounts/` (not `custom/spec/`), mirroring the existing sibling spec
`spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb` — confirmed against the current
repo layout during Phase 0 research, not assumed from the source design doc.

## Complexity Tracking

*No Constitution Check violations — this section is intentionally empty.*
