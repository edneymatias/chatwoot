# API Contract: Closing Required Fields

All routes are account-scoped, mirroring `pipeline_stages`/`opportunities` under
`/api/v1/accounts/:account_id/...`. Admin-only for configuration endpoints (mirrors
`PipelineStageRequiredFieldPolicy`, all actions gated on `@account_user.administrator?`).

## Configuration endpoints (new)

### `POST /api/v1/accounts/:account_id/pipeline_closing_required_fields`

Creates (or replaces, per outcome+attribute pair) a closing requirement.

**Request body**:
```json
{
  "pipeline_closing_required_field": {
    "custom_attribute_definition_id": 123,
    "outcome": "lost"
  }
}
```

**Success (200)**:
```json
{
  "id": 1,
  "account_id": 1,
  "custom_attribute_definition_id": 123,
  "outcome": "lost",
  "created_at": "...",
  "updated_at": "..."
}
```

**Failure (422)** — e.g. attribute is not an opportunity attribute, or duplicate for the same
`(account, attribute, outcome)`:
```json
{ "error": "Custom attribute definition must be an opportunity attribute" }
```

### `DELETE /api/v1/accounts/:account_id/pipeline_closing_required_fields/:id`

Deletes a closing requirement by its own `id` (not by `custom_attribute_definition_id`, since — unlike
the per-stage sibling — a single attribute may have two rows, one per outcome, so the sibling
pattern of `find_by!(custom_attribute_definition_id: params[:id])` is ambiguous here and must key
on the join row's own primary key instead).

**Success**: `204 No Content` (or `200`/`head :ok`, matching sibling convention).

### `GET /api/v1/accounts/:account_id/pipeline_closing_required_fields`

Lists all closing requirements for the account (both outcomes), for the settings screen to render
both lists from one fetch.

**Success (200)**:
```json
[
  { "id": 1, "custom_attribute_definition_id": 123, "outcome": "won" },
  { "id": 2, "custom_attribute_definition_id": 456, "outcome": "lost" }
]
```

## Enforcement (existing endpoint, unchanged contract)

### `PATCH /api/v1/accounts/:account_id/opportunities/:id`

No route or param changes. Existing `missing_required_fields` 422 contract is reused as-is:

**Failure (422)** — status change to `won`/`lost` blocked by unmet closing requirement:
```json
{
  "error": "Missing required fields to close this opportunity",
  "missing_required_fields": {
    "custom_attribute_keys": ["loss_reason"]
  }
}
```

**Retry request** (same endpoint, now including the previously-missing attribute):
```json
{
  "opportunity": {
    "status": "lost",
    "custom_attributes": { "loss_reason": "budget" }
  }
}
```

**Success (200)**: standard opportunity JSON, `status: "lost"`.
