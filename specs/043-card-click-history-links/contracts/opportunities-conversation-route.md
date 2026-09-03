# Contract: `opportunities_conversation` route

Existing named route (`app/javascript/dashboard/routes/dashboard/dashboard.routes.js`), child of
`opportunities_index`, rendering `OpportunityConversationDrawer.vue`.

## Before (current)

- Path: `conversations/:conversationId` — `conversationId` is required; navigating without it is
  not a supported state (callers only ever push it when `active_conversation_id` is present).
- Drawer default tab: always `'conversation'`.

## After (this feature)

- Path: `conversations/:conversationId?` — `conversationId` becomes optional.
- Navigating with `query.opportunityId` and no `conversationId` is now a first-class, supported
  state: the drawer opens on the `'activity'` (history) tab instead of `'conversation'`.
- Navigating with `conversationId` present (whether from the initial card click or a history-panel
  link) still opens on the `'conversation'` tab, unchanged.
- `query.opportunityId` remains the sole source of opportunity context in both cases — a history
  link push explicitly carries it forward (named pushes don't inherit the current query
  automatically), so it must never be dropped (FR-007).

## Consumer contract

- `KanbanCard.vue` / list-view `Index.vue` click handlers: always push `opportunities_conversation`
  with `query: { opportunityId }`, including `params.conversationId` only when
  `active_conversation_id` is present (FR-001, FR-002).
- `OpportunityActivityLog.vue` link clicks: push `opportunities_conversation` with
  `params: { conversationId: <that entry's display id> }` and
  `query: { opportunityId: route.query.opportunityId }` (FR-006, FR-007).
- `useConversationDrawer.js`'s watcher on `route.params.conversationId` becomes a no-op when the
  param is absent (must not attempt to load `undefined`).
