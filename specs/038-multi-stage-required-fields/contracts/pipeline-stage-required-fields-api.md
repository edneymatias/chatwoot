# Contract: Multi-Stage Required Fields API

This document specifies the behavior changes to the existing Pipeline Stage Required Fields endpoints.

## Endpoints

### 1. Assign Required Field to a Stage

- **Route**: `POST /api/v1/accounts/:account_id/pipeline_stages/:pipeline_stage_id/required_fields`
- **Controller**: `Api::V1::Accounts::PipelineStageRequiredFieldsController#create`
- **Request Body**:
  ```json
  {
    "pipeline_stage_required_field": {
      "custom_attribute_definition_id": 42
    }
  }
  ```

#### Behavior Changes:
- **Before**: System deleted any existing `PipelineStageRequiredField` record for `custom_attribute_definition_id: 42` across all stages in the account before creating the record for `pipeline_stage_id`.
- **After**: System does **not** delete requirements on other stages. It creates the requirement record for the specified `pipeline_stage_id`.

#### Responses:
- **`200 OK`**:
  ```json
  {
    "id": 105,
    "account_id": 1,
    "pipeline_stage_id": 2,
    "custom_attribute_definition_id": 42,
    "created_at": "2026-08-17T12:00:00.000Z",
    "updated_at": "2026-08-17T12:00:00.000Z"
  }
  ```
  *(Returned when successfully assigned to this stage, even if already assigned to another stage in the same account).*

- **`422 Unprocessable Entity`**:
  ```json
  {
    "error": "Custom attribute definition is already required in this pipeline stage"
  }
  ```
  *(Returned when attempting to assign the same attribute to the same stage twice).*

---

### 2. Batch Sync Stage Required Fields

- **Route**: `PATCH /api/v1/accounts/:account_id/pipeline_stages/:id`
- **Controller**: `Api::V1::Accounts::PipelineStagesController#update`
- **Request Body**:
  ```json
  {
    "pipeline_stage": {
      "name": "Qualification",
      "required_custom_attribute_definition_ids": [42, 55]
    }
  }
  ```

#### Behavior Changes:
- **Before**: `sync_required_attributes` destroyed records on other stages (`where.not(pipeline_stage_id: stage.id).destroy_all`), effectively stealing the attributes from any other stage that had them configured.
- **After**: `sync_required_attributes` only modifies records associated with `stage.id`. Requirements for attributes `42` and `55` on other stages remain completely intact.

#### Responses:
- **`200 OK`**:
  ```json
  {
    "id": 2,
    "name": "Qualification",
    "position": 2,
    "requires_deal_value": false,
    "total_display_mode": "value_sum",
    "accent_color": null,
    "stale_after_days": null,
    "required_custom_attribute_definitions": [
      {
        "id": 42,
        "attribute_key": "budget_confirmed",
        "attribute_display_name": "Budget Confirmed",
        "attribute_display_type": "checkbox",
        "attribute_values": null
      },
      {
        "id": 55,
        "attribute_key": "decision_maker",
        "attribute_display_name": "Decision Maker",
        "attribute_display_type": "text",
        "attribute_values": null
      }
    ]
  }
  ```

---

### 3. Remove Required Field from a Stage

- **Route**: `DELETE /api/v1/accounts/:account_id/pipeline_stages/:pipeline_stage_id/required_fields/:id`
- **Controller**: `Api::V1::Accounts::PipelineStageRequiredFieldsController#destroy`
- **Parameters**: `id` is the `custom_attribute_definition_id`.

#### Behavior:
- Deletes the association between `pipeline_stage_id` and `custom_attribute_definition_id`.
- Has zero impact on requirement records for the same `custom_attribute_definition_id` on any other stages in the account.

#### Responses:
- **`200 OK`**: (empty body / `head :ok`)
