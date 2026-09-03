# Contract: Campaign Performance Reports API

## `GET /api/v1/accounts/:account_id/campaign_performance_reports`

Mirrors `GET .../opportunity_funnel_reports` exactly (same auth, same date-range param
convention, same response-is-the-whole-payload shape — no pagination, no envelope).

**Authorization**: `authorize :report, :view?` (Pundit `ReportPolicy`) — identical to every other
report endpoint in this codebase. No new permission level.

**Query parameters**:

| Param | Type | Required | Notes |
|---|---|---|---|
| `since` | integer (unix timestamp) | No | Range start. Omitted → unbounded start, same as `DateRangeHelper` used by `opportunity_funnel_reports`. |
| `until` | integer (unix timestamp) | No | Range end. |

**Response `200`**:

```json
{
  "summary": {
    "leads": 128,
    "milestone_stage_name": "Agendado",
    "milestone_count": 41,
    "milestone_rate_pct": 32.0,
    "won_count": 19,
    "won_rate_pct": 14.8,
    "lost_count": 33,
    "lost_rate_pct": 25.8,
    "distinct_campaigns": 6,
    "distinct_adsets": 14,
    "distinct_ads": 22
  },
  "by_campaign": [
    { "campaign_name": "Black Friday 2026", "leads": 54, "won_count": 9, "lost_count": 12, "milestone_count": 20, "milestone_rate_pct": 37.0 },
    { "campaign_name": "Não identificado", "leads": 8, "won_count": 1, "lost_count": 3, "milestone_count": 1, "milestone_rate_pct": 12.5 }
  ],
  "by_adset": [
    { "campaign_name": "Black Friday 2026", "campaign_adset_name": "Lookalike 1%", "leads": 30, "won_count": 6, "lost_count": 5, "milestone_count": 12, "milestone_rate_pct": 40.0 }
  ],
  "by_ad": [
    { "campaign_name": "Black Friday 2026", "campaign_adset_name": "Lookalike 1%", "campaign_ad_name": "Video A", "leads": 18, "won_count": 4, "lost_count": 2, "milestone_count": 8, "milestone_rate_pct": 44.4 }
  ]
}
```

**Response shape rules** (from spec FR-005/FR-010/FR-011):

- When the account has no stage flagged `campaign_report_milestone`, `summary.milestone_stage_name`
  is `null`, and `summary.milestone_count`/`milestone_rate_pct` **and** every row's
  `milestone_count`/`milestone_rate_pct` keys are omitted entirely (not `null`, not `0`) — the
  frontend uses key presence, not truthiness, to decide whether to render the milestone
  card/column.
- Rows whose grouping key is missing render with the literal string `"Não identificado"` in place
  of `campaign_name`/`campaign_adset_name`/`campaign_ad_name` — they are real rows, included in
  `leads`/`won_count`/`lost_count`/`milestone_count`, but their group key never counts toward
  `summary.distinct_campaigns`/`distinct_adsets`/`distinct_ads`.
- All three of `by_campaign`/`by_adset`/`by_ad` are always returned together in one response (no
  separate endpoint or param per tab) — the frontend tab switch re-renders from already-fetched
  data.
- Every array is sorted by `leads` descending; this order is fixed, not client-adjustable (per
  Clarifications session 2026-09-02).

**Response `403`**: Standard Pundit-denial JSON (same shape as every other report endpoint) when
the current user lacks report-view permission. Feature-gating (attribution disabled / no resolved
data) is **not** a 403 — it's a frontend-only concern (the sidebar entry doesn't render, so the
page is never navigated to); the endpoint itself does not re-check
`CampaignAttributionSetting.enabled`.

## `GET /api/v1/accounts/:account_id/campaign_attribution_setting` (existing — extended)

No new params, no new auth. One new field added to the existing response:

| Field | Type | Notes |
|---|---|---|
| `resolved_data_present` | boolean | **New.** `true` when the account has at least one opportunity with `campaign_resolution_status: 'resolved'`. Used by the frontend to gate the new sidebar entry, alongside the existing `enabled` field. |

Existing fields (`enabled`, `connected`, `pending_count`, `meta_app_id`, `meta_api_version`) are
unchanged.
