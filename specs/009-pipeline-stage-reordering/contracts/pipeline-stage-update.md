# Contract: `PATCH /api/v1/accounts/:account_id/pipeline_stages/:id`

Existing endpoint (`custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb#update`). This feature changes its behavior and response shape **only when the `position` param is present and differs from the stage's current position** — all other update calls (renaming, editing description, toggling `requires_deal_value`, etc.) are unaffected.

## Authorization

Unchanged: gated by `PipelineStagePolicy#update?` (`@account_user.administrator?`), consistent with FR-005.

## Request

```
PATCH /api/v1/accounts/:account_id/pipeline_stages/:id
Content-Type: application/json

{
  "pipeline_stage": {
    "position": <integer>   // 1-based target position within the account's stage list
  }
}
```

Same params contract as today (`pipeline_stage_params` already permits `:position`); no new params are introduced.

## Behavior

- If `position` is absent from the request, or equals the stage's current `position`: behaves exactly as before (single-record update, no renumbering) — satisfies FR-007 (no-op on drop-in-place).
- If `position` is present and differs from the current value:
  1. Runs the full reorder within a single DB transaction (see [data-model.md](../data-model.md) — State transition: Reorder).
  2. All siblings whose position shifted are persisted alongside the moved stage.
  3. Response body changes from "single stage" to "full ordered list of the account's stages" (see below).

## Response — reorder case (position changed)

```
200 OK
Content-Type: application/json

[
  {
    "id": 12,
    "name": "Leads Recebidos",
    "position": 1,
    "description": "...",
    "requires_deal_value": false,
    "required_custom_attribute_definitions": [ ... ]
  },
  {
    "id": 15,
    "name": "Em Contato",
    "position": 2,
    ...
  }
]
```

- Array is ordered by the new `position` (ascending), i.e. already in display order.
- Every element uses the same shape currently returned for a single stage (including the existing `required_custom_attribute_definitions` include) — no new fields.

## Response — non-reorder case (position absent/unchanged, or any other field updated)

Unchanged from today: a single stage JSON object (not an array).

```
200 OK
{ "id": 12, "name": "...", "position": 1, ... }
```

## Error cases (unchanged)

- `422 Unprocessable Entity` with `{ "error": "<messages>" }` on validation failure — same as today. A validation failure during reorder rolls back the whole transaction (no partial renumbering), and the moved stage's own validation errors are what's surfaced, consistent with existing behavior.

## Frontend contract impact

`dashboard/store/modules/pipelineStages/actions.js#update` must branch on whether `response.data` is an Array (reorder — replace the full store collection) or an Object (single-stage update — existing `UPDATE_STAGE` commit), so both the Pipeline Stages settings screen and the Kanban board's shared `pipelineStages` store module stay correct without an extra round trip (FR-003).
