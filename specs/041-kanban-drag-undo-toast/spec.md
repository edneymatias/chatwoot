# Feature Specification: Kanban Drag Undo Toast

**Feature Branch**: `041-kanban-drag-undo-toast`

**Created**: 2026-08-17

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 9/15-kanban-drag-undo-toast/spec70.md"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Undoing Stage-to-Stage Drag Moves (Priority: P1)

As a sales agent or manager organizing opportunities on the Kanban board, I want an immediate "Undo" confirmation toast after dragging a card to a new stage, so that if I moved a card by accident (for example, while panning across the board), I can restore it to its original column and exact position with a single click.

**Why this priority**: Core value of the feature. Accidental card drags between stages happen frequently with click-and-drag panning; an instant undo prevents pipeline data corruption and agent frustration.

**Independent Test**: Can be tested by dragging an opportunity card from Stage A to Stage B, observing the undo toast appear, clicking "Undo", and verifying the card returns to Stage A at its exact original position and rank.

**Acceptance Scenarios**:

1. **Given** a user drags an opportunity card from Stage A to Stage B, **When** the move completes without validation blocks, **Then** an undo toast appears at the bottom of the board saying "Moved to [Stage B Name]" with an "Undo" action link.
2. **Given** the undo toast is visible, **When** the user clicks "Undo" within 5 seconds, **Then** the card is moved back to Stage A at its original index position and the toast is dismissed immediately.
3. **Given** the undo toast is visible, **When** 5 seconds elapse without user interaction, **Then** the toast is automatically dismissed and the move is kept.

---

### User Story 2 - Undoing Terminal Status Drops (Won/Lost) (Priority: P2)

As an agent using the Kanban board, I want to quickly undo accidental drops onto the bottom Won or Lost status bar, so that a deal is not unintentionally closed or marked lost when attempting to pan or move cards.

**Why this priority**: Accidental drops into terminal states (Won/Lost) are high-impact mistakes that otherwise require navigating into the card to reopen and reassign.

**Independent Test**: Can be tested by dragging an open opportunity card into the Won or Lost drop zone, clicking "Undo" on the resulting toast, and verifying that the opportunity status returns to "open" immediately.

**Acceptance Scenarios**:

1. **Given** a user drags an open card onto the "Won" drop zone (and no closing required fields block the move), **When** the status update succeeds, **Then** an undo toast appears saying "Marked as Won" with an "Undo" action link.
2. **Given** a user drags an open card onto the "Lost" drop zone, **When** the status update succeeds, **Then** an undo toast appears saying "Marked as Lost" with an "Undo" action link.
3. **Given** an undo toast for a Won/Lost drop is visible, **When** the user clicks "Undo", **Then** the opportunity status is restored to "open" and the toast is dismissed.

---

### User Story 3 - Toast Stack Management, Pause on Hover & Auto-Dismiss (Priority: P3)

As an agent performing multiple actions in quick succession, I want the undo toasts to stack cleanly (up to 3 items), pause their countdown when I hover over them, and resume when I move the cursor away, so that rapid actions do not cause me to run out of time to undo an accidental move.

**Why this priority**: Ensures high usability and ergonomic safety during rapid board interactions without overwhelming the UI with toast clutter.

**Independent Test**: Can be tested by triggering 4 rapid moves (verifying the oldest toast is dropped when the 4th arrives) and hovering the mouse over the toast stack (verifying the timers pause and resume from the paused remainder).

**Acceptance Scenarios**:

1. **Given** up to 3 undo toasts are displayed, **When** a new completed move occurs, **Then** the new toast is added to the top of the stack and each entry maintains its independent 5-second timer.
2. **Given** 3 undo toasts are already active, **When** a 4th move completes, **Then** the oldest toast in the stack is evicted immediately to make room for the new one without executing its undo.
3. **Given** one or more undo toasts are actively counting down, **When** the user hovers the cursor over the toast container, **Then** all active countdown timers pause.
4. **Given** toast timers are paused due to hover, **When** the user moves the cursor away from the toast container, **Then** each timer resumes counting down from its remaining paused duration (not reset to 5s).

