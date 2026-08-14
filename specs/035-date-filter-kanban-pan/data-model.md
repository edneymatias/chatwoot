# Data Model: Custom Date Attribute Filtering & Kanban Drag-to-Pan Navigation

## Entities & Schemas

### 1. Opportunity Custom Attributes
- **Model**: `Opportunity` (`custom/app/models/opportunity.rb`)
- **Storage**: `custom_attributes` (JSONB column)
- **Key Types**:
  - `date`: Stored as ISO-8601 date string (e.g., `"2026-08-13"` or `"2026-08-13T00:00:00.000Z"`).
  - `text`: Stored as string.
  - `number`: Stored as numeric string or number.
  - `list`: Stored as string or array of strings.
  - `checkbox`: Stored as boolean.

### 2. Opportunity Filter Payload Contract
- **Query Parameter**: `payload` (JSON encoded array of filter objects)
- **Schema per Filter Item**:
  ```json
  {
    "attribute_key": "data_agendamento",
    "filter_operator": "is_greater_than",
    "values": ["2026-08-01"],
    "attribute_model": "customAttributes"
  }
  ```
- **Supported Operators for Date Custom Attributes**:
  | Operator | Description | Backend SQL Evaluation |
  |----------|-------------|------------------------|
  | `equal_to` | Exact date match | `(safe_date_cast) = :val::date` |
  | `not_equal_to` | Not equal to date | `(safe_date_cast) != :val::date OR NOT (custom_attributes ? :key)` |
  | `is_greater_than` | After date (`>`) | `(safe_date_cast) > :val::date` |
  | `is_less_than` | Before date (`<`) | `(safe_date_cast) < :val::date` |
  | `days_before` | X days before today | `(safe_date_cast) = :target_date::date` |
  | `is_present` | Attribute exists and is not null | `custom_attributes ? :key AND custom_attributes->>:key IS NOT NULL` |
  | `is_not_present` | Attribute missing or null | `NOT (custom_attributes ? :key) OR custom_attributes->>:key IS NULL` |

### 3. Kanban Board Pan State (Frontend Transient State)
- **Component**: `KanbanBoard.vue`
- **State Fields**:
  - `isPanning`: Boolean (true while primary mouse button is depressed on board surface).
  - `startX`: Number (initial X position on mousedown relative to container offset).
  - `initialScrollLeft`: Number (container scrollLeft when pan begins).
  - `isDraggingCard`: Boolean (synchronized with card drag start/end to suppress board pan).
