# API Contracts

## `GET /api/v1/accounts/{account_id}/opportunities`

This endpoint fetches the list of opportunities. This feature adds several new optional query parameters to support filtering and sorting.

### New Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `q` | String | A search term used to partially match (case-insensitive) the opportunity's `title` or its associated contact's `name`. |
| `assignee_id` | Integer | Filters opportunities to only those assigned to the specified user ID. |
| `status` | String | Filters opportunities by their status (e.g., `open`, `won`, `lost`). |
| `custom_attributes` | Hash/Object | Filters by custom attribute keys and values. Format in query string is typically `custom_attributes[key]=value`. Multiple keys are ANDed together. |
| `sort_by` | String | Defines the sort order. Supported values: `value_desc`, `value_asc`, `last_activity`. If omitted or unrecognized, defaults to `created_at` descending. |

**Existing Parameters (Unchanged):**
*   `page`: For pagination.
*   `pipeline_stage_id`: Filters by stage.
*   `contact_id`: Filters by contact.

### Response

The response schema remains unchanged, returning a paginated list of opportunity objects.
