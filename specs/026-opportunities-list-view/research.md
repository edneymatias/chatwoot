# Research: Kanban List View

## Decision: Frontend-Only Implementation

**Rationale**: The backend `Api::V1::Accounts::OpportunitiesController#index` already supports standard paginated listing when no `pipeline_stage_id` is provided. Therefore, the list view can be implemented entirely in the frontend by creating a new `fetchAll` Vuex action that omits the stage filter, and new Vue components to render the result.
**Alternatives considered**: Building a new backend endpoint. Rejected because the existing endpoint is sufficient, avoiding unnecessary backend duplication.

## Decision: Separate State for List View in Vuex

**Rationale**: The Kanban board maintains state per stage (`state.cards[stageId]`). For the flat list, we need a separate ordered list of all IDs (`state.allIds`) and separate pagination (`state.pagination.all`). The actual opportunity objects will still be merged into the shared `state.byId` map so that updates in one view (or real-time events) are immediately reflected in both views.
**Alternatives considered**: Reusing the Kanban state. Rejected because Kanban state is heavily partitioned by stage, making it impossible to render a globally sorted list without flattening and sorting on the client, which breaks pagination.

## Decision: Read-Only List View (for Phase 1)

**Rationale**: Drag-and-drop between stages is intrinsic to the Kanban layout. In a list view, changing stage/status would require inline dropdowns or bulk actions. To keep the initial release small and focused on scanning, the list view will be read-only, matching the original specification.
**Alternatives considered**: Adding inline stage dropdowns. Rejected to minimize the scope of the initial phase and follow the "Smallest Production-Ready Change" principle.

## Decision: Store View Preference in LocalStorage

**Rationale**: Users will want their preferred view (Kanban or List) to persist across sessions and page reloads. `localStorage` with a key of `chatwoot_opportunities_view_mode` provides simple, client-side persistence without requiring a backend schema change for user preferences.
**Alternatives considered**: Storing the preference in the database. Rejected because it violates "Smallest Production-Ready Change" and requires backend migrations for a purely client-side layout toggle.
