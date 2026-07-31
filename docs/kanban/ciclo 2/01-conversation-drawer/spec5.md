# Phase 5: Conversation Drawer on Card Click

**Depends on**: Phase 3 (frontend board), Phase 4 (realtime/menu wiring)
**Feeds**: nothing yet — first phase of ciclo 2

## Context

Today, clicking an Opportunity card opens `OpportunityDetailView.vue`, a side
panel showing opportunity metadata (status, contact, assignee) and, if
`origin_conversation_id` is present, a `router-link` that navigates *away*
from the board to `inbox_conversation`.

This phase replaces that behavior: clicking a card opens the full native
conversation experience — message thread (`ConversationBox`) and native
contact/conversation sidebar (`ContactPanel`) — in a drawer that slides in
from the right, on top of the board, with a close button that returns to the
board. The agent can do everything they could in the normal conversation
view (reply, resolve, assign, etc.) without leaving the Kanban context.
`OpportunityDetailView.vue` is removed; opportunity status/actions remain
accessible only via the card and board (existing hover actions).

Cards without an `origin_conversation_id` are not clickable and are
rendered with reduced opacity as a visual cue. Building a "link a
conversation later" feature is explicitly out of scope (see Out of Scope).

## Functional Requirements

**FR-001**: The drawer MUST be implemented as a Vue Router nested (child)
route under the existing `opportunities_index` route, e.g. path
`opportunities/conversations/:conversationId`, name
`opportunities_conversation`. This is an addition to
`dashboard.routes.js`, following the same anchor-based touch pattern
already used in Phase 4's `bin/sync-custom-module-hooks`; the script's
manifest MUST be extended to cover this new anchor.

**FR-002**: Clicking a card with a present `origin_conversation_id` MUST
navigate to `opportunities_conversation` with `conversationId` set to that
value (`router.push`), instead of setting local component state
(`selectedOpportunityId`). Clicking a card without `origin_conversation_id`
MUST do nothing (no navigation, no modal).

**FR-003**: `KanbanCard.vue` MUST render cards without
`origin_conversation_id` with reduced opacity (e.g. `opacity-60`) and
without the `cursor-pointer`/hover-click affordance, to visually
communicate they have no linked conversation. No "link a conversation"
action is added (see Out of Scope).

**FR-004**: A new component `OpportunityConversationDrawer.vue` MUST be
created (in the Opportunities module's own directory) that renders, inside
a right-side sliding panel: `ConversationBox` and `ContactPanel` only — no
`ChatList`. It MUST NOT modify `ConversationView.vue`; it is an independent
composition of the same exported components `ConversationView.vue` already
uses, reused as-is with zero edits to either component.

**FR-005**: A new composable `useConversationDrawer.js` MUST encapsulate all
interaction with the core "active chat" Vuex state
(`setActiveChat`/`clearSelectedState` or equivalent actions already used by
`ConversationView.vue`), plus fetching the conversation by id if not
already loaded, plus triggering `markMessagesRead` on open. This composable
is the single point of coupling to upstream's internal chat-state
management — future upstream changes to that internal state should only
require updating this one file.

**FR-006**: On mount, `useConversationDrawer.js` MUST: (a) check if the
conversation is already present in the Vuex store; (b) if not, fetch it via
the existing conversation-fetch action already used elsewhere in the
dashboard; (c) call `setActiveChat` (or equivalent) once loaded; (d) trigger
`markMessagesRead`.

**FR-007**: On unmount / route leave, `useConversationDrawer.js` MUST clear
the active chat state (`clearSelectedState` or equivalent), so the global
chat state does not leak into other parts of the dashboard after the
drawer closes.

**FR-008**: If the conversation fetch fails (not found, no permission,
etc.), the drawer MUST render an inline error state (message + close
button) instead of `ConversationBox`/`ContactPanel`. No toast is used for
this case, since the drawer must already be open (and thus visible) before
the fetch outcome is known.

**FR-009**: The close button (and browser back navigation) MUST return to
the `opportunities_index` route, unmounting the drawer, without reloading
or otherwise affecting the Kanban board's own state
(`idsByStage`/`byId`/etc.).

**FR-010**: `OpportunityDetailView.vue` MUST be deleted. Any opportunity
status change actions (mark won/lost/reopen) remain available only via
`KanbanCard.vue`'s existing hover actions.

## Out of Scope (this phase)

- Any "link a conversation to an existing opportunity" flow — explicitly
  rejected; would require reverting Phase 1's FR-008 immutability
  constraint on `origin_conversation_id`, with no proven use case yet.
- Injecting an "Opportunities" section into the native `ContactPanel.vue`
  sidebar (parked as a future idea — see
  `docs/kanban/ciclo 2/05-contact-panel-opportunities-section/spec9.md`).
- Any backend/API changes — this phase reuses existing conversation-fetch
  and chat-state actions as-is.
- Toast-based error handling for conversation load failures (see FR-008).

## Completion Criteria

Verify inside the `vite` container (`docker compose exec vite <command>`).

1. Clicking a card with `origin_conversation_id` opens the drawer at
   `opportunities/conversations/:conversationId`, showing the real
   conversation thread and contact sidebar, fully interactive (reply,
   resolve, assign, etc.).
2. Clicking a card without `origin_conversation_id` does nothing; the card
   renders with reduced opacity and no pointer cursor.
3. Closing the drawer (button or back navigation) returns to the board
   with no residual "active chat" state and no change to board data.
4. A conversation id that fails to load (403/404) shows the inline error
   state, not a blank drawer or a toast.
5. `OpportunityDetailView.vue` no longer exists in the codebase; no
   remaining references to it.
6. `pnpm eslint` and `pnpm test` pass for the touched/added files.
