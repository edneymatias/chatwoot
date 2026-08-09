# Phase 35: Search (and Sort/Filter) for Opportunities

**Depends on**: Phase 8 (List View), whose `OpportunitiesViewBar.vue` is extended by this phase
and whose `fetchAll`/`fetchForStage` actions gain new query parameters; existing Kanban board
(`KanbanBoard.vue`, `KanbanColumn.vue`) for the per-stage fetch pattern that also needs to accept
filters.

## Context

Today there is no way to narrow down opportunities beyond scrolling Kanban columns or paging
through the List view — the backend `Api::V1::Accounts::OpportunitiesController#index` only
supports `pipeline_stage_id`/`contact_id` filters and a fixed `created_at desc` order. This phase
adds a unified search/filter/sort bar (the same `OpportunitiesViewBar.vue` shared by both views,
per its original design intent) that operates consistently across Kanban and List, with a few
deliberate differences between the two views spelled out below.

This phase follows the `contacts` module's existing pattern for filtered lists
(`ContactAPI.filter(page, sortAttr, queryPayload)`, `ContactAPI.search(search, page, sortAttr,
label)`): filters/sort are passed as arguments to fetch actions and owned by local component
state, not persisted in Vuex module state. This keeps behavior consistent with an established
codebase convention and means "reset on navigation" (see FR-011) requires no explicit cleanup —
the state simply disappears when the owning component unmounts.

## Backend — `OpportunitiesController#index`

- **FR-001**: Add an optional `q` param that matches opportunity `title` or the associated
  contact's `name` (case-insensitive, partial match). Implemented via `left_joins(:contact)` and
  an `ILIKE` match on both columns, using `sanitize_sql_like` on the input.
- **FR-002**: Add an optional `assignee_id` param, filtering `where(assignee_id: params[:assignee_id])`.
- **FR-003**: Add an optional `status` param, filtering `where(status: params[:status])`.
- **FR-004**: Add an optional `custom_attributes` param (a hash of `attribute_key => value`
  pairs) for filtering by opportunity custom attributes with `attribute_display_type: "list"`.
  Each pair is applied as `where("custom_attributes ->> ? = ?", key, value)`, ANDed together when
  multiple keys are present.
- **FR-005**: Add an optional `sort_by` param accepting `value_desc`, `value_asc`, or
  `last_activity`; any other value (including absent) keeps the current default
  `order(created_at: :desc)`. `value_desc`/`value_asc` map to `order(value: :desc/:asc)`.
  `last_activity` maps to `order(updated_at: :desc)` — no join needed, since
  `record_subsequent_stage_change` already causes a stage change to touch the opportunity's own
  `updated_at`.
- **FR-006**: The existing `pipeline_stage_id` and `contact_id` params are unchanged and continue
  to combine with the new params (all filters are ANDed).
- **FR-007**: Extract the filtering logic (FR-001 through FR-004) into private controller helper
  methods rather than one long `index` method, to stay under the complexity/length guidelines
  established in Phase 34.

## Frontend — Filter bar UI

- **FR-008**: Extend `OpportunitiesViewBar.vue` with: a search input (title/contact, FR-001), an
  assignee dropdown (FR-002), a status dropdown (FR-003), a stage dropdown (FR-006, **List view
  only** — hidden when `viewMode === 'kanban'`, since a stage filter is redundant with Kanban's
  per-stage columns), one single-select dropdown per opportunity custom attribute definition where
  `attribute_display_type === 'list'` (FR-004, sourced from the existing `attributes` Vuex module,
  filtered client-side for `attribute_model === 'opportunity_attribute'` and
  `attribute_display_type === 'list'`; each dropdown's options come from that definition's own
  `attribute_values`), and a sort dropdown (FR-005, **List view only**) offering
  "Value (high to low)", "Value (low to high)", "Last activity", defaulting to the existing
  created-at-desc order.
- **FR-009**: All of the above (search, assignee, status, custom attribute filters) apply to
  **both** Kanban and List views. In Kanban, a non-matching card is simply not rendered within its
  existing column — columns themselves are never hidden and no separate "filtered" board state is
  introduced.
- **FR-010**: Filter/sort state is owned locally by `OpportunitiesViewBar.vue` (or `Index.vue`, an
  implementation detail) as reactive component state — not persisted to Vuex, not written to
  `localStorage` or the URL. This mirrors `viewMode`'s independence: `viewMode` persists via
  `localStorage`, filters do not.
- **FR-011**: Filter/sort state resets automatically when `Index.vue` unmounts (e.g. navigating
  away from Opportunities), since it is local component state with no explicit persistence — no
  reset action needs to be dispatched.

## Frontend — Data layer

- **FR-012**: `opportunities/fetchAll` and `opportunities/fetchForStage` accept an optional
  filters argument (merged into the existing action payload, e.g.
  `fetchAll({ page, filters })`), which is serialized into the API query string alongside the
  existing `page`/`pipeline_stage_id` params. Filters is a plain object matching the backend
  params from FR-001 through FR-005 (`q`, `assigneeId`, `status`, `customAttributes`, `sortBy`
  for `fetchAll`; `q`, `assigneeId`, `status`, `customAttributes` only for `fetchForStage`, since
  sort is List-only per FR-008).
- **FR-013**: `Index.vue` passes the current filters (and sort, for List) down to
  `KanbanBoard.vue` (→ `KanbanColumn.vue`) and `OpportunityListView.vue` as a prop. Each view
  `watch`es the prop: on change, it resets its own local pagination state (`allIds`/`pagination.all`
  for List; the affected stage's `cardsForStage` cache for Kanban) and re-fetches page 1 with the
  new filters.
- **FR-014**: `KanbanColumn.vue` gains the filters prop (threaded through `KanbanBoard.vue`) and
  includes it in its `fetchForStage` dispatch, alongside its existing `stage.id`/page arguments.

## Out of scope

- Value range filtering — explicitly excluded per this phase's brainstorm.
- Sorting within Kanban columns — sort is List-view only; Kanban's per-column card order is
  unaffected by this phase.
- Persisting filter/sort state (URL params, `localStorage`) — resets on navigation by design
  (FR-010, FR-011).
- Saved filters / custom views for opportunities (unlike the existing `customViews` module for
  conversations/contacts) — not requested, not part of this phase.
- Bulk actions on filtered/searched results — separate preview (Phase 37, this cycle).
