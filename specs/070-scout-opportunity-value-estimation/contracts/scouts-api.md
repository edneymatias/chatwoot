# Contract: Scouts API — interest attribute & value table

Extends the existing `Api::V1::Accounts::ScoutsController` contract
(`custom/app/controllers/api/v1/accounts/scouts_controller.rb`). No new endpoints — two new
permitted/returned fields on the existing `create`/`update`/`show`/`index` actions, following the
same shape as the existing `required_custom_attribute_definition_ids` write / `required_custom_attribute_definitions`
read pair.

## Write: `POST /api/v1/accounts/:account_id/scouts` and `PATCH .../scouts/:id`

New permitted params (added to `scout_params`, alongside the existing `allowed` list):

| Param | Type | Notes |
|---|---|---|
| `interest_attribute_definition_id` | integer or `null` | Must reference a `CustomAttributeDefinition` belonging to the same account with `attribute_display_type: list` and `attribute_model: opportunity_attribute`. Assigning one with any other `attribute_display_type` is rejected by a model-level validation (see `data-model.md`) — the request fails with `422 Unprocessable Entity` and `@scout.errors.full_messages` in the response body, the same failure shape already used for every other `scout_params` validation error. This is the actual system-of-record enforcement of spec FR-001; the config UI's interactive chip selector (only offering list-type opportunity attributes) is a UX convenience on top of it, not the only guard, since this endpoint can be called directly without going through the dashboard. |
| `value_by_interest` | hash (`{ string => number }`) | Permitted as a free-form hash, mirroring how `audience` is already permitted as a structured array param. Keys not present in the interest attribute's `attribute_values` are harmless (simply never matched at lookup time) — no server-side key validation is added, consistent with "Smallest Production-Ready Change". |

Example request body (update):

```json
{
  "scout": {
    "interest_attribute_definition_id": 42,
    "value_by_interest": {
      "Implante": 2500,
      "Clareamento": 400
    }
  }
}
```

## Read: `GET .../scouts/:id` and `GET .../scouts` (index)

`include_associations` gains one entry, and includes `attribute_values` on both custom attribute associations:

```json
{
  "include": {
    "inboxes": { "only": ["id", "name", "channel_type"] },
    "required_custom_attribute_definitions": { "only": ["id", "attribute_key", "attribute_display_name", "attribute_display_type", "attribute_model", "attribute_values"] },
    "interest_attribute_definition": { "only": ["id", "attribute_key", "attribute_display_name", "attribute_display_type", "attribute_model", "attribute_values"] }
  }
}
```

Top-level scout JSON also includes the raw `value_by_interest` jsonb hash as-is (already returned
automatically as a column, same as `audience` is today — no serializer change needed beyond the
association include above).

## No change to other Scout endpoints or to the tool-calling contract

`manage_opportunity`'s tool parameters (`custom/app/services/custom/scout/tools/manage_opportunity.rb`)
are unchanged — the LLM-facing tool signature (`action`, `title`, `stage_id`, `estimated_value`,
`custom_attributes`, `opportunity_id`) is untouched. This feature's new behavior is entirely
internal to the tool's implementation (two new call sites), invisible to the model calling it,
per spec FR-004/FR-008 ("the model never needs to know this exists").
