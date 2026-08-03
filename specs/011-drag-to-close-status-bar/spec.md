# Feature Specification: Drag-to-Close Status Bar

**Feature Branch**: `011-drag-to-close-status-bar`

**Created**: 2026-08-03

**Status**: Draft

**Input**: User description: "Phase 16: Drag-to-Close Status Bar — replace the won/lost action buttons on the opportunity card with a drag target. Dragging a card onto a status bar (dropzone) marks it won or lost; the card stays in its current pipeline lane. Reopen stays a direct button on closed cards. Reference: Kommo CRM shows this pattern as two drop zones (PERDA/loss, GANHO/won) that appear at the bottom of the board while a card is being dragged."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Closing an opportunity by dragging onto Won or Lost (Priority: P1)

A sales rep is working an opportunity card in the kanban board. Instead of opening a menu and clicking a "Won" or "Lost" button, they drag the card onto a status bar that appears at the bottom of the board, dropping it on the "Won" or "Lost" zone to close the opportunity with that outcome.

**Why this priority**: This is the core interaction being introduced — without it, the drag-to-close mechanism doesn't exist and the feature delivers no value.

**Independent Test**: Drag an open opportunity card onto the "Won" zone of the status bar and verify its status updates to won while it remains in its current pipeline lane; repeat for "Lost".

**Acceptance Scenarios**:

1. **Given** an open opportunity card in any pipeline lane, **When** the user drags the card and drops it on the "Won" zone of the status bar, **Then** the opportunity's status becomes "won" and the card stays in its current lane.
2. **Given** an open opportunity card in any pipeline lane, **When** the user drags the card and drops it on the "Lost" zone of the status bar, **Then** the opportunity's status becomes "lost" and the card stays in its current lane.
3. **Given** the user starts dragging a card, **When** the drag begins, **Then** the status bar with its "Won" and "Lost" zones becomes visible; **When** the drag ends without dropping on either zone, **Then** the status bar is hidden again and the opportunity's status is unchanged.
4. **Given** the user drags a card over the "Won" or "Lost" zone, **When** the card is positioned over a zone, **Then** that zone shows a visual highlight indicating it is a valid drop target.

---

### User Story 2 - Reopening a closed opportunity is unaffected (Priority: P2)

A sales rep has an opportunity that was previously marked won or lost. They click the existing "reopen" button on the card to set it back to open. This action is unchanged by the introduction of the drag-to-close status bar.

**Why this priority**: Confirms the existing reopen affordance is preserved and not accidentally converted into a drag interaction, since it is explicitly a click-based action.

**Independent Test**: On a card that is currently won or lost, click "reopen" and verify the status changes to "open" without any drag interaction required.

**Acceptance Scenarios**:

1. **Given** a card with status "won" or "lost", **When** the user clicks its "reopen" button, **Then** the opportunity's status becomes "open" and no status bar or drag interaction is involved.

---

### User Story 3 - Won/lost buttons are no longer available on the card (Priority: P2)

A sales rep looks at an open opportunity card's available actions. The direct "Won" and "Lost" buttons that used to appear there are gone; dragging onto the status bar is the only way to close an opportunity.

**Why this priority**: Removing the old buttons is necessary to avoid two conflicting affordances for the same action, but is lower risk/value than the new interaction itself.

**Independent Test**: Inspect an open opportunity card's actions and verify no "Won" or "Lost" buttons are present, only whatever actions remain (e.g. edit, complete fields).

**Acceptance Scenarios**:

1. **Given** an open opportunity card, **When** the user views its available actions, **Then** no direct "Won" or "Lost" buttons are shown.

---

### Edge Cases

