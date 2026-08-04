# Contract: Pipeline Stage Aggregates API

## `GET /api/v1/accounts/:account_id/pipeline_stage_aggregates`

Read-only endpoint. Returns the open-opportunity count and value sum for each requested pipeline
stage belonging to the current account. Mirrors the authorization/guard pattern of
`Api::V1::Accounts::PipelineStagesController` (`Concerns::KanbanFeatureGuard`,
`check_authorization` via Pundit).

### Request

| Param | Type | Required | Notes |
|---|---|---|---|
| `stage_ids[]` | array of integer | Yes | Pipeline stage IDs to compute aggregates for. Stage IDs not belonging to `Current.account` are silently excluded from the response (no error), matching the account-scoping already used by `PipelineStagesController`. |

Example: `GET /api/v1/accounts/1/pipeline_stage_aggregates?stage_ids[]=10&stage_ids[]=11`

### Response — `200 OK`

A JSON array. One entry per requested stage that has at least one open opportunity. **Stages with
zero open opportunities are simply absent from the array** — the frontend treats absence as
`open_count: 0, open_value_sum: 0`.

```json
[
  { "pipeline_stage_id": 10, "open_count": 4, "open_value_sum": "12500.0" },
  { "pipeline_stage_id": 11, "open_count": 1, "open_value_sum": "300.0" }
]
```

### Errors

- Missing/empty `stage_ids[]`: `422 Unprocessable Entity` with `{ "error": "stage_ids is required" }`.
- Unauthorized account access: standard Pundit `403 Forbidden`, same as sibling pipeline-stage
  endpoints.

### Notes

- Query shape: `Current.account.opportunities.where(pipeline_stage_id: stage_ids, status:
  :open).group(:pipeline_stage_id).count` and `.sum(:value)`, merged into one payload per stage.
- No pagination — `stage_ids[]` is expected to be small (typically 1-2 for a surgical
  post-mutation refresh, or the full stage list on initial board load).
- Consumed by the frontend on: initial board mount (all stage IDs) and after any of: card move,
  card create, status change, value edit (only the affected `stage_id`(s)).
