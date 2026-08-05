# Phase 1 Data Model: Graphical Funnel Chart

This feature introduces no database tables or new backend models. It adds one field to an
existing service's return hash (`Reports::OpportunityFunnelBuilder#conversion_funnel`) and one
frontend view-model shape derived from it.

## FunnelPoint (frontend view model)

One per pipeline stage band, derived in `OpportunityFunnelReport.vue` from the
`conversion_funnel` API payload (see `contracts/conversion-funnel-data-contract.md`) and passed
into `FunnelChart.vue`.

| Field        | Type             | Source                                              | Notes |
|--------------|------------------|------------------------------------------------------|-------|
| `label`      | `string`         | `conversion_funnel.labels[i]`                        | Pipeline stage name. |
| `percentage` | `number` (0–100) | `conversion_funnel.count_data[i]`                     | Percentage of the period's total created count reaching this stage; drives band width. |
| `count`      | `number`         | `conversion_funnel.counts[i]` (new backend field, FR-008) | Raw opportunity count for this stage, always present once the backend change ships (see research.md Decision 2 — it's a synchronous, in-memory computation with no failure mode that would leave it absent). |
| `color`      | `string` (hex)   | `pipeline_stages.accent_color` via `stageColorByName` (existing lookup already in `OpportunityFunnelReport.vue`) | Falls back to the page's existing `DEFAULT_BAR_COLOR` when a stage has no `accent_color` (per `/speckit-clarify` decision), same as the current bar chart. |

**Validation rules**:
- `percentage` MUST be clamped to `[0, 100]` by the component (defensive against a malformed
  backend value, since band width is derived directly from it and an out-of-range value would
  visually break the taper).
- Points render in the array order given — ordering by `PipelineStage#position` is the caller's
  responsibility (already established in `OpportunityFunnelReport.vue`'s existing data-fetch
  path), not re-derived inside `FunnelChart.vue`.
- A `points` array of length 1 or length 0 MUST both render without error (single band, or an
  empty-state container respectively) — see spec Edge Cases.

**State transitions**: None — `FunnelPoint` is a derived, read-only computed value; it has no
lifecycle of its own beyond the parent component's existing `reportData` computed refresh (already
wired for filter/date-range changes).

## Pipeline Stage (existing entity, referenced not modified)

Already defined by the `matias_pipeline_stages` table and the `pipelineStages/` Vuex module.
This feature only *reads* `name`, `position`, and `accent_color` — no schema or store changes.

## `Reports::OpportunityFunnelBuilder#conversion_funnel` (existing service method, modified)

`custom/app/services/reports/opportunity_funnel_builder.rb`. Already computes, per
`account.pipeline_stages.order(:position)`:

- `labels` (`Array<String>`) — unchanged.
- `count_data` (`Array<Float>`) — unchanged; percentage 0–100, `.round(1)`.
- `won_rate_pct` (`Float`) — unchanged.
- `counts` (`Array<Integer>`) — **new**, one raw opportunity count per stage, same order as
  `labels`. Derived from the `reached` hash (`{opportunity_id => max_position_reached}`) the
  method already builds via `max_stage_positions_reached`: `counts[i] = reached.count { |_id,
  max_pos| max_pos >= stages[i].position }` — exactly the numerator `funnel_pct` already computes
  before dividing by `total_count`.

No new query, no new state, no change to `labels`/`count_data`/`won_rate_pct`'s values.
