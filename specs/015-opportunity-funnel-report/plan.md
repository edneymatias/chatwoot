# Implementation Plan: Opportunity Funnel Report

**Branch**: `015-opportunity-funnel-report` | **Date**: 2026-08-04 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/015-opportunity-funnel-report/spec.md`

## Summary

Add a fixed, 7-chart Opportunity Funnel report page to the existing Reports
module: `Opportunity` gains a nullable `closed_at` timestamp (set/cleared via
a `before_save` callback on open↔won/lost transitions); a new
`Api::V1::Accounts::OpportunityFunnelReportsController#index` endpoint
delegates to a single new `Reports::OpportunityFunnelBuilder` service that
assembles all 7 metrics (conversion funnel, win rate, pipeline value by
stage, average time in stage, new-opportunities trend, sales cycle time,
performance by assignee) from existing `Opportunity`/`OpportunityStageChange`/
`PipelineStage` data — no metric computation on the frontend. Two small new
chart wrapper components (`DonutChart.vue`, `LineChart.vue`) join the
existing `BarChart.vue`; a new report page reuses `ReportHeader`,
`ReportFilters`, and `ReportMetricCard` exactly as every sibling report page
already does.

## Technical Context

**Language/Version**: Ruby 3.x (Rails 7.1), Vue 3 (Composition API, `<script setup>`)

**Primary Dependencies**: Rails/ActiveRecord, Pundit (`ReportPolicy`,
unmodified), Vuex, `vue-chartjs`/chart.js (already a dependency, no new npm
package), existing `ReportHeader.vue`/`ReportFilters.vue`/`ReportMetricCard.vue`/
`BarChart.vue`

**Storage**: PostgreSQL — one additive column, `matias_opportunities.closed_at`
(nullable datetime); no new tables (reads existing `matias_opportunity_stage_changes`
from Phase 11)

**Testing**: RSpec (`bundle exec rspec`) for the model callback and the
builder service's 7 metric calculations; no JS unit tests planned beyond
existing lint/type checks (per CLAUDE.md, specs are not written unless
explicitly asked)

**Target Platform**: Existing Chatwoot web dashboard (Rails API + Vue SPA)

**Project Type**: Web application (Rails backend + Vue frontend); backend
additions live in the fork-owned `custom/` tree, frontend additions live
directly in `app/javascript/dashboard/` following every prior report page's
placement (see `research.md`)

**Performance Goals**: N/A beyond existing report-page load expectations —
one request, 7 independently-scoped SQL aggregate queries per request, no
N+1 (each metric is a single grouped query), matching the shape of existing
`V2::Reports` builders

**Constraints**: Must not touch upstream/core report files (`app/builders/v2/reports/**`,
`app/services/reports/data_source.rb`, etc.) or the `Reports` core module's
existing files — only add new files; reuse `ReportPolicy`/`DateRangeHelper`
unmodified; `closed_at` migration is additive-only on an already fork-owned
table

**Scale/Scope**: Single account's opportunity volume; no pagination needed
(each metric is a small, pre-aggregated set — at most one row per pipeline
stage or per assignee)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. `closed_at` is an additive
  column on the already fork-owned `matias_opportunities` table, set via a
  callback on the already fork-owned `Opportunity` model — direct ownership,
  not a core-file edit. The new controller lives in
  `custom/app/controllers/api/v1/accounts/`, matching every sibling kanban
  controller. The new `Reports::OpportunityFunnelBuilder` service is
  physically isolated under `custom/app/services/reports/`, resolved by the
  existing `custom/app/**` eager-load glob with zero new wiring — it reopens
  the core `Reports` module nominally but edits no core file. `config/routes.rb`
  gets one new `resources :opportunity_funnel_reports, only: [:index]` line
  in the existing account-scoped kanban routes block, mirroring how every
  prior kanban route was added. `ReportPolicy` and `DateRangeHelper` (both
  core) are consumed unmodified, not edited or forked.
