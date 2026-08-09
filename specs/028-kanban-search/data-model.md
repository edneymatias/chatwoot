# Data Model

No new database tables or columns are introduced in this feature. However, it relies heavily on the structure of existing tables to perform filtering and sorting.

## Entities

### Opportunity
Represents a deal or prospect in the system.
*   **Key Fields**:
    *   `title` (String): Matched partially against the `q` parameter.
    *   `status` (Enum/String): Filtered via the `status` parameter.
    *   `assignee_id` (Integer): Filtered via the `assignee_id` parameter.
    *   `value` (Decimal/Float): Used for sorting when `sort_by` is `value_desc` or `value_asc`.
    *   `updated_at` (Timestamp): Used for sorting when `sort_by` is `last_activity`.
    *   `created_at` (Timestamp): The default sort order.
    *   `contact_id` (Integer): Foreign key to the `Contact` model.
    *   `custom_attributes` (JSONB): A flexible hash. Queried for custom attribute filters.

### Contact
The associated person or organization for the opportunity.
*   **Key Fields**:
    *   `name` (String): Matched partially against the `q` parameter when searching.

### CustomAttributeDefinition
Defines the schema for custom attributes applied to opportunities.
*   **Key Fields**:
    *   `attribute_model` (String): Must be `opportunity_attribute` for this feature.
    *   `attribute_display_type` (String): Filter dropdowns only apply to `list` types.
    *   `attribute_values` (Array/JSON): The available options for the filter dropdown.
