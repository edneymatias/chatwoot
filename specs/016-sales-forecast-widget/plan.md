# Implementation Plan: Sales Forecast Widget (Preview)

**Branch**: `016-sales-forecast-widget` | **Date**: 2026-08-04 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/016-sales-forecast-widget/spec.md`

## Summary

Add an 8th card to the existing Opportunity Funnel Report page (Phase 21): a
probability-weighted forecast of currently-open pipeline value expected to
close within 90 days, broken into 0–30/31–60/61–90 day buckets. Entirely
additive to the existing `Reports::OpportunityFunnelBuilder` service (new
`sales_forecast` key in its response hash, reusing the same stage-duration
data already computed for `avg_time_in_stage`) and to
`OpportunityFunnelReport.vue` (new card laid out as three pieces — a
`ReportMetricCard`-style big number for the current open-pipeline baseline,
a `BarChart.vue` bar chart for the three time buckets, and a second
`ReportMetricCard`-style big number for the weighted grand total — plus
`EmptyState.vue` for the insufficient-data case). No new migration,
controller, route, or shared component; `ReportMetricCard.vue` and
`BarChart.vue` are both already used elsewhere on this same page.

## Technical Context

**Language/Version**: Ruby 3.x (Rails 7.1), Vue 3 (Composition API, `<script setup>`)

**Primary Dependencies**: Rails/ActiveRecord (existing `Opportunity`,
`PipelineStage`, `OpportunityStageChange` models — no schema change), Vuex,
`vue-chartjs`/chart.js (already a dependency), existing
`OpportunityFunnelReport.vue`/`BarChart.vue`/`ReportMetricCard.vue`/
`dashboard/components/widgets/EmptyState.vue` — no new npm/gem dependency

**Storage**: PostgreSQL — no schema change; the forecast is computed on
read from existing `matias_opportunities`/`matias_opportunity_stage_changes`/
`matias_pipeline_stages` tables (FR-003: never persisted, always fresh)

**Testing**: RSpec (`bundle exec rspec`) for the builder's new
`sales_forecast` computation (weighted value, bucketing, sufficiency gate);
no JS unit tests planned beyond existing lint checks, per CLAUDE.md (specs
not written unless explicitly asked)

**Target Platform**: Existing Chatwoot web dashboard (Rails API + Vue SPA)

**Project Type**: Web application (Rails backend + Vue frontend); backend
change lives in the already fork-owned `custom/app/services/reports/`
file; frontend change lives in the already fork-owned
`app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue`
file, both edited in place (Phase 21's files)

**Performance Goals**: N/A beyond existing report-page load expectations —
the forecast adds one extra pass over the same `OpportunityStageChange`
rows already scanned for `avg_time_in_stage`/`conversion_funnel`, plus one
query over currently-open opportunities; no new N+1, no pagination needed
(at most one row per pipeline stage, three fixed buckets)

**Constraints**: Must not touch upstream/core report files
(`app/builders/v2/reports/**`, `app/services/reports/data_source.rb`) or
any other core `Reports` module file; only extend the already fork-owned
`custom/app/services/reports/opportunity_funnel_builder.rb`; reuse
`ReportPolicy`/`DateRangeHelper`/`Concerns::KanbanFeatureGuard` unmodified
(same authorization/feature-gate as every other funnel-report field, no
new checks needed since this is the same endpoint)

**Scale/Scope**: Single account's opportunity volume; no pagination
(exactly 3 buckets, one aggregate total)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. The only backend edit is to
  `custom/app/services/reports/opportunity_funnel_builder.rb`, a file
  already fully fork-owned (created in Phase 21) — not a core file, not a
  new file, not new wiring. The only frontend edit is to
  `OpportunityFunnelReport.vue` and `en.json`, both already fork-created
  Phase 21 files. No core Chatwoot file (upstream `app/`, `config/routes.rb`,
  any core `Reports` file) is touched at all — a strict subset of Phase 21's
  already-approved touch surface.
- **II. Smallest Production-Ready Change**: PASS. No new service, no new
  Vue component, no new chart wrapper, no new shared `Badge`/icon
  component, no migration, no new route. One new private computation block
  in an existing service; one new card block (two `ReportMetricCard`
  big-numbers + one `BarChart.vue` + `EmptyState.vue`) in an existing page,
  reusing three components already used elsewhere on the same page. See
  `research.md` Decisions 6–9 for the specific "reuse existing pattern, add
  nothing new" calls made to keep this minimal.
- **III. Adhere to Established Conventions**: PASS. `<script setup>`
  Composition API (matching the rest of `OpportunityFunnelReport.vue`);
  new i18n keys added to `en.json` only (no bare template strings, no
  non-English locale hand-edits — unlike Phase 21's named pt-BR exception,
  none is requested or needed here); Tailwind-only styling for the new
  card markup and preview badge; RuboCop-compliant Ruby in the builder
  addition.
- **IV. Safe, Reversible Change Management**: PASS. Purely additive code
  changes (new hash key, new Vue template block); no migration, no data
  backfill, no destructive operation of any kind. Fully revertible by
  reverting the two edited files.
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS. No new endpoint, no
  new controller, no new policy — the existing `ReportPolicy` (already
  `prepend_mod_with`-wired for Enterprise per Phase 21) continues to gate
  the entire response, `sales_forecast` included, with zero additional
  Enterprise-specific work needed. No OSS/Enterprise core surface is
  touched.

No violations — Complexity Tracking section not needed.

## Project Structure

### Documentation (this feature)

```text
specs/016-sales-forecast-widget/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md         # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── opportunity_funnel_report.md   # Phase 1 output — contract addition (sales_forecast key)
├── checklists/
│   └── requirements.md
└── tasks.md              # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
custom/app/services/reports/
└── opportunity_funnel_builder.rb        # edit: add sales_forecast key + private helpers
                                          #   (stage_win_probabilities, forecast_sufficient?,
                                          #    expected_close_offset_days, sales_forecast)

app/javascript/dashboard/routes/dashboard/settings/reports/
└── OpportunityFunnelReport.vue          # edit: add 8th card (ReportMetricCard x2
                                          #   + BarChart.vue bucket bars + EmptyState.vue)

app/javascript/dashboard/i18n/locale/en/
└── report.json (en.json)                # edit: new OPPORTUNITY_FUNNEL_REPORTS.SALES_FORECAST
                                          #   and .CHARTS.SALES_FORECAST keys

spec/  (only if explicitly requested — see CLAUDE.md)
└── custom/spec/services/reports/opportunity_funnel_builder_spec.rb
    # extend existing spec (if present) or add sales_forecast-focused examples
```

No new files. Every change lands in a file that already exists and is
already fully fork-owned (`custom/app/services/reports/`) or already
fork-created in `app/javascript/dashboard/` (Phase 21). No route, no
controller, no migration, no shared/new component.

**Structure Decision**: This feature makes no structural changes — it
extends exactly two existing files (the Phase 21 builder service and the
Phase 21 report page component) plus the existing `en.json` locale file,
matching Phase 21's established `custom/`-isolation convention with zero
new wiring. `contracts/opportunity_funnel_report.md` documents only the
addition to the existing endpoint's response shape (no new endpoint).

## Complexity Tracking

*No constitution violations — section not applicable.*
