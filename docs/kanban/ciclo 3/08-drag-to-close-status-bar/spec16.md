# Phase 16: Drag-to-Close Status Bar

**Status**: designed — ready for implementation
**Depends on**: Phase 6 (card info and ordering — current won/lost buttons
on `KanbanCard.vue`), Phase 19 (closing required fields on win/loss —
blocks the drag when required fields are missing)

## Decisions

- The card stays in its current lane when marked won/lost — today's
  behavior (`UPDATE_OPPORTUNITY` merges fields, doesn't remove from
  `idsByStage`) does **not** change. No "disappears from the board"
  behavior in this phase.
- The won/lost action buttons are removed from `KanbanCard.vue`.
  Dragging the card onto the new status bar (dropzone) is the only way to
  mark won/lost.
- Once an opportunity is won/lost, a **reopen** button appears on the
  card (sets `status: 'open'`) — this stays a direct button, not a drag
  target.
- Missing-required-fields blocking on win/loss drag depends on Phase 19;
  if Phase 19 isn't ready yet, this phase can ship with unconditional
  drag-to-close and Phase 19 adds the blocking validation afterward.

## Deferred (explicitly out of scope here)

A visual indicator for closed (won/lost) opportunities on the board
header is out of scope for this phase — no header/summary UI exists yet.
**Note for the list view phase** (`04-list-view`, spec8): when designing
that view's header/filters, revisit whether a "show closed opportunities"
toggle or count belongs there, since closed opportunities remain in their
lane with no dedicated visibility control today.

## Remaining open questions

- One combined status bar with two drop zones (won/lost side by side), or
  two separate targets?
- Visual feedback during drag (bar highlighting, confirm-on-drop vs.
  immediate)?
