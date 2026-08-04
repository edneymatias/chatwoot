# Phase 23: Sales Forecast Widget (preview)

**Depends on**: Phase 21 (Opportunity Funnel Report — reuses the
`avg_time_in_stage` calculation and adds an 8th card to that report page)

## Context

The funnel report page (Phase 21) ships 7 fixed charts. This phase adds
an 8th, explicitly a **preview / first version**: a probability-weighted
forecast of currently-`open` pipeline value, expected to close within the
next 90 days. It ships as a single card: one donut/circle showing total
weighted forecast value, plus a breakdown into three time buckets —
**0–30, 31–60, 61–90 days** — each showing count and weighted value.

This is deliberately a first iteration: the goal is directional signal
("how much is likely to close soon"), not a precise revenue commitment.
Two decisions worth calling out because they're not obvious from the data
model alone:
- The circle's total is the sum of **all three buckets** (i.e. all
  currently-open pipeline expected to close within 90 days) — not scoped
  down to just the 0–30 bucket. The buckets underneath give the
  time-distribution breakdown of that same total.
- An opportunity whose `expected_close_date` (FR-002) has already passed
  (overdue) is **not** excluded or shown as a separate "overdue" bucket —
  it's folded into the 0–30 day bucket, since it's already due and the
  most actionable next-30-days signal.

## Backend API

**FR-001**: `Api::V1::Accounts::OpportunityFunnelReportsController#index`
(from Phase 21) gains a `sales_forecast` key in its response, computed by
the same `Reports::OpportunityFunnelBuilder` service. Not period-filtered
— always reflects current open pipeline, like `pipeline_value_by_stage`
and `avg_time_in_stage`.

For each currently-`open` opportunity: `weighted_value = value *
stage_win_probability`, where `stage_win_probability` is the historical
win rate of opportunities that have passed through the opportunity's
current stage (closed `won` ÷ closed `won` + closed `lost`, among
opportunities that reached that stage — lifetime, not period-scoped). The
opportunity is then bucketed by its `expected_close_date` (FR-002) into
`0-30`, `31-60`, or `61-90` days from today; opportunities with an
`expected_close_date` more than 90 days out are excluded from the
forecast entirely. Response shape: total weighted value, and per bucket
`{ count, weighted_value }`.

**FR-002**: `expected_close_date` for an open opportunity is computed as
`today + sum(avg_time_in_stage for the opportunity's current stage and
every stage after it, per pipeline order)`, reusing the same
completed-duration averages as Phase 21's `avg_time_in_stage`. It's
computed on read, not persisted — cheap to derive from data already
queried for the other charts, and it should always reflect the latest
historical averages rather than going stale.

**FR-003**: The forecast has a **data-sufficiency gate**, distinct from
Phase 21's empty-state convention (an account with zero opportunities):
it only activates once the account has, for every stage in the pipeline,
at least one *completed* transition (a value for `avg_time_in_stage`) and
at least one closed `won` and one closed `lost` opportunity overall (a
non-zero denominator for `stage_win_probability`). This is all-or-nothing
across the whole pipeline, not per-stage — if even one stage lacks
history, the forecast doesn't activate at all, rather than showing a
partial number that would shift unpredictably as individual stages
accumulate data. Fresh/new accounts — no closed deals yet, no completed
stage transitions — won't meet the gate, so rather than substituting a
fabricated default (e.g. assuming 50% probability or an arbitrary average
stage duration) or returning an ambiguous `null`, the API returns
`sales_forecast: { status: "insufficient_data" }` (omitting the
total/bucket fields), and the frontend renders an explicit, declared empty
state (FR-005) instead of a chart. This avoids showing numbers the team
could mistake for a real commitment before the account has the history to
back them.

## Frontend

**FR-004**: An 8th card on the funnel report page (Phase 21), positioned
last, titled and carrying a visible "preview" badge (this is explicitly a
first version, not part of the original 7-chart set). Reuses
`DonutChart.vue` (from Phase 21), segmented into **3 slices — one per
bucket** (`0-30`/`31-60`/`61-90`), each slice sized proportionally to that
bucket's `weighted_value`. The **grand total** (sum of all 3 buckets) is
displayed as a text label in the donut's center hole. Below the donut, a
3-row list — one per bucket — each row pairing a color swatch matching its
donut slice with the bucket label, opportunity count, and weighted value
(e.g. "0–30 dias · 4 oportunidades · R$ 12.400"). No new chart wrapper
component needed.

**FR-005**: When the API returns `sales_forecast.status ==
"insufficient_data"` (FR-003), the card keeps its title/frame but replaces
the donut and list with an inline empty state (icon + a declared message,
e.g. "Ainda não há dados históricos suficientes para calcular a previsão
de vendas" — translated string) instead of a zeroed-out donut or `0`
total, so it's not mistaken for "no pipeline value" when the real reason
is insufficient history.

## Out of scope

- Any change to `avg_time_in_stage`'s calculation (owned by Phase 21).
- Editable/configurable bucket widths (0–30/31–60/61–90 is fixed for this
  first version).
- Per-opportunity forecast drilldown or export.
