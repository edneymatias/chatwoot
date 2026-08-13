# Phase 1 Contracts: Component Interfaces

This feature adds no backend endpoints (see `plan.md` Technical Context). Its only "interfaces" are
the Vue component props/emits it adds or extends, and the Vuex mutation payload it introduces.
Documented here so all call sites (existing and new) agree on the same contract.

## `OpportunityCreateModal.vue`

### New prop: `initialContact`

```js
initialContact: {
  type: Object, // { id: Number, name: String, email: String }
  default: null,
}
```

**Contract**:
- When **present** (an object): `selectedContact` is initialized to it on mount; the contact
  section renders as a read-only chip with no "Clear" button and no search input; the contact
  cannot change for the lifetime of that modal instance.
- When **absent** (`null`, the default): behavior is exactly as it is today — search-and-select,
  with a "Clear" button once a contact is picked. This is a strict backward-compatible default; no
  existing call site (Kanban's per-column "+", the List view's "add opportunity" button) passes
  this prop and both continue to behave unchanged.

### Existing prop (unchanged): `originConversationId`

Already supported (`props.originConversationId`, passed straight through to
`opportunities/create`). This feature's new call site (`ContactOpportunities.vue`) passes the
current conversation's id here — no change to the prop itself.

## `ContactOpportunityCard.vue`

### New prop: `isCurrentConversation`

```js
isCurrentConversation: {
  type: Boolean,
  default: false,
}
```

**Contract**:
- When `true`, the card's bottom divider border uses the existing accent color token
  `border-n-brand` instead of the default `border-n-slate-3`.
- When `false` (default), rendering is unchanged from today. Only `ContactOpportunities.vue` ever
  passes `true`, and only for the single card (if any) matching the current conversation.
- No other visual or behavioral change; the existing `click` emit and all other props are
  unaffected.

## `store/modules/opportunities` — `PREPEND_ID_TO_CONTACT` mutation

```js
commit('PREPEND_ID_TO_CONTACT', { contactId, opportunityId });
```

**Contract**:
- Input: `contactId` and `opportunityId` of a just-created (or otherwise newly-known) opportunity.
- Effect: if `state.idsByContact[contactId]` exists (i.e. that contact's opportunities have already
  been fetched by some mounted view), prepend `opportunityId` to it (deduped, mirroring
  `PREPEND_ID_TO_STAGE`). If it does not exist, no-op — never fabricates a partial list for a
  contact nobody has loaded.
- Callers: the `opportunities/create` action commits this unconditionally alongside its existing
  `ADD_OPPORTUNITY`/`PREPEND_ID_TO_STAGE` commits; the no-op guard means it is always safe to call
  regardless of which view triggered creation (Contact Panel, Kanban, or List view).
