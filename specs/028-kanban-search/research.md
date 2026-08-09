# Phase 0: Outline & Research

## Architecture Decisions

### 1. Unified Controller Filtering
- **Decision**: Extend `Api::V1::Accounts::OpportunitiesController#index` to handle filtering logic via `q`, `assignee_id`, `status`, `custom_attributes`, and `sort_by` parameters.
- **Rationale**: It follows the existing `contacts` module pattern, ensuring consistent API design and avoiding separate endpoints for filtered vs. unfiltered data.
- **Alternatives considered**: Creating a new search endpoint (rejected to maintain API consistency and reduce controller sprawl).

### 2. Local Component State for Filters
- **Decision**: Maintain filter state locally in `Index.vue` or `OpportunitiesViewBar.vue` rather than in Vuex.
- **Rationale**: Mirrors established codebase conventions (e.g., `ContactAPI`), allowing automatic "reset on navigation" without requiring explicit Vuex cleanup actions.
- **Alternatives considered**: Storing in Vuex or URL parameters (rejected as URL persistence/saved filters were explicitly out of scope).

### 3. SQL-level Search Match
- **Decision**: Implement case-insensitive partial match via `left_joins(:contact)` and `ILIKE` using `sanitize_sql_like` for the `q` parameter.
- **Rationale**: Ensures robust search capabilities spanning both the opportunity title and associated contact name efficiently within a single query, without requiring a separate full-text search engine.
- **Alternatives considered**: Client-side filtering (rejected due to pagination limits).

### 4. Custom Attributes Filtering
- **Decision**: Filter by custom attributes using `where("custom_attributes ->> ? = ?", key, value)`.
- **Rationale**: Standard Chatwoot approach for querying PostgreSQL JSONB custom attribute columns.
