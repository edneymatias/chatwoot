# Data Model: Sales Forecast Widget (Preview)

No schema changes. This feature adds no migration, no new table, no new
column — every value is computed on read, via `Reports::SalesForecastCalculator`
(invoked from `Reports::OpportunityFunnelBuilder#sales_forecast`), from existing data.

## Existing entities read (no changes)

### Opportunity (`matias_opportunities`, `custom/app/models/opportunity.rb`)

Fields used: `value`, `status` (`open`/`won`/`lost`), `pipeline_stage_id`,
`account_id`. Only `status: open` opportunities feed the forecast; `won`/
`lost` opportunities feed the win-probability denominator/numerator only.

### PipelineStage (`matias_pipeline_stages`, `custom/app/models/pipeline_stage.rb`)

Fields used: `position` (ordering, for "every stage after it"), `name`
(bucket/label context only, not surfaced by the forecast itself), `id`.

### OpportunityStageChange (`custom/app/models/opportunity_stage_change.rb`)

Fields used: `opportunity_id`, `to_stage_id`, `changed_at`. Source of both
the lifetime stage-reach set (win-probability numerator/denominator
population) and the completed-interval durations (expected-close-date
offsets) — identical source data already used by `avg_time_in_stage` and
`conversion_funnel`.

## Computed (non-persisted) shapes

### SalesForecast

Returned under the `sales_forecast` key of the funnel report response.

| Field | Type | Present when |
|---|---|---|
| `status` | `"ok"` \| `"insufficient_data"` | always |
| `total_weighted_value` | Float | `status == "ok"` only |
| `buckets` | `{ "day_0": ForecastBucket, "1_30": ForecastBucket, "31_60": ForecastBucket, "61_90": ForecastBucket }` | `status == "ok"` only |

There is no separate raw/unweighted "current pipeline" baseline figure —
the card's headline is the weighted `total_weighted_value` only (product
decision superseding the original FR-005a baseline).

`total_weighted_value` is the sum of all four buckets'
`weighted_value` (FR-005).

### ForecastBucket

| Field | Type | Notes |
|---|---|---|
| `count` | Integer | number of open opportunities whose computed `days_until_close` falls in this bucket |
| `weighted_value` | Float | sum of those opportunities' `value * stage_win_probability` |

## Computation pipeline (per `build` call, all in-memory after one query pass)

1. **Stage win probabilities** (`stage_id => Float`, 0.0–1.0): for every
   pipeline stage, among *all* (lifetime, whole-account) opportunities whose
   stage-change history shows they reached that stage or later, count
   currently `won` vs currently `lost`; probability = `won / (won + lost)`.
   A stage with zero won+lost reaching it has no probability entry (its
   absence is what the sufficiency gate below checks for).
2. **Stage average durations** (`stage_id => Float days`): reuses the
   existing `build_stage_durations` private method (already computed for
   `avg_time_in_stage`) — completed (non-current) interval durations per
   stage, averaged.
3. **Sufficiency gate**: `status = "ok"` only if every pipeline stage has a
   non-empty entry in (2) **and** the account has at least one `won` **and**
   one `lost` opportunity overall. Otherwise `status = "insufficient_data"`
   and no further computation runs.
4. For each currently-`open` opportunity:
   - `weighted_value = value.to_f * stage_win_probabilities[opportunity.pipeline_stage_id]`
   - `expected_close_date_offset_days = sum(avg_duration for the opportunity's current stage and every stage at or after its position, by pipeline order)`
   - `days_until_close = expected_close_date_offset_days` (today + offset,
     expressed directly as an offset-from-today integer for bucketing —
     no need to materialize an actual `Date`)
   - bucket: `<= 0` → `day_0`; `<= 30` → `1_30`; `<= 60` → `31_60`;
     `<= 90` → `61_90`; `> 90` → excluded from the forecast entirely (FR-004)
5. Sum `count`/`weighted_value` per bucket; `total_weighted_value` = sum of
   all four buckets' `weighted_value`.

## Validation rules

- No new validation — all inputs are already-validated `Opportunity`/
  `PipelineStage` records read-only.
- `stage_win_probabilities` values are always in `[0.0, 1.0]` since they're
  a ratio of non-negative counts.
- `weighted_value` and `total_weighted_value` are never negative (product
  of a non-negative `value` and a `[0.0, 1.0]` probability).

## State transitions

None — this is a pure read/aggregate computation with no persisted state
and no lifecycle of its own. Its output changes only as the underlying
`Opportunity`/`OpportunityStageChange` data changes (FR-003's "always
reflect the latest historical averages" requirement is satisfied by
computing fresh on every request, never caching/persisting).
