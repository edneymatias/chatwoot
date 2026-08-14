# Research: Custom Date Attribute Filtering & Kanban Drag-to-Pan Navigation

## Technical Decisions & Findings

### Decision 1: Custom Date Attribute SQL Comparison in PostgreSQL
- **Decision**: In `OpportunitiesController#apply_value_filter` and related filter helpers, evaluate date comparisons using safe PostgreSQL date casting with regex validation:
  ```sql
  (CASE WHEN custom_attributes->>:key ~ '^\d{4}-\d{2}-\d{2}' THEN (custom_attributes->>:key)::date ELSE NULL END) > :value::date
  ```
- **Rationale**:
  - Direct string comparison in JSONB (`custom_attributes->>:key > '2026-08-01'`) fails when formatting varies or when operators are collapsed into `IN (:values)`.
  - Direct PostgreSQL `::date` casting without regex validation throws fatal SQL exceptions (`PG::InvalidDatetimeFormat`) if any record has empty string `""` or invalid text.
  - Safe case-expression casting ensures 100% query safety and accurate chronological ordering.
- **Alternatives Considered**:
  - *Ruby-level filtering in memory*: Rejected because pagination, counting, aggregate totals, and stage card loads would be broken and non-scalable.
  - *JSONB path operators (`@>` / `jsonb_path_query`)*: More complex to parameterize safely across relational comparison operators than standard SQL `CASE/::date`.

### Decision 2: Date Operators Definition in Frontend Filter Composable
- **Decision**: Update `useOperators` in `operators.js` to define a dedicated `customDateOperators` set containing:
  - `equal_to` (`=`)
  - `not_equal_to` (`!=`)
  - `is_greater_than` (`>`)
  - `is_less_than` (`<`)
  - `days_before` (`📅 É X dias antes`)
  - `is_present` (`Está presente`)
  - `is_not_present` (`Não está presente`)
- **Rationale**:
  - Eliminates inappropriate string operators (contains, does not contain) from date attributes.
  - Provides the full set of intuitive date comparison capabilities requested by users.
- **Alternatives Considered**:
  - *Using `comparisonOperators` (which was numeric)*: Missing `days_before` and not tailored for date UX.

### Decision 3: Kanban Board Drag-to-Pan Event Delegation & Card Isolation
- **Decision**: Attach mouse and touch pan event listeners on the board container (`KanbanBoard.vue`), ignoring events originating from interactive elements (`button`, `a`, `input`, `select`, `.kanban-card`, or card draggable handles):
  - Track `startX`, `scrollLeft`, and `hasDragged` state.
  - Apply immediate stop on mouseup without artificial momentum/inertia per user decision.
  - Prevent click event hijacking on zero-movement clicks.
- **Rationale**:
  - Native, lightweight, framework-aligned approach using Vue 3 Composition API refs.
  - Completely preserves existing `vuedraggable` card moving and stage transition requirements without event conflicts.
- **Alternatives Considered**:
  - *Third-party drag-scroll libraries*: Rejected to avoid adding external dependencies and bundle bloat when standard Vue DOM event handling takes ~30 clean lines.

### Decision 4: Hiding Native Horizontal Scrollbar
- **Decision**: Apply Tailwind utility classes `[scrollbar-width:none] [-ms-overflow-style:none] [&::-webkit-scrollbar]:hidden` to the board container.
- **Rationale**:
  - Cross-browser compatible (Firefox, Safari, Chromium, Edge).
  - Keeps scroll container fully scrollable programmatically and via pan gestures while rendering 0px visual bar.
  - 100% Tailwind compliant without custom/scoped CSS per repository constitution.
