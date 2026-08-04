# Contract: Opportunity Funnel Report endpoint

## `GET /api/v1/accounts/:account_id/opportunity_funnel_reports`

Controller: `Api::V1::Accounts::OpportunityFunnelReportsController#index`
(`custom/app/controllers/api/v1/accounts/`)

### Authorization

- `Concerns::KanbanFeatureGuard` — 403 `{ "error": "Opportunities feature not enabled" }` if `account.feature_enabled?('opportunities')` is false.
- `authorize(:report, :view?)` (core `ReportPolicy`, unmodified) — Pundit `NotAuthorizedError` (→ 403) unless the current account user is an administrator (or Enterprise-extended equivalent via `ReportPolicy.prepend_mod_with`).

### Request

| Param | Type | Required | Notes |
|---|---|---|---|
| `since` | unix timestamp (integer, as string) | yes | Start of the period. Same convention as `Api::V2::Accounts::ReportsController`. |
| `until` | unix timestamp (integer, as string) | yes | End of the period. |

No `type`, `group_by`, `id`, or any other selector params — the endpoint
always returns the full fixed set of 7 metrics (FR-003).

### Response — `200 OK`

```json
{
  "conversion_funnel": {
    "labels": ["Leads Recebidos", "Em Contato", "Proposta Enviada"],
    "data": [100.0, 62.5, 18.0]
  },
  "win_rate": {
    "won": 12,
    "lost": 5
  },
  "pipeline_value_by_stage": {
    "labels": ["Leads Recebidos", "Em Contato", "Proposta Enviada"],
    "data": [15000.0, 42000.0, 9000.0]
  },
  "avg_time_in_stage": {
    "labels": ["Leads Recebidos", "Em Contato", "Proposta Enviada"],
    "data": [1.5, 4.2, 2.8]
  },
  "new_opportunities_over_time": {
    "labels": ["2026-07-01", "2026-07-02", "2026-07-03"],
    "data": [3, 5, 2]
  },
  "sales_cycle_time": {
    "average_days": 9.4
  },
  "performance_by_assignee": [
    { "assignee_id": 7, "assignee_name": "Jane Doe", "count": 6, "value": 24000.0 },
    { "assignee_id": null, "assignee_name": "Unassigned", "count": 1, "value": 1200.0 }
  ]
}
```

### Field notes

- `conversion_funnel.labels` — pipeline stage names, ordered by `PipelineStage#position`. `data[i]` is the percentage (0–100) of opportunities created in the period that reached `labels[i]` or a later stage.
- `win_rate` — raw counts, not a percentage; the frontend computes/derives the headline `%` for `ReportMetricCard` (`won / (won + lost) * 100`, `0` when both are `0`).
- `pipeline_value_by_stage` / `avg_time_in_stage` — **not** period-filtered; identical regardless of `since`/`until` (FR-007, FR-008). `avg_time_in_stage.data[i]` is in days (float), averaged only over completed (non-current) stage intervals.
- `new_opportunities_over_time.labels` — ISO `YYYY-MM-DD` day buckets spanning `since`..`until`; days with zero opportunities are included with `data[i] = 0` (no gaps).
- `sales_cycle_time.average_days` — `null` when there are zero won opportunities closed in the period (not `0`, to distinguish "no data" from "won instantly").
- `performance_by_assignee` — ranked descending by `value`; an entry with `assignee_id: null` / `assignee_name: "Unassigned"` groups won opportunities with no assignee (per spec Assumptions).

### Empty-state response (FR-006/FR-012)

For an account/period with zero matching opportunities, every key is still
present with zero-valued/empty contents (never omitted, never a 4xx/5xx):

```json
{
  "conversion_funnel": { "labels": ["Leads Recebidos", "Em Contato"], "data": [0.0, 0.0] },
  "win_rate": { "won": 0, "lost": 0 },
  "pipeline_value_by_stage": { "labels": ["Leads Recebidos", "Em Contato"], "data": [0.0, 0.0] },
  "avg_time_in_stage": { "labels": ["Leads Recebidos", "Em Contato"], "data": [0.0, 0.0] },
  "new_opportunities_over_time": { "labels": [], "data": [] },
  "sales_cycle_time": { "average_days": null },
  "performance_by_assignee": []
}
```

Note `pipeline_value_by_stage`/`avg_time_in_stage` can independently be
non-empty even when the other 5 period-scoped keys are empty (FR-006), since
they read current-state/lifetime data unaffected by `since`/`until`.

### Errors

| Status | Condition |
|---|---|
| 403 | Opportunities feature disabled for the account, or requester is not an administrator |
| 401 | Not authenticated (standard `Api::V1::Accounts::BaseController` behavior) |

No 422/500 for missing `since`/`until` — `DateRangeHelper` treats a blank
range as "no filter," which for this endpoint's period-scoped metrics is
equivalent to returning them empty; the two non-period-filtered metrics are
unaffected either way.
