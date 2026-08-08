# Phase 8: List View for the Kanban Board

**Depends on**: Phase 24 (Opportunity Assignment Rules) for `assignee` data on opportunities;
existing Kanban board (`KanbanBoard.vue`, `KanbanColumn.vue`, `KanbanCard.vue`) and the
`opportunities` Vuex module for the data model and per-stage fetch pattern this phase extends.

## Context

The Kanban board today only renders opportunities grouped by stage, fetched one stage at a
time (`opportunities/fetchForStage`). There is no flat, cross-stage listing of opportunities in
the frontend, even though the backend `Api::V1::Accounts::OpportunitiesController#index` already
supports plain paginated listing (`order(created_at: :desc)`, `.page(params[:page]).per(10)`)
when no `pipeline_stage_id` filter is passed — so this phase is almost entirely frontend work.

This phase adds a dense, row-based alternative to the Kanban board for users who prefer scanning
a table over drag-and-drop lanes, plus a small toggle bar shared by both views that also surfaces
pipeline-wide totals (lead count and value) that previously only existed per-column.

## Frontend — View toggle bar

- **FR-001**: Add `OpportunitiesViewBar.vue`, rendered at the top of `KanbanBoard.vue` above the
  board content (list and Kanban both render below this bar; no new route or wrapper component).
- **FR-002**: The bar shows two icon-only toggle buttons (list icon, Kanban icon) that switch a
  local `viewMode` ref between `'kanban'` and `'list'`. The active mode is highlighted.
- **FR-003**: `viewMode` is persisted to `localStorage` under key
  `chatwoot_opportunities_view_mode` and restored on mount, so the choice survives reloads and
  navigation away/back.
- **FR-004**: The bar displays a total lead count and total opportunity value, computed
  client-side by summing `open_count` and `open_value_sum` across all stages already present in
  `pipelineStages` state (the same aggregates `KanbanBoard.vue` fetches on mount via
  `pipelineStages/fetchAggregates`). No new backend endpoint is introduced. Value formatting
  reuses `getCurrencyConfig`/`Intl.NumberFormat`, matching `KanbanColumn.vue`'s existing
  `displayTotal`.
- **FR-005**: The bar has a right-aligned "add opportunity" button, rendered in a disabled state
  with a tooltip (e.g. "Coming soon"). It is not wired to `OpportunityCreateModal` in this phase —
  connecting it is left to the Manual Opportunity Creation phase (see preview stub in this cycle),
  which may change what "add opportunity" means as an entry point.

## Frontend — List view

- **FR-006**: Add `OpportunityListView.vue`, rendered instead of the Kanban columns when
  `viewMode === 'list'`. Add `OpportunityListRow.vue` for individual rows.
- **FR-007**: Each row shows: title, contact (avatar + name), assignee, stage name, value
  (currency-formatted), status badge (open/won/lost, reusing `statusBadgeClass` conventions from
  `useOpportunityCardFields`), and the last-activity timestamp/stale indicator — the same fields
  `KanbanCard.vue` already surfaces, just laid out as table columns instead of a card.
  Opportunities of any status (`open`, `won`, `lost`) are included, matching what the Kanban board
  already shows per column.
- **FR-008**: Clicking a row with `origin_conversation_id` set opens the same conversation drawer
  used by `KanbanCard.vue`'s `handleCardClick` (`opportunities_conversation` route). Rows without
  an origin conversation are not clickable, same as today's cards.
- **FR-009**: The list is read-only with respect to stage and status — no drag, no inline stage
  dropdown, no quick-action buttons. Changing an opportunity's stage or status still requires the
  Kanban board or another future entry point (see Out of scope).
- **FR-010**: Rows are fetched and appended via `IntersectionObserver`-driven infinite scroll,
  reusing the same pattern `KanbanColumn.vue` uses for per-stage pagination.

## Frontend — Data layer (`opportunities` Vuex module)

- **FR-011**: Add a `fetchAll({ page })` action that calls the existing `opportunities` API with
  no `pipeline_stage_id` filter, paginated the same way `fetchForStage` is (`hasMore` derived from
  `payload.length >= 10`).
- **FR-012**: Add flat state independent of the per-stage caches: `state.allIds` (ordered list of
  opportunity ids from the flat fetch) and `state.pagination.all` (`{ page, hasMore }`), plus a
  `uiFlags.isFetchingAll` flag. Fetched opportunities are still merged into the existing shared
  `state.byId` map, so a card open in both the Kanban board and the list view stays in sync.
- **FR-013**: Add getters `allCards` (maps `allIds` to `byId`), `hasMoreAll`, `isFetchingAll`,
  mirroring the existing per-stage getters (`cardsForStage`, `hasMoreForStage`,
  `isFetchingForStage`).

## Out of scope

- Sorting and filtering beyond the default `created_at desc` order — deferred to the Search
  preview (this cycle), which will own query/filter/sort together as one cohesive feature rather
  than splitting sort into its own item.
- Changing an opportunity's stage or status directly from the list (drag or per-row dropdown) —
  the list is read-only for v1; revisit once usage patterns from this phase are observed.
- Wiring the "add opportunity" button in the view bar — deferred to the Manual Opportunity
  Creation preview.
- Bulk selection/actions from the list — separate preview (this cycle).
- A dedicated route or URL for the list view — it is a client-side toggle on the existing
  `opportunities_index` route, not a new route.
