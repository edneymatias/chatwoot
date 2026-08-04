# Phase 21: Opportunity Funnel Report

**Depends on**: Phase 11 (stage dwell-time tracking — supplies the
`OpportunityStageChange` transition history this phase reports on)

## Context

Chatwoot's existing Reports module (CSAT, agents, labels, inbox, etc.) gets
a new page: a fixed dashboard of the 7 highest-value charts for a CRM
funnel. Unlike the rest of the Reports module, there is no chart builder or
`type=` selector — the set of charts is fixed, matching the product
decision that flexibility isn't the goal here; maximum value from a minimum
common denominator is.

**Two cohort semantics coexist**, matching how CRM tools (HubSpot,
Pipedrive) split "pipeline health" from "team output":
- **Created-in-period**: opportunities created within the selected date
  range. Drives the conversion funnel and the lead-volume trend.
- **Closed-in-period**: opportunities whose `closed_at` falls within the
  selected date range. Drives win rate, sales cycle time, and
  assignee performance — these describe what the team *closed* during the
  period, independent of when those deals were originally created.
- Two charts are **not period-filtered** (always reflect current state):
  pipeline value by stage, and average time-in-stage (a lifetime average
  across all historical transitions, not scoped to the selected range).

**Chart rendering**: reuses existing infra as much as possible.
`shared/components/charts/BarChart.vue` (chart.js + vue-chartjs, already a
dependency) already exists and is reused as-is for 5 of the 7 charts. Two
small new wrapper components are added, both trivial because chart.js
already ships the underlying chart types — only a thin Vue wrapper
(mirroring `BarChart.vue`'s existing structure) is missing:
- `DonutChart.vue` (registers `ArcElement`/`DoughnutController`) for win rate.
- `LineChart.vue` (registers `LineElement`/`PointElement`) for the
  lead-volume trend.

No new npm dependency is introduced. `ReportMetricCard.vue` (existing KPI
tile component, already used by CSAT/SLA reports) is reused for the two
single-number metrics (win rate %, average sales cycle days).

**Funnel chart visual (explicit scope decision)**: the conversion funnel
(#1 below) ships as a horizontal bar chart with decreasing bar lengths —
reusing `BarChart.vue`, not a bespoke trapezoid/funnel shape. A true
graphical funnel (stacked SVG trapezoids, styled per stage's
`accent_color`) is a documented **future, presentation-only upgrade**: it
would replace only this one chart's rendering, with no change to the data
model, API, or calculation logic. It's deferred until the report has
shipped and proven worth the added visual polish — see "Out of scope"
below.

## Data model

**FR-001**: `Opportunity` gains `closed_at` (datetime, nullable).

**FR-002**: A `before_save` callback sets `closed_at` to `Time.current`
when `status` transitions from `open` to `won` or `lost`, and clears it
back to `nil` if a closed opportunity is reopened (status changes back to
`open`) — so a previously-closed opportunity that reopens doesn't carry a
stale `closed_at` into future win-rate/cycle-time calculations.

## Backend API

**FR-003**: New `Api::V1::Accounts::OpportunityFunnelReportsController#index`
accepts `since`/`until` (unix timestamp, same convention as the existing
`Api::V2::Accounts::ReportsController`). No `type`/`group_by` params —
the endpoint always returns the full fixed set.

**FR-004**: Response is a single JSON object with one key per chart, each
already shaped as chart-ready data (labels + dataset values), so the
frontend does no metric computation, only rendering:
`conversion_funnel`, `win_rate`, `pipeline_value_by_stage`,
`avg_time_in_stage`, `new_opportunities_over_time`, `sales_cycle_time`,
`performance_by_assignee`.

**FR-005**: A single service object (e.g. `Reports::OpportunityFunnelBuilder`)
assembles all 7 queries for the given account/date range — not a generic,
configurable builder like `Reports::DrilldownBuilder`, since the metric set
is fixed:

- **conversion_funnel**: opportunities created in period; for each stage
  (ordered by `PipelineStage#position`), count of distinct opportunities
  with at least one `OpportunityStageChange` row reaching that stage or
  later, shown as a percentage of the period's total created count.
- **win_rate**: opportunities closed in period, counts of `won` vs `lost`.
- **pipeline_value_by_stage**: not period-filtered. Sum of `value` for
  currently-`open` opportunities, grouped by current `pipeline_stage_id`.
- **avg_time_in_stage**: not period-filtered. From `OpportunityStageChange`,
  averaged duration (`next.changed_at - changed_at`) between consecutive
  transitions per opportunity, grouped by the stage occupied during that
  interval. Only **completed** stage durations are averaged — an
  opportunity's current (still-open) stage interval has no "next"
  transition yet and is excluded, so the average isn't skewed by
  still-in-progress dwell time.
- **new_opportunities_over_time**: opportunities created in period, bucketed
  by day (same bucketing convention as the existing time-series reports).
- **sales_cycle_time**: average of `closed_at - created_at`, for `won`
  opportunities closed in period.
- **performance_by_assignee**: `won` opportunities closed in period, grouped
  by `assignee_id`, with count and summed `value`, ranked descending.

**FR-006**: Empty states are non-error: an account with no opportunities in
the selected period returns empty/zero data per chart (same empty-state
convention as existing reports), not a 4xx/5xx. `pipeline_value_by_stage`
and `avg_time_in_stage` can independently have data even when the other 5
(period-filtered) charts are empty, since they aren't scoped to the
selected range.

## Frontend

**FR-007**: New page under the existing Reports module (e.g.
`Relatórios → Funil`), following the existing page structure/navigation
pattern (CSAT, agents, etc.), including the existing date-range filter
component already used by other report pages.

**FR-008**: Two new chart wrapper components, `DonutChart.vue` and
`LineChart.vue`, added alongside the existing `BarChart.vue` in
`shared/components/charts/`, following its exact prop/structure pattern
(`collection`, `chartOptions`, `clickable`/`elementClick`).

**FR-009**: The page renders all 7 charts: 5 via `BarChart.vue`
(conversion funnel, pipeline value by stage, avg time in stage, new
opportunities over time is actually `LineChart.vue` — see below,
performance by assignee), 1 via `DonutChart.vue` (win rate breakdown) + a
`ReportMetricCard.vue` for the win-rate percentage headline, 1 via
`LineChart.vue` (new opportunities over time), and 1 via
`ReportMetricCard.vue` alone (average sales cycle days, no chart —
it's a single number).

## Out of scope

- **Graphical (trapezoid) funnel chart**: deferred. When/if pursued, it's a
  presentation-only swap of chart #1's rendering (custom Tailwind/SVG
  component using each stage's `accent_color`), with zero change to
  `conversion_funnel`'s data shape or calculation. Not scheduled to a
  phase yet — revisit once this report has shipped and real usage
  justifies the investment.
- Multi-pipeline selector/filter (depends on the still-placeholder
  multi-pipeline phase).
- Per-chart drilldown or CSV/export.
- Any alerting, digest, or notification derived from these metrics (this
  is a report page only).
