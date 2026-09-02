# Contract: `GET /api/v1/accounts/{account_id}/pipeline_stage_aggregates`

Controller: `custom/app/controllers/api/v1/accounts/pipeline_stage_aggregates_controller.rb`
(gated by `Concerns::KanbanFeatureGuard`, requires `feature_enabled?('opportunities')`).

## Request

| Param | Type | Required | Notes |
|---|---|---|---|
| `stage_ids[]` | array of integer | Yes | Existing param, unchanged. 422 with `{ "error": "stage_ids is required" }` if blank — unchanged. |
| `q` | string | No | **NEW.** Free-text search term, same semantics as `Api::V1::Accounts::OpportunitiesController#index`'s `q` (matches title, contact name, and campaign attribution fields per this feature's Part 1). |
| `status` | string (`open`\|`won`\|`lost`\|`all`) | No | **NEW.** Same semantics as the opportunities list endpoint. Omitted → defaults to `open` (unchanged default behavior), unless a `status` condition is present in `payload`. |
| `payload` | JSON string (array of filter conditions) | No | **NEW.** Same advanced-filter payload shape already accepted by the opportunities list endpoint (`attribute_key`/`filter_operator`/`values` triples), including a `status` condition. |
| `custom_attributes` | hash | No | **NEW.** Same semantics as the opportunities list endpoint. |

## Response — 200 OK

```json
[
  { "pipeline_stage_id": 1, "count": 3, "value_sum": 1500.0 },
  { "pipeline_stage_id": 2, "count": 0, "value_sum": 0.0 }
]
```

One entry per requested `stage_id`, in the order given, even if a stage has zero matching
opportunities (unchanged behavior — every requested stage always gets an entry).

**Breaking change from current behavior**: response keys renamed `open_count` → `count`,
`open_value_sum` → `value_sum`. This is a fork-internal endpoint with exactly one consumer
(`app/javascript/dashboard/api/pipelineStageAggregates.js`), updated in the same change — no
transition/dual-read period needed (see research.md §5 for rationale).

## Response — 422 Unprocessable Entity

```json
{ "error": "stage_ids is required" }
```
Unchanged.

## Behavioral contract

- With no `q`/`payload`/`status` param, response is byte-for-byte equivalent (aside from the key
  rename) to today's pre-feature response: open-only counts/values per stage (spec.md FR-009/SC-004).
- Every param this contract lists is handled identically to how
  `Api::V1::Accounts::OpportunitiesController#index` already handles the same-named param, via the
  shared `OpportunitiesFilter` — this contract does not define new filter semantics of its own.
