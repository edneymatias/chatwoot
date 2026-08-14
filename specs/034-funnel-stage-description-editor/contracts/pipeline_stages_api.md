# Contract: Pipeline Stages API (`description` field addition)

**Feature**: `034-funnel-stage-description-editor` | **Date**: 2026-08-14

No new endpoints are introduced. This documents the delta to the existing
`Api::V1::Accounts::PipelineStagesController` contract (`/api/v1/accounts/:account_id/pipeline_stages`).

## `PATCH /api/v1/accounts/:account_id/pipeline_stages/:id`

**Request body** (existing shape, `description` already accepted but previously discarded):

```json
{
  "pipeline_stage": {
    "description": "<p>Use this stage when the deal is <strong>qualified</strong>.</p>"
  }
}
```

- `description`: string, optional, sanitized HTML fragment produced by the stage description
  editor. May be omitted, `null`, or an empty/whitespace string to clear it.

**Response body** (200 OK, existing shape, now includes a working `description`):

```json
{
  "id": 12,
  "name": "Qualified",
  "position": 2,
  "description": "<p>Use this stage when the deal is <strong>qualified</strong>.</p>",
  "requires_deal_value": false,
  "total_display_mode": "value_sum",
  "accent_color": "#3B82F6",
  "stale_after_days": null,
  "required_custom_attribute_definitions": []
}
```

**Behavioral contract**:
- Saving a `description` and then fetching the stage again (via `GET`, or the `update` response
  itself) MUST return the same `description` value (FR-001, FR-002).
- Sending an empty/whitespace `description` MUST clear it (stored as blank) (FR-003).

## `GET /api/v1/accounts/:account_id/pipeline_stages`

**Response body** (existing shape, each stage object now includes a working `description`):

```json
[
  {
    "id": 12,
    "name": "Qualified",
    "description": "<p>Use this stage when the deal is <strong>qualified</strong>.</p>",
    "...": "..."
  }
]
```

This is the payload the kanban board consumes to render the per-column info panel (FR-006–FR-011).

## `POST /api/v1/accounts/:account_id/pipeline_stages`

**Request/response**: same `description` field, same semantics as `PATCH`, accepted at creation
time. Not a required part of this feature's scope (create flow is unaffected/untested by this
feature), documented here only for completeness since the controller shares `pipeline_stage_params`.
