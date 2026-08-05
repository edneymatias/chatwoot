# Contract addition: `sales_forecast` key on the Opportunity Funnel Report endpoint

This extends the existing contract at
`specs/015-opportunity-funnel-report/contracts/opportunity_funnel_report.md`
for `GET /api/v1/accounts/:account_id/opportunity_funnel_reports`. No new
endpoint, no new route, no request-parameter changes — the existing `since`/
`until` params are accepted as before but do **not** affect `sales_forecast`
(it is never period-filtered, matching `pipeline_value_by_stage` and
`avg_time_in_stage`).

## Response — `200 OK` (new key only)

### Sufficient-data case

```json
{
  "...": "... existing 7 keys unchanged ...",
  "sales_forecast": {
    "status": "ok",
    "total_weighted_value": 45600.0,
    "buckets": {
      "day_0": { "count": 1, "weighted_value": 3200.0 },
      "1_30": { "count": 4, "weighted_value": 12400.0 },
      "31_60": { "count": 6, "weighted_value": 21200.0 },
      "61_90": { "count": 3, "weighted_value": 8800.0 }
    }
  }
}
```

### Insufficient-data case

```json
{
  "...": "... existing 7 keys unchanged ...",
  "sales_forecast": {
    "status": "insufficient_data"
  }
}
```

`total_weighted_value` and `buckets` are omitted entirely (not `null`, not
zero-valued) when `status` is `"insufficient_data"` — this is the signal
the frontend uses to render the empty state instead of a zeroed chart
(FR-009).

## Field notes

- `sales_forecast.status` — `"ok"` when the account has at least one
  completed stage-transition for every pipeline stage and at least one
  `won` and one `lost` opportunity overall (lifetime, whole account);
  otherwise `"insufficient_data"` (FR-006).
- `total_weighted_value` — sum of all four buckets' `weighted_value`;
  represents all currently-open pipeline expected to close within 90 days,
  not just any single bucket (per spec Context). There is no separate
  raw/unweighted baseline figure in the response — the card's headline is
  this weighted total.
- `buckets` — exactly four fixed keys: `"day_0"`, `"1_30"`, `"31_60"`,
  `"61_90"`. Each `weighted_value` is the sum of `value *
  stage_win_probability` for open opportunities whose computed
  days-until-close falls in that bucket. An opportunity whose computed
  close date has already passed (offset `<= 0`) is counted in `"day_0"`.
  An opportunity whose computed close date is more than 90 days out is
  excluded from every bucket and from `total_weighted_value` (FR-004).
- Boundary convention: a days-until-close value landing exactly on a
  bucket edge (30 or 60) counts toward the earlier/lower bucket.

## Errors

Same as the base endpoint contract — no new error conditions introduced
by `sales_forecast` (it never 4xx/5xxs independently of the rest of the
response).
