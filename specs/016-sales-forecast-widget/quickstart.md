# Quickstart: Sales Forecast Widget (Preview)

Validates the feature end-to-end against a running dev stack. See
[data-model.md](./data-model.md) for the computation pipeline and
[contracts/opportunity_funnel_report.md](./contracts/opportunity_funnel_report.md)
for the exact response shape.

## Prerequisites

- Stack running: `docker compose up -d`
- An account with the `opportunities` feature enabled and at least one
  pipeline stage (seed via `Seeders::AccountSeeder` or manually through the
  Kanban UI)
- Signed in as an account administrator (required by `ReportPolicy`)

## Scenario 1 — insufficient data (new/sparse account)

1. Use a freshly seeded account with open opportunities but **no** closed
   (`won`/`lost`) opportunities yet.
2. Navigate to Reports → Funnel report.
3. **Expected**: the 8th card ("Sales Forecast" / preview badge) shows the
   empty state (`EmptyState.vue` title + message) instead of a donut.
4. Confirm via API directly:
   ```bash
   curl -s -H "Cookie: <session>" \
     "http://localhost:3000/api/v1/accounts/<account_id>/opportunity_funnel_reports?since=0&until=0" \
     | jq '.sales_forecast'
   # => { "status": "insufficient_data" }
   ```

## Scenario 2 — sufficient data, forecast renders

1. On the same account, close at least one opportunity as `won` and one as
   `lost` in **every** pipeline stage (so every stage has at least one
   completed transition), and leave several opportunities `open` across
   different stages.
2. Reload the Funnel report page.
3. **Expected**:
   - Left big-number stat shows `current_pipeline.count`/`current_pipeline.value`
     (the full open pipeline, not limited to 90 days).
   - Middle bar chart shows three bars (0–30 / 31–60 / 61–90 days), heights
     scaled by each bucket's `weighted_value`.
   - Right big-number stat shows the sum of the three buckets' `count` and
     `total_weighted_value` as the headline total.
   - The three buckets' `weighted_value`s sum to `total_weighted_value`.
4. Confirm via API:
   ```bash
   curl -s -H "Cookie: <session>" \
     "http://localhost:3000/api/v1/accounts/<account_id>/opportunity_funnel_reports?since=0&until=0" \
     | jq '.sales_forecast'
   # => { "status": "ok", "current_pipeline": {...}, "total_weighted_value": ..., "buckets": { "0_30": {...}, "31_60": {...}, "61_90": {...} } }
   ```

## Scenario 3 — date-range independence

1. With Scenario 2's account, change the report's date-range filter (e.g.
   from "last 30 days" to "last quarter").
2. **Expected**: the forecast card's total and buckets do **not** change
   (unlike the 5 period-scoped charts) — `sales_forecast` ignores
   `since`/`until` entirely (FR-001).

## Scenario 4 — overdue and out-of-range opportunities

1. Manually inspect (via Rails console or by controlling seed data) an open
   opportunity whose computed expected close date has already passed.
   **Expected**: it appears in the `0_30` bucket's `count`, not excluded
   and not in a separate "overdue" bucket.
2. Inspect an open opportunity in a very early stage with long average
   stage durations ahead of it, such that its computed expected close date
   is more than 90 days out. **Expected**: it does not appear in any
   bucket and does not contribute to `total_weighted_value`.

## Regression check

Confirm the existing 7 charts on the Funnel report page are unaffected —
same values as before this feature, since `sales_forecast` is purely
additive to the response and to the page's markup.
