# Contract: Scouts API — `audience` field

Extends the existing Scout REST endpoints (`Api::V1::Accounts::ScoutsController`) with one new
read/write field. No new routes, no new controller actions. All existing behavior, params, and
responses for fields other than `audience` are unchanged.

## Affected endpoints

- `GET /api/v1/accounts/:account_id/scouts` (index) — response only
- `GET /api/v1/accounts/:account_id/scouts/:id` (show) — response only
- `POST /api/v1/accounts/:account_id/scouts` (create) — request + response
- `PATCH /api/v1/accounts/:account_id/scouts/:id` (update) — request + response

## Request shape (create/update)

`audience` is accepted as an optional array of condition objects, nested under the existing
`scout` param key (matching how `follow_up_delays_hours` is already accepted):

```json
{
  "scout": {
    "audience": [
      {
        "attribute_key": "phone_number",
        "filter_operator": "equal_to",
        "values": ["+5511999999999"],
        "query_operator": "and"
      },
      {
        "attribute_key": "labels",
        "filter_operator": "contains",
        "values": ["beta"],
        "query_operator": "or"
      }
    ]
  }
}
```

- Omitting `audience` entirely on `update` leaves the stored value unchanged (standard
  `permit`/`update` semantics — only submitted keys are written).
- Submitting `"audience": []` explicitly clears the target audience (Scout reverts to engaging
  everyone — spec FR-003, User Story 1 Acceptance Scenario 4).
- No server-side schema validation is added for the shape of individual condition objects (see
  data-model.md — the UI is the sole writer and always emits well-formed conditions); malformed
  entries are handled defensively at evaluation time (per-condition fail-safe, FR-007), not
  rejected at the API boundary.
- **Controller `permit` syntax**: verified against this codebase's own precedent for an
  array-of-hashes-with-a-nested-array-value —
  `app/controllers/api/v1/accounts/automation_rules_controller.rb`'s
  `conditions: [:attribute_key, :filter_operator, :query_operator, { values: [] }]`. Use the same
  shape here: `audience: [:attribute_key, :filter_operator, :query_operator, { values: [] }]`.
  (The source design doc's sketch, `[%i[attribute_key filter_operator query_operator] +
  [values: []]]`, evaluates to a doubly-nested array and does not permit the intended shape —
  do not use it.)

## Response shape

`audience` appears verbatim (whatever array is currently stored) in every Scout JSON
representation returned by `index`, `show`, `create`, and `update` — no transformation, since the
controller's existing `as_json(include_associations)` call already serializes all column values
including new columns automatically.

```json
{
  "id": 42,
  "name": "Sales Scout",
  "enabled": true,
  "audience": [
    {
      "attribute_key": "phone_number",
      "filter_operator": "equal_to",
      "values": ["+5511999999999"],
      "query_operator": "and"
    }
  ],
  "...": "...other existing Scout fields unchanged..."
}
```

## Authorization

Unchanged — governed by the existing `check_authorization(Scout)` `before_action`, same as every
other Scout field. No new permission tier is introduced for editing `audience`.

## Backward compatibility

Existing API clients that never send `audience` are unaffected: the column defaults to `[]` at the
database level, so pre-existing Scouts and any client that omits the field observe the current
"engage everyone" behavior with no migration-time behavior change (spec SC-003).
