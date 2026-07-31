# Phase 0 Research: Conversation Drawer on Card Click

No `NEEDS CLARIFICATION` markers remained in Technical Context — all unknowns were resolved by
inspecting the existing codebase directly. This document records the decisions and the evidence
behind them.

## Decision: Reuse `ConversationBox.vue` + `ConversationSidebar.vue` verbatim

- **Rationale**: `ConversationView.vue`
  (`app/javascript/dashboard/routes/dashboard/conversation/ConversationView.vue`) already composes
  exactly these two components (`ConversationBox` from
  `dashboard/components/widgets/conversation/ConversationBox.vue`, `ConversationSidebar` from
  `dashboard/components/widgets/conversation/ConversationSidebar.vue`, alongside
  `CmdBarConversationSnooze` and `SidepanelSwitch`) driven off the `getSelectedChat` Vuex getter
  (`currentChat`) and `uiSettings`. Neither component is coupled to `ChatList` or the standalone
  route by name — `ConversationBox` takes `inbox-id`/`is-on-expanded-layout` props and
  `ConversationSidebar` takes a `:current-chat="currentChat"` prop, all satisfiable from a drawer
  context — so they can be re-composed in a new drawer component without modification, satisfying
  FR-004 and Constitution Principle I.
  Precedent for this drawer/panel pattern already exists in this codebase: `SidepanelSwitch.vue`
  is itself a component-swap side-panel already wired into `ConversationView.vue`, and other
  `*Drawer.vue`-named components already exist in the dashboard (e.g.
  `ReportDrilldownDrawer.vue`, `AssistantDrilldownDrawer.vue`), confirming `Drawer` is an
  established naming idiom here, not a new one introduced by this feature.
- **Alternatives considered**: Building a new lightweight message-thread component — rejected,
  duplicates upstream behavior and diverges from Principle I (Upstream Compatibility First).

## Decision: `useConversationDrawer.js` composable as the sole active-chat coupling point

- **Rationale**: `ConversationView.vue`'s lifecycle logic drives `setActiveChat`,
  `clearSelectedState`, and conversation fetching through the `conversations` Vuex module
  (`app/javascript/dashboard/store/modules/conversations/actions.js`). Note: `mounted()` doesn't
  call these actions directly — it calls a local `initialize()` method, which internally performs
  the fetch-then-activate sequence below; the composable should replicate the sequence itself
  rather than the `initialize()` wrapper name. The exact sequence to replicate:
  1. If the conversation isn't already in `chatList`, dispatch `getConversation` (root action,
     `actions.js:36-44`) to fetch it by id.
  2. Once available, dispatch `setActiveChat({ data, after })` (`actions.js:194-209`) — this
     expects a full conversation object already present in `chatList`, so the composable must
     watch for the conversation to land in the store (mirroring `ConversationView.vue`'s
     `chatList.length` watcher) rather than assume `getConversation`'s response can be passed
     directly.
  3. Dispatch `markMessagesRead` (`store/modules/conversations/actions/messageReadActions.js:6`),
     matching existing call sites in `ChatList.vue`, `MessagesView.vue`, and `actions.js` itself
     (`syncActiveConversationMessages`, line 170) — the last confirms `markMessagesRead` is safe to
     dispatch redundantly/idempotently alongside other read-sync paths.
  4. On unmount / route leave, dispatch `clearSelectedState` (`actions.js:83-85`) — matching
     `ConversationView.vue`'s `beforeRouteLeave` hook — to satisfy FR-007.
- **Alternatives considered**: Dispatching these actions directly from
  `OpportunityConversationDrawer.vue` — rejected per FR-005's explicit requirement for a single
  composable as the coupling point, so future upstream changes to chat-state internals require
  updating only one file.

## Decision: Loading indicator reuses `MessagesView.vue`'s existing `Spinner`

- **Rationale**: There is no dedicated "skeleton" component for conversation loading anywhere in
  the dashboard. `MessagesView.vue` (rendered inside `ConversationBox.vue`) already shows
  `Spinner` (`dashboard/components-next/spinner/Spinner.vue`) while `shouldShowSpinner` is true.
  Since the drawer reuses `ConversationBox.vue` as-is, this loading state is inherited for free
  once the conversation begins loading inside the box — no separate skeleton needs to be built.
  This resolves the FR-006 clarification ("same loading/skeleton indicator the standalone
  conversation view already shows") without new code.
- **Alternatives considered**: Building a custom drawer-level skeleton to show before
  `ConversationBox` even mounts — rejected as unnecessary complexity (Principle II); the drawer can
  mount `ConversationBox` immediately and let its existing internal spinner cover the load, as long
  as `setActiveChat` runs before/while `ConversationBox` renders.

## Decision: New child route added via the existing anchor-based touch pattern

- **Rationale**: `dashboard.routes.js` already has an inline `opportunities_index` route object
  (lines 37-47) inserted by a `bin/sync-custom-module-hooks` manifest entry anchored on
  `...campaignsRoutes.routes,`. The script (`bin/sync-custom-module-hooks`) is idempotent
  (skips if the insert text is already present) and fails loudly if its anchor text isn't found —
  the established, safe way this fork touches shared route files. The new
  `opportunities_conversation` route should be added as a new manifest entry anchored on a unique
  string inside the already-inserted `opportunities_index` block (e.g. its closing `},`), keeping
  the touch pattern consistent with how `opportunities_index` itself was introduced.
- **Alternatives considered**: Converting the flat `opportunities` route entry into one with a
  `children` array — considered, but a sibling top-level entry
  (`opportunities/conversations/:conversationId`) is simpler and matches the flat structure already
  used by every other entry in this routes file (e.g. `inbox_conversation` is a flat sibling too,
  not nested under an `inbox` parent route).

## Decision: `OpportunityDetailView.vue` deletion is isolated

- **Rationale**: Repo-wide search confirms `KanbanBoard.vue` is the only consumer of
  `OpportunityDetailView.vue` (excluding a stale built asset in `public/vite-dev/`). No spec file
  references it either. Deleting it only requires updating `KanbanBoard.vue`'s import and template
  usage, satisfying FR-010 with no other blast radius.
- **Alternatives considered**: Keeping the file around unused "just in case" — rejected, dead code
  must be removed per repository conventions (CLAUDE.md: "Remove dead/unreachable/unused code").

## Note: Pre-existing `KanbanCard.vue` emit-name mismatch (unrelated bug, found during validation)

`KanbanCard.vue` declares `defineEmits(['click', 'status-changed'])` but actually emits
`$emit('statusChanged', ...)` (camelCase) at its call sites. This predates this feature and isn't
caused by it, but since `KanbanCard.vue` is already in this feature's edit scope (FR-003
opacity/affordance changes), it should be fixed opportunistically in the same edit rather than
left inconsistent — trivial, no behavior change beyond correcting the declared-vs-emitted name.

## Validation

Cross-checked against the real chatwoot/chatwoot upstream repository (gh_grep) and a fresh
read-only pass over this fork's current source (Explore agent) on 2026-07-31. All decisions above
were confirmed accurate against both; the corrections folded into this document (the `initialize()`
call path, the `ConversationSidebar`/`ConversationBox` props, the extra `markMessagesRead` call
site, and the `SidepanelSwitch`/`*Drawer` naming precedent) are the result of that pass. No
decision required reversal.