- **II. Smallest Production-Ready Change**: PASS. One service, one
  controller action, one migration, two trivial chart wrapper components
  (mirroring `BarChart.vue`'s exact structure, per FR-008) — no generic
  chart-builder, no per-chart config, no CSV/export/drilldown (explicitly
  out of scope per spec). No new Enterprise-specific behavior is introduced.
- **III. Adhere to Established Conventions**: PASS. `<script setup>`
  Composition API for the new page and chart wrappers; i18n keys added to
  `en.yml`/`en.json` only; Tailwind-only styling (reusing existing report
  components' classes); strong params pattern not needed (GET-only,
  read-only endpoint, no persisted params).
- **IV. Safe, Reversible Change Management**: PASS. Standard additive Rails
  migration (new nullable column), no destructive operations, no data
  backfill required (existing opportunities simply have `closed_at: nil`
  until their next `won`/`lost` transition).
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS. `ReportPolicy` is
  already `prepend_mod_with`-wired for Enterprise; this feature calls it
  unmodified, so any Enterprise-specific report-access override (if one
  exists) automatically applies to this new endpoint with no extra work.
  No other OSS/Enterprise core surface is touched — the entire feature is
  either fork-owned (`custom/`, `matias_opportunities`) or new files in the
  existing dashboard frontend tree.

No violations — Complexity Tracking section not needed.

## Project Structure

### Documentation (this feature)

```text
specs/015-opportunity-funnel-report/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── opportunity_funnel_report.md   # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
db/migrate/
└── <timestamp>_add_closed_at_to_matias_opportunities.rb

custom/app/models/
└── opportunity.rb                                  # add closed_at before_save callback

custom/app/services/reports/
└── opportunity_funnel_builder.rb                   # new: Reports::OpportunityFunnelBuilder

custom/app/controllers/api/v1/accounts/
└── opportunity_funnel_reports_controller.rb         # new

config/routes.rb                                     # +1 line: opportunity_funnel_reports route

app/javascript/shared/components/charts/
├── BarChart.vue                                     # existing, reused as-is
├── DonutChart.vue                                   # new (win rate)
└── LineChart.vue                                    # new (new-opportunities trend)

app/javascript/dashboard/api/
└── opportunityFunnelReports.js                      # new ApiClient subclass

app/javascript/dashboard/store/modules/
└── OpportunityFunnelReports.js                      # new Vuex module (get action, data/uiFlags getters)

app/javascript/dashboard/routes/dashboard/settings/reports/
├── OpportunityFunnelReport.vue                       # new page
└── reports.routes.js                                 # +1 route entry ('funnel')

app/javascript/dashboard/components-next/sidebar/
└── Sidebar.vue                                       # +1 nav entry under Reports

app/javascript/dashboard/i18n/locale/en/
├── en.yml    (backend N/A — no new backend-rendered strings)
└── en.json                                           # new OPPORTUNITY_FUNNEL_REPORTS keys

spec/  (only if explicitly requested — see CLAUDE.md)
├── custom/spec/models/opportunity_spec.rb (closed_at callback coverage)
├── custom/spec/services/reports/opportunity_funnel_builder_spec.rb
└── custom/spec/requests/api/v1/accounts/opportunity_funnel_reports_controller_spec.rb
```

**Structure Decision**: Backend additions follow the exact convention
established in Phases 1–14: new fork-specific logic lives in `custom/app/**`
(models edited in place since they're already fork-owned; new controller and
service files added net-new), the one shared-infrastructure exception is the
additive `db/migrate/` file, and `config/routes.rb` gets the smallest
possible single-line addition. `Reports::OpportunityFunnelBuilder` reopens
the core `Reports` Ruby namespace but is physically isolated in `custom/`,
resolved by the existing autoload glob with no new wiring. Frontend
additions are all new files placed directly alongside their nearest
sibling in the existing `dashboard` tree (no isolated frontend directory
exists in this fork, and prior phases already established this placement
for kanban-specific frontend code — see `research.md`). No `contracts/`
artifact is needed beyond the one new endpoint's shape, documented in
`contracts/opportunity_funnel_report.md`.

## Complexity Tracking

*No constitution violations — section not applicable.*

## Post-Plan Additions (Convergence Phase 9)

Approved after initial implementation, layered onto the file set above without changing it:

- `OpportunityFunnelReport.vue` gained a `showValue` toggle (`SHOW_VALUE_TOGGLE` i18n key) and
  per-chart headline computeds; `opportunity_funnel_builder.rb`'s `pipeline_value_by_stage` and
  `new_opportunities_over_time` gained `value_data` alongside `count_data` to back the toggle.
  See spec.md's "Post-launch scope additions" note.
- Chart panels (`h-72` sizing, hidden y-axis ticks, %/currency-aware tooltip callbacks, compact
  currency formatting) are cosmetic UI polish on the existing `BarChart.vue`/`DonutChart.vue`/
  `LineChart.vue` wrappers listed above — no new components, no wrapper API change.
