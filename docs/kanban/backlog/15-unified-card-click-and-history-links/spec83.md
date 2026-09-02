# Phase 83: Unified Kanban Card Click & Conversation Links in History

**Status**: Design approved by the user on 2026-09-02 — ready for an implementation plan.

**Depends on**: none functionally on other backlog phases. Builds directly on top of the
multi-conversation-per-opportunity work (`OpportunityConversation`, `associated_conversations_json`
in `custom/app/models/custom/concerns/opportunity_conversation_management.rb`) and the audit/history
panel (`OpportunityActivity`, `OpportunityActivityLog.vue`) introduced in earlier phases. No backend
changes required — every piece of data this phase needs already exists and is already persisted.

## Quick Preview

Today, clicking a Kanban card only does something when the opportunity has an
`active_conversation_id`: it opens `OpportunityConversationDrawer.vue` showing that conversation,
which itself has a tab to switch to the history/audit panel (`OpportunityActivityLog.vue`). When
there is no active conversation, the card click is a no-op (card rendered `grayscale`,
`cursor-default`, `border-dashed`), and the only affordance is a "+" button to start or link a
conversation.

This phase does two things, both confirmed to need zero backend work — the routing
(`opportunities_conversation`) and its loader (`useConversationDrawer.js`) are already generic
(load whatever `conversationId` is given, not hardcoded to the opportunity's active one), and every
conversation-related `OpportunityActivity` already stores `metadata.conversation_id` /
`metadata.conversation_display_id`:

1. **Uniform card click**: clicking a card always opens something — the active conversation if one
   exists, otherwise the history panel directly. The "+" button stays as-is, a separate explicit
   action (`@click.stop`), unaffected by this change.
2. **History entries become links**: the four conversation-related activity-log event types
   (`conversation_opened`, `conversation_transferred_in`, `conversation_transferred_out`,
   `conversation_detached`) render as clickable links instead of plain text. Clicking one switches
   the drawer to the conversation tab showing that specific conversation, regardless of its status
   (open, resolved, or no longer linked to this opportunity — see Part 2 note).

## Part 1 — Uniform card click

### Route: optional `conversationId`

`app/javascript/dashboard/routes/dashboard/dashboard.routes.js` — the `opportunities_conversation`
child route (`path: 'conversations/:conversationId'`, under `opportunities_index`, component
`OpportunityConversationDrawer.vue`) becomes:

```js
{
  path: 'conversations/:conversationId?',
  name: 'opportunities_conversation',
  component: OpportunityConversationDrawer,
  props: true,
},
```

`app/javascript/dashboard/composables/useConversationDrawer.js` — its watcher on
`route.params.conversationId` already drives conversation loading; add a guard so it's a no-op when
the param is absent instead of attempting to load `undefined`:

```js
watch(
  () => route.params.conversationId,
  id => {
    if (!id) return;
    // existing load logic unchanged
  },
  { immediate: true }
);
```

### Drawer: default tab depends on whether a conversation was requested

`OpportunityConversationDrawer.vue` — `activeTab` initializes based on whether the route already
carries a `conversationId`, and switches to `'conversation'` whenever one becomes present (covers
both the initial "opened directly on a conversation" case and "clicked a link from history" case,
via one mechanism):

```js
const activeTab = ref(route.params.conversationId ? 'conversation' : 'activity');

watch(
  () => route.params.conversationId,
  id => {
    if (id) activeTab.value = 'conversation';
  }
);
```

### Card click: always navigate

`KanbanCard.vue`'s `handleCardClick` and `Index.vue`'s `handleRowClick` (list view) both currently
no-op when `active_conversation_id` is falsy. Both change to always push, including
`conversationId` only when there's an active conversation:

```js
const handleCardClick = () => {
  const params = {};
  if (opportunity.active_conversation_id) {
    params.conversationId =
      opportunity.active_conversation_display_id || opportunity.active_conversation_id;
  }
  router.push({
    name: 'opportunities_conversation',
    params,
    query: { opportunityId: opportunity.id },
  });
};
```

`KanbanCard.vue`'s `cardClass` drops the `grayscale`/`cursor-default`/`border-dashed` branch — the
card is now always clickable, so it always renders with the normal clickable appearance. The "+"
button (`StartOpportunityConversationButton.vue`, still `v-if="!opportunity.active_conversation_id"`)
keeps its own `@click.stop` (already the case) so it doesn't trigger the card's own navigation.

## Part 2 — Conversation entries in history become links

`OpportunityActivityLog.vue` currently renders `conversation_opened` / `conversation_transferred_in`
/ `conversation_transferred_out` / `conversation_detached` entries as plain interpolated text
(`t(key, { displayId })`). Each of these events already carries what's needed in `metadata`
(`custom/app/models/opportunity_conversation.rb`,
`custom/app/models/custom/concerns/opportunity_conversation_management.rb`):
`conversation_id` and `conversation_display_id`.

Change: for these four event types, render the display-id portion of the message as a link. Click
handler pushes the same route as the card, with that conversation's id and the query param
preserved explicitly (a named push doesn't inherit the current query automatically):

```js
const openConversation = displayId => {
  router.push({
    name: 'opportunities_conversation',
    params: { conversationId: displayId },
    query: { opportunityId: route.query.opportunityId },
  });
};
```

Because `OpportunityConversationDrawer.vue`'s `watch` on `route.params.conversationId` (Part 1)
already flips `activeTab` to `'conversation'` whenever it's set, no event/emit plumbing between
`OpportunityActivityLog.vue` and its parent is needed — the route change alone drives the tab
switch, the same mechanism already used for the card click.

**Status independence**: `useConversationDrawer.js` loads a conversation by id regardless of its
`status` (open/resolved/pending) — no filtering exists today that would block opening a closed one.
**Detached conversations**: a `conversation_detached` entry's link still opens that conversation —
this is a historical/audit view (the whole point of the panel), independent of whether the
conversation is still linked to this opportunity right now; `currentOpportunity` in the drawer
resolves from `query.opportunityId`, not from the conversation's current association, so this
already works without special-casing.

## Out of scope

- Any new entry point for starting/linking a conversation from inside the history panel — the "+"
  button on the card remains the only place for that action (confirmed with the user).
- Changing what `OpportunityActivityLog.vue` shows for non-conversation events
  (`opportunity_created`, `opportunity_stage_changed`, `opportunity_won/lost/reopened`) — unchanged.
- A dedicated "related conversations" list/section separate from the activity log — this phase only
  makes the existing conversation-related log entries clickable, it doesn't add a new UI section
  (the `associated_conversations` payload already has everything needed if that's wanted later, but
  no evidence it's needed now).
- Any backend change — confirmed everything needed (`metadata.conversation_id`/
  `conversation_display_id`, route/composable already being id-agnostic) already exists.

## Acceptance criteria

- Clicking a Kanban card (or list-view row) with an active conversation opens that conversation, on
  the conversation tab — same as today, no regression.
- Clicking a Kanban card (or list-view row) with **no** active conversation opens the drawer
  directly on the history/activity tab, instead of doing nothing.
- The card's "+"/start-conversation button still works exactly as today, and clicking it does not
  also trigger the card's own navigation.
- Cards without an active conversation no longer render `grayscale`/dashed/non-pointer — same
  visual treatment as cards with one.
- In the history panel, each `conversation_opened`/`conversation_transferred_in`/
  `conversation_transferred_out`/`conversation_detached` entry is a clickable link.
- Clicking one of those links switches the drawer to the conversation tab, showing that specific
  conversation — including when it's resolved/closed, and including a `conversation_detached` entry
  whose conversation is no longer linked to this opportunity.
- The opportunity context shown alongside the conversation (via `query.opportunityId`) stays correct
  after following a history link — it doesn't get lost or reset.
- Full spec/lint suite (ESLint, Jest) passes, including updated specs for `KanbanCard.vue`,
  `OpportunityConversationDrawer.vue`, and `OpportunityActivityLog.vue` covering the new
  no-active-conversation click path and the history-link click path.
