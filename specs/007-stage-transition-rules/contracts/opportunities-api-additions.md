# Contract: Opportunities API additions

Additive changes to the existing `custom/app/controllers/api/v1/accounts/opportunities_controller.rb`.

## Create / Update — permitted params addition

```json
{
  "opportunity": {
    "value": 5000,
    "custom_attributes": { "budget": 3000, "decision_maker": "Jane Doe" }
  }
}
```

`value` and `custom_attributes` are permitted on both `create` and `update`, alongside the
existing `title`/`contact_id`/`pipeline_stage_id`/`status`/`assignee_id` params. `custom_attributes`
is permitted as an open hash, matching the existing jsonb custom-attribute param pattern used
elsewhere in Chatwoot (e.g. `Conversation`/`Contact` custom attribute params).

Creation (`POST`) never triggers the required-field validation regardless of the selected stage
(FR-010) — the validation only fires `on: :update`.

## Update — forward move validation failure response

**Request** (forward move into a stage with unmet requirements):
```json
{ "opportunity": { "pipeline_stage_id": 3 } }
```

**Response `422`**:
```json
{
  "error": "Missing required fields for this stage",
  "missing_required_fields": {
    "custom_attribute_keys": ["budget", "decision_maker"],
    "requires_value": true
  }
}
```

- `custom_attribute_keys`: `attribute_key`s of unmet `PipelineStageRequiredField`s on the
  destination stage (empty array if none missing).
- `requires_value`: `true` only if the destination stage has `requires_deal_value: true` **and**
  `value` is unset on this opportunity; otherwise `false`.

This is the defensive fallback path (direct API calls, stale frontend state, race conditions) —
the primary UX flow is the proactive client-side check in `KanbanBoard.vue` that avoids
dispatching this request in the first place when fields are already known to be missing.

## Update — forward move validation success (fields satisfied, or non-forward move)

**Response `200`**: existing `render json: @opportunity` shape, now including `value` and
`custom_attributes` in the serialized body (already exposed via default `as_json` since they're
plain columns — no `as_json` override change needed beyond what already exists).

## Backward/lateral move

**Request**:
```json
{ "opportunity": { "pipeline_stage_id": 1 } }
```
where stage `1`'s position is `<=` the opportunity's current stage position.

**Response `200`**: move succeeds unconditionally, regardless of `custom_attributes`/`value`
completeness (FR-006 of spec) — no validation runs at all for this request.
