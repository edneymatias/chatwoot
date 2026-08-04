# Phase 22: Graphical Funnel Chart

**Depends on**: Phase 21 (Opportunity Funnel Report — ships the
`conversion_funnel` data via
`Api::V1::Accounts::OpportunityFunnelReportsController#index`)

## Context

Phase 21 ships the conversion funnel (chart #1 of the funnel report's 7
charts) as a horizontal bar chart, reusing the existing `BarChart.vue`
component — an explicit scope decision made there to avoid blocking the
report's launch on a bespoke visual. This phase replaces that rendering
with an actual trapezoid/funnel shape: decreasing-width bands, one per
pipeline stage, styled with each stage's `accent_color` (the same field
already used for kanban lane styling).

This is **presentation-only**: zero change to the `conversion_funnel`
data shape, its calculation, or the backend endpoint shipped in Phase 21.
Only the chart's rendering on the funnel report page is swapped.

## Frontend

**FR-001**: New `FunnelChart.vue` component under
`shared/components/charts/`, built as a custom Tailwind/SVG component (not
chart.js — chart.js has no native funnel/trapezoid chart type). It
replaces `BarChart.vue` for the conversion funnel section of the funnel
report page from Phase 21; no other chart on that page is affected.

**FR-002**: Renders one trapezoid band per pipeline stage, ordered by
`PipelineStage#position`, width proportional to that stage's value from
the existing `conversion_funnel` payload (percentage of the period's total
created count, same as Phase 21's bar chart used).

**FR-003**: Each band is colored using the stage's `accent_color` and
labeled with the stage name plus its percentage/count, mirroring the
labeling the bar-chart version already showed.

**FR-004**: Consumes the exact same `conversion_funnel` API response shape
from Phase 21 — no backend change, no new endpoint, no new query.

## Out of scope

- Any change to `conversion_funnel`'s calculation, data shape, or
  filtering (owned by Phase 21; unaffected by this phase).
- Animations/transitions beyond what's needed for a static funnel render.
- Applying the same trapezoid treatment to any other chart on the funnel
  report page.
