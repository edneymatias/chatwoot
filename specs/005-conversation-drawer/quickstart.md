# Quickstart: Validating the Conversation Drawer

All commands run inside the containerized dev stack per this repo's `CLAUDE.md`.

## Prerequisites

```bash
docker compose up -d
```

Ensure the account has at least:
- One Opportunity/card with a valid `origin_conversation_id` (a conversation the current agent
  can access).
- One Opportunity/card with `origin_conversation_id` set to `null`.
- (For User Story 4 / error state) One Opportunity/card whose `origin_conversation_id` points to a
  conversation the agent cannot load (deleted, or belongs to an inbox the agent has no access to).

## Scenario 1 — Open the drawer from a linked card (User Story 1, P1)

1. Navigate to the Kanban board (`opportunities_index`).
2. Click a card with a linked conversation.
3. **Expect**: URL updates to `opportunities/conversations/:conversationId`
   (`opportunities_conversation`); a drawer slides in from the right showing the message thread and
   contact sidebar; the board remains visible/underneath.
4. Reply to the conversation from the drawer, then resolve it, then assign it.
5. **Expect**: All three actions behave identically to the standalone conversation view.
6. Reload the browser at the drawer's URL.
7. **Expect**: The drawer reopens directly showing the same conversation (no need to reopen it from
   the board).

## Scenario 2 — Non-clickable card (User Story 2, P2)

1. On the board, locate a card with no linked conversation.
2. **Expect**: The card renders with reduced opacity (`opacity-60`) and no pointer/hover affordance.
3. Click the card.
4. **Expect**: Nothing happens — no drawer, no URL change.

## Scenario 3 — Clean close (User Story 3, P2)

1. Open the drawer for a linked card (as in Scenario 1).
2. Click the drawer's close button.
3. **Expect**: Returns to the board unchanged (same cards, same stage layout); URL returns to
   `opportunities_index`.
4. Check elsewhere in the app (e.g. the main inbox conversation list) that the conversation is no
   longer reflected as the "active" chat.
5. Repeat steps 1-4, but close via browser back navigation instead of the close button.
6. **Expect**: Same clean result.

## Scenario 3b — Rapid re-click on a different linked card (Edge Case, US1)

1. Open the drawer for one linked card (as in Scenario 1).
2. Before it finishes loading (or immediately after), click a *different* card that also has a
   linked conversation.
3. **Expect**: The drawer settles on the second card's conversation only — its message thread and
   contact sidebar, matching the second card's `origin_conversation_id`. No trace of the first
   conversation (stale thread, stale sidebar, stale loading state) remains.

## Scenario 4 — Load failure (User Story 4, P3)

1. Directly navigate to `opportunities/conversations/:conversationId` using an id that cannot be
   loaded (not found, or belongs to an inbox the agent can't access).
2. **Expect**: The drawer opens showing an inline error message and a close action — not a blank
   panel, not a toast.
3. Click close.
4. **Expect**: Returns cleanly to the board.

## Verification commands

```bash
docker compose exec vite pnpm eslint
docker compose exec vite pnpm test
```

Both must pass for all touched/added files (Completion Criteria in the source phase doc).

## Manual code check

```bash
grep -r "OpportunityDetailView" app/javascript --include="*.vue" --include="*.js"
```

**Expect**: No results (file deleted, no remaining references).
