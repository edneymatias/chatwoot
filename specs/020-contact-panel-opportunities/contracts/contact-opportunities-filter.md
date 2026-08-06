# Contract: List a contact's opportunities

Extends the existing `GET` opportunities index action with a new optional filter param. No new route.

## Request

```
GET /api/v1/accounts/:account_id/opportunities?contact_id=:contact_id
```

| Param | Location | Required | Notes |
|---|---|---|---|
| `contact_id` | query | No | When present, restricts results to opportunities belonging to that contact. Omitting it preserves today's unfiltered/`pipeline_stage_id`-filtered behavior. |
| `pipeline_stage_id` | query | No | Existing filter, unaffected; may be combined with `contact_id` (both apply as `AND` via chained `where`). |

## Response — 200 OK

Same shape as the existing unfiltered index response: an array of opportunity JSON objects (title, status, `pipeline_stage_id`, `value`, `custom_attributes`, `assignee_id`, `created_at`, etc.), ordered `created_at DESC` (existing default ordering — satisfies FR-001's most-recent-first requirement with no new ordering logic).

## Errors

No new error cases introduced. Authorization/feature-gating behaves exactly as it does today for the existing `index` action (`Concerns::KanbanFeatureGuard`, existing Pundit policy) — this filter does not change who can call the endpoint or what they can see beyond narrowing by `contact_id`.

---

# Contract: Update an opportunity (extended payload)

No new route; documents the payload the contact-panel edit dialog sends, which is a superset of fields the existing action already accepts.

## Request

```
PUT /api/v1/accounts/:account_id/opportunities/:id
```

```json
{
  "title": "string",
  "pipeline_stage_id": "integer",
  "value": "decimal, nullable",
  "custom_attributes": { "...": "..." },
  "assignee_id": "integer, nullable"
}
```

All fields are already permitted by the existing controller's strong params for `update` — this feature relies on the dialog always sending `pipeline_stage_id` alongside the fields it already sent, rather than requiring a controller change.

## Response — 200 OK

Existing updated opportunity JSON.

## Response — 422 Unprocessable Entity (forward-move validation failure)

Existing shape, unchanged, produced by `Opportunity#missing_required_fields` when `validate_forward_stage_move_requirements` fails (i.e., `pipeline_stage_id` is being moved to a stage with a strictly later `position` than the current stage, and required fields for that stage are missing):

```json
{
  "errors": ["..."],
  "custom_attribute_keys": ["key_a", "key_b"],
  "requires_value": true
}
```

Backward moves (destination stage `position` ≤ current stage `position`) never produce this 422 for missing-field reasons (FR-011).

---

# Contract: Reopen a closed opportunity

Uses the same update route as above with a minimal payload, dispatched independently of the dialog's main save action.

## Request

```
PUT /api/v1/accounts/:account_id/opportunities/:id
```

```json
{ "status": "open" }
```

## Response — 200 OK

Existing updated opportunity JSON with `status: "open"`. No stage-requirements validation is triggered by this call, since `pipeline_stage_id` is not part of the payload and therefore not "moving" (FR-014, spec Edge Cases).