- What happens when a card is dropped on the status bar but the account has required fields configured for that outcome (won/lost) that are missing on the opportunity? The status change is blocked and the user is prompted to fill the missing fields, per the existing closing-required-fields validation flow — the drag interaction does not bypass that check.
- What happens when a card is dropped outside both the "Won" and "Lost" zones (e.g. back into a lane, or in empty space)? The opportunity's status is unchanged; if dropped into a valid lane position, normal card-move-between-stages behavior applies as today.
- What happens when a user drags a card that is already won or lost onto the status bar? Already-closed cards are not draggable onto the status bar; closing only applies to open opportunities. (Reopening remains a separate, click-based action per User Story 2.)
- What happens on touch/small-screen layouts where drag-and-drop may be harder to perform precisely? Out of scope for this phase — no touch-specific fallback is introduced; the board already assumes a drag-capable board today.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display a status bar containing two distinct drop zones, "Won" and "Lost", while an opportunity card drag is in progress.
- **FR-002**: The status bar MUST NOT be visible/active when no card drag is in progress.
- **FR-003**: System MUST allow a user to mark an open opportunity as "won" by dragging its card and dropping it on the "Won" zone.
- **FR-004**: System MUST allow a user to mark an open opportunity as "lost" by dragging its card and dropping it on the "Lost" zone.
- **FR-005**: After a status change via the status bar, the opportunity's card MUST remain in its current pipeline lane (no removal or relocation caused by the status change itself).
- **FR-006**: System MUST remove the direct "Won" and "Lost" action buttons from the opportunity card; the status bar drag is the only path to close an opportunity as won or lost.
- **FR-007**: The "reopen" action MUST remain a direct button on won/lost cards and MUST NOT require any drag interaction.
- **FR-008**: System MUST provide a visual highlight on a drop zone when a dragged card is positioned over it, indicating it is a valid drop target.
- **FR-009**: System MUST leave the opportunity's status unchanged when a card drag ends without dropping on the "Won" or "Lost" zone.
- **FR-010**: If closing-required-field validation (per the closing-required-fields feature) rejects a won/lost status change initiated by dropping on the status bar, the system MUST NOT change the opportunity's status and MUST surface the missing-fields prompt to the user, consistent with how that validation is surfaced today.
- **FR-011**: Already-closed (won/lost) opportunity cards MUST NOT be offered as draggable onto the status bar.

### Key Entities *(include if feature involves data)*

- **Opportunity**: The kanban card being dragged; relevant attributes are its status (open/won/lost) and its current pipeline stage/lane, which is unaffected by a status-only change.
- **Status Bar**: A transient UI element containing two drop zones ("Won" and "Lost") that only appears during an active card drag and accepts opportunity cards as drop payloads.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can mark an opportunity won or lost in a single drag-and-drop gesture, without opening any menu or additional dialog (when no required fields are missing).
- **SC-002**: 100% of drags over a "Won" or "Lost" zone produce a visible highlight before the drop completes, so users can confirm the target before releasing.
- **SC-003**: Dropping a card anywhere other than a valid drop zone never changes its status — verified across repeated attempts with no unintended closes.
- **SC-004**: No opportunity card retains a direct "Won"/"Lost" button after this change ships, eliminating the prior duplicate-affordance path to closing.

## Assumptions

- The status bar is a single combined element with two adjacent drop zones ("Won" and "Lost") rather than two fully separate UI regions, matching the two-zone pattern shown in the reference example.
- The status change on drop is applied immediately (no confirmation dialog), consistent with the immediate behavior of the buttons it replaces — the closing-required-fields prompt (FR-010) is the only interruption, and only when applicable.
- The status bar's screen position (e.g. bottom of the board) is a layout detail left to implementation/design and does not affect the functional behavior specified here.
- A trash/delete drop target, as shown alongside the won/lost zones in the reference example, is out of scope — this phase only introduces the won/lost closing interaction, not deletion.
- This phase does not change how the card visually indicates its current status (e.g. existing status badge) — only how that status is set.
- Closing-required-fields validation (FR-010) is provided by a related, independently developed capability; if that capability is not yet available when this phase ships, the status bar drag applies the status change unconditionally, per the source design notes.
