# API Contract: Pipeline Card Field Configs

Base path: `/api/v1/accounts/:account_id/pipeline_card_field_configs`

Authorization: account administrator only (all actions), matching
`PipelineClosingRequiredFieldPolicy`.

## `GET /` (index)

Lists the account's configured card fields, ordered by `position`.

**Response `200`**:
```json
[
  {
    "id": 1,
    "field_type": "custom_attribute",
    "custom_attribute_definition_id": 42,
    "color": "#4F46E5",
    "position": 1
  },
  {
    "id": 2,
    "field_type": "deal_value",
    "custom_attribute_definition_id": null,
    "color": "#16A34A",
    "position": 2
  }
]
```

## `POST /` (create)

**Request**:
```json
{
  "pipeline_card_field_config": {
    "field_type": "custom_attribute",
    "custom_attribute_definition_id": 42,
    "color": "#4F46E5"
  }
}
```
(`custom_attribute_definition_id` omitted when `field_type` is `deal_value`.)

**Response `200`**: the created record (same shape as index item).

**Response `422`** when:
- the account already has 3 configured fields
- `field_type: deal_value` is submitted and one already exists for the account
- the same `custom_attribute_definition_id` is already configured for the account
- the referenced `custom_attribute_definition` is not an `opportunity_attribute`
- `color` is blank

```json
{ "error": "<validation message>" }
```

## `PATCH/PUT /:id` (update)

**Request**:
```json
{ "pipeline_card_field_config": { "color": "#DC2626" } }
```

Only `color` is expected to change post-creation (field selection itself is add/remove, not
in-place field-type swap).

**Response `200`**: the updated record. **Response `422`** on validation failure (e.g. blank color).

## `DELETE /:id` (destroy)

**Response `200`** (`head :ok`), matching sibling controllers.
