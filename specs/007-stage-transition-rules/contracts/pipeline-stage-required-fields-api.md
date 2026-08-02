# Contract: Pipeline Stage Required Fields API

New nested resource under the existing `pipeline_stages` route, following the same
`Api::V1::Accounts::*` controller shape as `custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb`.

## Route

```
config/routes.rb — inside the existing `resources :pipeline_stages` block:
  resources :required_fields, only: [:create, :destroy], controller: 'pipeline_stage_required_fields'
```

Effective paths:
- `POST /api/v1/accounts/:account_id/pipeline_stages/:pipeline_stage_id/required_fields`
- `DELETE /api/v1/accounts/:account_id/pipeline_stages/:pipeline_stage_id/required_fields/:id`

## POST (create / assign)

**Request body**:
```json
{ "required_field": { "custom_attribute_definition_id": 42 } }
```

**Behavior**: Deletes any existing `PipelineStageRequiredField` row for that
`custom_attribute_definition_id` (in this account, regardless of which stage currently holds it),
then creates a new row for the target `pipeline_stage_id`, atomically within the request (per
research.md §2 — "reassignment steals it").

**Response `200`**:
```json
{
  "id": 7,
  "pipeline_stage_id": 3,
  "custom_attribute_definition_id": 42,
  "attribute_key": "budget",
  "attribute_display_name": "Budget",
  "attribute_display_type": "currency"
}
```

**Response `422`** (e.g. `custom_attribute_definition_id` does not reference an
`opportunity_attribute`-model definition, or doesn't belong to this account):
```json
{ "error": "Custom attribute definition must be an opportunity attribute" }
```

## DELETE (destroy / unassign)

**Response `200`**: `{}` (or `head :ok`, matching the existing `PipelineStagesController#destroy`
convention).

## PipelineStagesController#index / #show — response shape addition

Existing endpoint, additive fields only (no breaking change to current consumers):

```json
{
  "id": 3,
  "name": "Qualified",
  "position": 2,
  "requires_deal_value": true,
  "required_custom_attribute_definitions": [
    {
      "id": 42,
      "attribute_key": "budget",
      "attribute_display_name": "Budget",
      "attribute_display_type": "currency"
    }
  ]
}
```

## PipelineStagesController#update — request body addition

```json
{ "pipeline_stage": { "requires_deal_value": true } }
```

Additive permitted param; existing `name`/`description`/`position` params unchanged.
