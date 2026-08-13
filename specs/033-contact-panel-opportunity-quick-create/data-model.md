# Phase 1 Data Model: Contact Panel Opportunity Quick Create

No new entities, fields, or backend data model changes. This feature only reads/writes existing
`Opportunity` records through the existing `opportunities` Vuex store module and existing API. It
adds one client-side store mutation to keep already-loaded state consistent after creation.

## Existing Entities (unchanged, referenced only)

### Opportunity

Sourced from the existing `opportunities` Vuex module (`store/modules/opportunities/`) and backend
`Opportunity` model (`custom/app/models/opportunity.rb`), unchanged by this feature.

| Field | Type | Notes (relevant to this feature) |
|---|---|---|
| `id` | number | Primary identifier |
| `contact_id` | number | Owning contact; drives `idsByContact` keying |
| `origin_conversation_id` | number \| null | Immutable once set (model-level validation, unchanged); this feature reads it to determine the current-conversation match and to disable the "Add opportunity" action |
| `pipeline_stage_id` | number | Used by existing `PREPEND_ID_TO_STAGE`; unaffected |
| `title`, `value`, `assignee_id`, `custom_attributes`, `status` | various | Unaffected; passed through by the existing create flow |

**Constraint reaffirmed (not re-implemented)**: at most one `Opportunity` per
`origin_conversation_id` (unique index + model immutability validation). This feature's UI changes
(disabled action, locked contact) exist to *respect*, not *enforce*, this constraint — enforcement
remains entirely in the existing backend.

### Contact (referenced only)

`{ id, name, email }` shape, as already returned by `ContactAPI.search` and already used to
populate `selectedContact` in `OpportunityCreateModal.vue`. This feature passes the same shape into
the modal proactively via the new `initialContact` prop instead of requiring a search.

## Store State Changes

### `state.idsByContact` (existing, `opportunities` module)

No shape change (`{ [contactId]: number[] }`). This feature adds one new mutation that writes to
it in an additional place (opportunity creation), it does not change what the state itself
represents.

### New mutation: `PREPEND_ID_TO_CONTACT`

```
PREPEND_ID_TO_CONTACT(state, { contactId, opportunityId })
```

- No-op if `state.idsByContact[contactId]` is `undefined` (that contact's opportunities were never
  fetched into any currently-mounted view — avoids creating a partial/wrong list).
- Otherwise prepends `opportunityId` to `state.idsByContact[contactId]` if not already present,
  mirroring `PREPEND_ID_TO_STAGE`'s existing dedupe-and-prepend shape.

Committed from the `opportunities/create` action using the newly created opportunity's
`contact_id`/`id`, alongside the existing `ADD_OPPORTUNITY` and `PREPEND_ID_TO_STAGE` commits.

## Component-Local State (not persisted, no store changes)

- `ContactOpportunities.vue`: a boolean/id ref tracking whether the new create-modal is open
  (mirrors the existing `backfillOpportunityId`/`isBackfillModalOpen` pattern in the same file),
  reset to closed whenever `currentChat.value.id` changes (FR-010).
- `OpportunityCreateModal.vue`: `selectedContact` is initialized from the new `initialContact` prop
  when present; no new reactive state beyond the existing fields.