---

## Edge Cases

- **Interrupted moves (Required Fields Modals)**: If dragging a card triggers a `StageTransitionRequirementsModal` or `ClosingRequirementsModal`, cancelling the modal already cancels/reverts the drag; in this case, no undo toast MUST be emitted.
- **Closed cards**: Cards in Won or Lost states cannot be dragged (enforced by draggable filters); undoing a Won/Lost drop restores the status strictly to `open`.
- **Rapid undo clicks**: Clicking "Undo" on a toast immediately removes that specific toast from the stack and dispatches the reversal action without affecting the timers or state of other stacked toasts.
- **Simultaneous status bar visibility**: The bottom `KanbanStatusBar` is only visible while dragging is active (`is-dragging`). Undo toasts only appear after dragging ends and completes. Therefore, the status bar and undo toasts never visually collide in the bottom viewport zone.
- **Network / API failure on undo**: If an undo action fails on the server, the standard UI error notification is shown and the optimistic revert rolls back to ensure UI consistency.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display an undo toast notification anchored at the bottom center of the Kanban board upon successful completion of a drag-and-drop stage transition or Won/Lost status drop.
- **FR-002**: System MUST capture the original stage ID (`fromStageId`) and original column index (`fromIndex`) for every stage move to enable precise spatial reversal.
- **FR-003**: System MUST provide an "Undo" action button in each toast that, when clicked, dispatches the inverse operation (reversing stage and index, or restoring status to `open`) and removes the toast immediately.
- **FR-004**: System MUST automatically dismiss each toast entry 5 seconds after creation if no interaction occurs.
- **FR-005**: System MUST pause the countdown timers of all visible toasts whenever the user's cursor hovers over the toast stack container, and resume the countdowns from their exact remaining time when the cursor leaves.
- **FR-006**: System MUST cap the maximum number of simultaneous undo toasts to 3. If a new toast is pushed when 3 are already active, the oldest toast MUST be dismissed immediately.
- **FR-007**: System MUST NOT display an undo toast when a drag move is interrupted by a required-fields modal or when a move is cancelled.
- **FR-008**: System MUST implement undo state management via a dedicated reusable composable (`useKanbanUndoStack.js`) that manages capped, individually-timed, pausable items independently of domain logic.
- **FR-009**: System MUST render the toast UI using a dedicated component (`KanbanUndoToast.vue`) positioned cleanly above or within the bottom board container with Tailwind utility classes.
- **FR-010**: System MUST provide synchronous localization for all toast copy ("Moved to {stage}", "Marked as Won", "Marked as Lost", "Undo") in both English (`en`) and Brazilian Portuguese (`pt-BR`).

### Key Entities

- **Undo Toast Item**: Represents an active undoable action with attributes: `id` (unique identifier), `message` (localized description of the action), `onUndo` (callback executing the reversal), `timeout` (total duration in ms, default 5000), `remainingTime` (remaining ms), `timerId` (active timeout handle), and `createdAt` (timestamp).
- **Undo Stack**: An array of up to 3 Undo Toast Items managed in FIFO order for eviction, with collective hover-pause/resume capabilities.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of unblocked drag-and-drop stage moves and status bar drops generate an undo toast within 50ms of action completion.
- **SC-002**: Clicking "Undo" restores the opportunity card to its exact previous stage and list position in 1 click.
- **SC-003**: 100% of toast timers pause reliably on cursor hover and resume without resetting or drifting.
- **SC-004**: The visible toast stack never exceeds 3 items under any burst of actions.
- **SC-005**: 100% of toast text and action labels are fully localized in English and Brazilian Portuguese.

## Assumptions

- No backend changes or new API endpoints are required; existing `opportunities/moveCard` and `opportunities/setStatus` Vuex actions are reused for reversal.
- Click-and-drag panning on the Kanban board remains enabled.
- The toast stack is scoped to the active Kanban board view and clears if the user navigates away from the board.
- Undoing manual field edits in the detail drawer or contact panel is out of scope for this feature.
