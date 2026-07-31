# Phase 1 Data Model: Conversation Drawer on Card Click

This feature introduces no new persisted data and no schema changes (Assumptions in spec.md: no
backend/API changes). The relevant entities are existing ones, referenced read-only, plus one
new client-side UI state model for the drawer itself.

## Existing Entities (unmodified)

### Opportunity
- Source: existing `opportunities` Vuex store module (`getters['opportunities/cardById']`).
- Relevant attribute: `origin_conversation_id` (nullable) — determines whether a `KanbanCard.vue`
  is clickable (FR-002) and which conversation id the drawer route/composable targets. Immutable
  per Phase 1's prior constraint (referenced in the source doc's Out of Scope); this feature only
  reads it.

### Conversation
- Source: existing `conversations` Vuex store module, fetched via the existing `getConversation`
  action (`ConversationApi.show`) and rendered via `ConversationBox.vue`/`ConversationSidebar.vue`.
  No new fields or fetch logic; the drawer surfaces the same data the standalone conversation view
  already does.

## New Client-Side State: Drawer Load State

Owned by `useConversationDrawer.js`, not persisted, reset on every mount/unmount cycle.

| State | Meaning | Drives |
|-------|---------|--------|
| `loading` | Conversation not yet present in `chatList`; `getConversation` dispatched but not resolved into an active chat yet | `ConversationBox.vue`'s own internal spinner (inherited, no new UI — see research.md) |
| `ready` | Conversation is in `chatList` and `setActiveChat` has completed | `OpportunityConversationDrawer.vue` renders `ConversationBox` + `ConversationSidebar` |
| `error` | `getConversation` fetch failed (not found / no permission) | `OpportunityConversationDrawer.vue` renders the inline error state (message + close action) per FR-008 |

### Transitions

```
mount ──▶ loading ──(fetch succeeds, chat becomes active)──▶ ready
              │
              └──(fetch fails: 404/403/etc.)──▶ error

ready ──▶ (unmount / route leave) ──▶ clearSelectedState dispatched, component torn down
error ──▶ (close action / route leave) ──▶ component torn down (no active-chat state to clear,
                                            since setActiveChat never ran)
```

- Entry point: `loading` on mount, driven by whether `conversationId` is already present in
  `chatList` (mirrors `ConversationView.vue`'s `fetchConversationIfUnavailable` check).
- `loading → ready`: once the conversation is confirmed present in `chatList` (via the existing
  `chatList.length`/store watch pattern) and `setActiveChat` + `markMessagesRead` have both been
  dispatched (FR-006).
- `loading → error`: the fetch action's failure path (`getConversation` currently swallows errors
  internally per research.md — the composable must surface a failure signal itself, e.g. by
  checking whether the conversation is present in `chatList` after the fetch settles, rather than
  relying on a thrown exception).
- `ready → (unmount)`: `clearSelectedState` dispatched unconditionally on unmount/route-leave
  (FR-007), matching `ConversationView.vue`'s `beforeRouteLeave` behavior.
- Re-clicking a different card while the drawer is open (Edge Case in spec.md) re-triggers this
  same state machine from `loading` for the new `conversationId`, since Vue Router will re-invoke
  the composable's watch/setup logic when the route param changes.
