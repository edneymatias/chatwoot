# Phase 70: Kanban Drag Undo Toast

**Status**: Design approved by user on 2026-08-17 — ready for an implementation plan.
**Depends on**: `custom/app/models/opportunity.rb` (existing `moveCard`/`setStatus` update
endpoint, `PATCH /opportunities/:id`), the existing Kanban drag-and-drop flow
(`app/javascript/dashboard/components-next/Opportunities/KanbanBoard.vue`,
`KanbanColumn.vue`, `KanbanStatusBar.vue`), and the existing `opportunities` Vuex module
(`app/javascript/dashboard/store/modules/opportunities/actions.js`). No backend changes.

## 1. Problem

Since the board switched to click-and-drag panning (dragging an empty area of the board to
scroll it), it's become easy to accidentally grab and drop an opportunity card while intending to
pan — moving it to a different pipeline stage, or into the Won/Lost drop zone, without meaning to.
There is currently no way to undo that specific action; the user has to manually drag the card
back (and, for a Won/Lost drop, manually reopen it).

## 2. Scope

Covers only moves that **actually completed**: a stage-to-stage drag between columns, or a drop
onto the Won/Lost status bar, in either case where no `StageTransitionRequirementsModal` /
`ClosingRequirementsModal` interrupted the flow (i.e. the destination stage/outcome had no unmet
required fields). When one of those modals appears, cancelling it already reverts the drag with no
extra affordance needed — that existing behavior is untouched. This spec adds a brief,
undo-capable confirmation for the case where the move went through silently.

Out of scope: undoing any other opportunity edit (manual field changes, assignment changes,
creation/deletion) — only the drag-triggered stage/status move is covered.

## 3. UI: `KanbanUndoToast.vue`

New component, `app/javascript/dashboard/components-next/Opportunities/KanbanUndoToast.vue` — a
small stack of toasts anchored to `absolute inset-x-0 bottom-0` of the Kanban board, in the same
screen region as `KanbanStatusBar.vue`'s Won/Lost drop zones. No visual collision: the status bar
only renders while a drag is actively in progress (`is-dragging`), and the undo toast only appears
after a drag has ended and its move has been committed, so the two are never on screen at the same
time.

Behavior:
- Each entry shows a short message ("Movido para {stage name}" / "Marcado como Ganha" / "Marcado
  como Perdida") plus an "Desfazer" (Undo) link.
- Each entry has its own 5-second timer, independent of the others.
- Hovering the mouse over the toast stack pauses every visible timer's countdown; leaving resumes
  each one from where it was paused (not a full reset) — this exists specifically so that a second
  accidental move landing while the first toast has under ~1s left doesn't rob the user of time to
  read and react to both.
- Maximum of 3 toasts visible at once. If a 4th arrives, the oldest is dismissed immediately
  (without executing its undo) to make room — this caps visual clutter from a burst of accidental
  moves without blocking new ones.
- Clicking "Desfazer" removes that entry immediately and runs its undo callback; it does not affect
  the other stacked entries or their timers.

## 4. Capture and reversal logic

All of this lives in `KanbanBoard.vue`, reusing the Vuex actions that already exist for the forward
move — undo is just the same action called with the direction reversed, so it inherits the
existing optimistic-commit + revert-on-error behavior for free.

- **Stage move**: in `executeMoveCard`, after `store.dispatch('opportunities/moveCard', …)`
  resolves successfully, push a toast whose undo callback re-dispatches `opportunities/moveCard`
  with `fromStageId`/`toStageId` swapped, restoring the card to its original stage **and original
  position** within that stage's column.
  - The original position (`fromIndex`) is available for free from vuedraggable's `removed` event
    (`event.removed.oldIndex`) in `KanbanColumn.vue`'s `onChange` handler; it needs to be threaded
    through the existing `cardRemoved` emit → `onCardRemoved` → `pendingMove` bookkeeping in
    `KanbanBoard.vue`, alongside `fromStageId`, which already makes the same trip.
- **Status change (Won/Lost)**: in `onStatusChanged`, after `store.dispatch('opportunities/setStatus', …)`
  resolves successfully (i.e. the `catch` for `missing_required_fields` was not hit), push a toast
  whose undo callback re-dispatches `opportunities/setStatus` with `status: 'open'`. The original
  status is always `'open'` — cards are only draggable while open (`Draggable`'s `filter=".is-closed"`
  in `KanbanColumn.vue` already excludes closed cards from being dragged at all), so there's no
  ambiguity about what to restore.

## 5. State management

New composable: `app/javascript/dashboard/components-next/Opportunities/composables/useKanbanUndoStack.js`.
Encapsulates the toast list, the 3-item cap, and the pause/resume timer logic (tracking remaining
time per entry, clearing/restarting `setTimeout` on hover in/out). Mirrors the array-of-timed-items
pattern already used by `SnackbarContainer.vue`, extended with pause/resume. `KanbanBoard.vue`
calls this composable to push entries; `KanbanUndoToast.vue` receives the stack as a prop and emits
hover/undo events back up.

This is a standalone unit purely about "manage a capped, individually-timed, pausable list" — it
has no opportunity-specific knowledge itself (that lives in the push calls made from
`KanbanBoard.vue`), which keeps it independently testable and reusable if another board-scoped
undo need comes up later.

## 6. Testing

- Composable unit tests: push beyond the cap of 3 evicts the oldest; pause on hover freezes the
  remaining time; resume continues from the frozen value instead of resetting.
- `KanbanBoard.spec.js` (existing): a completed stage move triggers a toast whose undo call invokes
  `opportunities/moveCard` with stage/index reversed; a completed Won/Lost drop triggers a toast
  whose undo call invokes `opportunities/setStatus` with `status: 'open'`; a move interrupted by
  `StageTransitionRequirementsModal`/`ClosingRequirementsModal` does **not** produce a toast.

## 7. Acceptance criteria

- Dragging a card between two columns that don't require fields shows an undo toast; clicking
  "Desfazer" within 5s returns the card to its original stage and original position.
- Dropping a card on Won/Lost (no required fields configured) shows an undo toast; clicking
  "Desfazer" within 5s reopens the opportunity (`status: 'open'`) with no other side effects.
- A move interrupted by a required-fields modal does not produce an undo toast (the existing
  cancel-reverts-the-drag behavior already handles that case).
- Hovering over the toast stack pauses all visible timers; moving the mouse away resumes them from
  where they were paused, not from zero.
- A 4th accidental move while 3 toasts are already visible dismisses the oldest one to make room.
