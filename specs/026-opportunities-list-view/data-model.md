# Data Model: Kanban List View

This feature requires modifying the frontend Vuex store for the `opportunities` module to support a global, cross-stage list view while maintaining the existing per-stage state for the Kanban board. 

The backend schema and data model remain unchanged.

## Vuex Store Modifications (`opportunities` module)

### State Additions

The `state` object will be extended with the following properties to track the flat list independently of the Kanban stages:

```javascript
{
  allIds: [], // Array of opportunity IDs fetched without stage filter
  pagination: {
    // ... existing pagination state ...
    all: {
      page: 1,
      hasMore: true
    }
  },
  uiFlags: {
    // ... existing uiFlags ...
    isFetchingAll: false
  }
}
```

*Note: The actual `Opportunity` objects will continue to be stored in the shared `state.byId` map. This ensures that any real-time updates (e.g. from WebSockets) or edits made in other views correctly reflect in both the List and Kanban views simultaneously.*

### Getter Additions

- `allCards(state)`: Maps `state.allIds` to the actual objects in `state.byId`.
- `hasMoreAll(state)`: Returns `state.pagination.all.hasMore`.
- `isFetchingAll(state)`: Returns `state.uiFlags.isFetchingAll`.

### Mutation Additions

- `SET_IS_FETCHING_ALL(state, status)`: Sets the fetching flag.
- `SET_ALL_CARDS(state, data)`: Pushes fetched IDs into `state.allIds`, updates `state.byId` with the objects, and updates `state.pagination.all.page` and `hasMore`.

### Action Additions

- `fetchAll({ commit }, { page })`: Makes a GET request to the existing `Api::V1::Accounts::OpportunitiesController#index` without the `pipeline_stage_id` filter. Determines `hasMore` by checking if the payload length is >= 10.
