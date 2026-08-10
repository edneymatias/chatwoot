# Feature Specification: Hide Closed Opportunities by Default, and Fix Win/Loss Drag-and-Drop Bug

**Feature Branch**: `030-hide-closed-dnd-fix`

**Created**: 2026-08-10

**Status**: Draft

**Input**: User description: "Hide closed (won/lost) opportunities from the Kanban board and List view by default, discoverable only through the existing filter system; and fix a drag-and-drop bug where dropping a card on the won/lost zone can simultaneously and incorrectly change the card's pipeline stage."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Board shows only active deals by default (Priority: P1)

A sales rep opens the Kanban board or the List view to review their pipeline. They see only
opportunities that are still open (not yet won or lost), so the board reflects the deals that
still need attention rather than being cluttered with concluded ones.

**Why this priority**: This is the core value of the feature — it directly determines what every
user sees every time they open the Opportunities module, and mirrors the existing default
behavior of the Conversations inbox (open conversations only).

**Independent Test**: Can be fully tested by creating opportunities with a mix of open, won, and
lost statuses, then opening the Kanban board and the List view with no filters applied — only the
open opportunities should be visible.

**Acceptance Scenarios**:

1. **Given** an account with open, won, and lost opportunities, **When** a user opens the Kanban
   board with no filters applied, **Then** only open opportunities are shown in the pipeline stage
   columns.
2. **Given** an account with open, won, and lost opportunities, **When** a user opens the List
   view with no filters applied, **Then** only open opportunities appear in the list.

---

### User Story 2 - Closed deals remain discoverable via filters (Priority: P2)

A sales rep wants to review deals that were already won or lost — for reporting, follow-up, or
auditing purposes. They use the existing status filter to explicitly bring closed opportunities
back into view.

**Why this priority**: Ensures the new default doesn't remove access to historical data; it's a
secondary but necessary complement to User Story 1 so no information is lost, only hidden by
default.

**Independent Test**: Can be fully tested by applying the existing status filter (selecting
`won`, `lost`, or both) on the Kanban board or List view and confirming the matching closed
opportunities appear.

**Acceptance Scenarios**:

1. **Given** a board showing only open opportunities by default, **When** a user filters by
   status "won", **Then** only won opportunities are shown.
2. **Given** a board showing only open opportunities by default, **When** a user filters by
   status "lost", **Then** only lost opportunities are shown.
3. **Given** a board showing only open opportunities by default, **When** a user selects all
   statuses (open, won, lost) in the filter, **Then** opportunities of every status are shown.

---

### User Story 3 - Contact profile still shows full opportunity history (Priority: P2)

A sales rep viewing a contact's profile wants to see that contact's complete deal history —
open, won, and lost — for full context on the relationship, independent of the new
board-wide default.

**Why this priority**: Without this, the new default would unintentionally hide a contact's past
outcomes from the one place where full history is most valuable, breaking an existing workflow.

**Independent Test**: Can be fully tested by opening a contact's profile panel that has
opportunities of every status and confirming all of them are listed, unaffected by the board's new
default scoping.

**Acceptance Scenarios**:

1. **Given** a contact with open, won, and lost opportunities, **When** a user opens that
   contact's profile panel, **Then** opportunities of every status are listed.

---

### User Story 4 - Dropping a card on the won/lost zone changes only its status (Priority: P1)

A sales rep drags a Kanban card onto the "Won" or "Lost" drop zone to close the deal. Only the
deal's status changes; the pipeline stage the deal was in at the time it was won or lost stays
exactly as it was, so later reporting on "which stage deals typically close from" remains
accurate.

**Why this priority**: This is a data-integrity bug — today, a single drag gesture can silently
and incorrectly overwrite the pipeline stage while also correctly setting the status, corrupting
historical stage data with no visible error to the user. Fixing it is as critical as the display
default itself.

**Independent Test**: Can be fully tested by dragging a card from any pipeline stage column onto
the won/lost drop zone and confirming afterward that the card's status changed but its
last-recorded pipeline stage before closing is unchanged.

**Acceptance Scenarios**:

1. **Given** a card in an arbitrary pipeline stage column, **When** a user drags it onto the "Won"
   drop zone and releases it, **Then** the card's status becomes "won" and its pipeline stage is
   unchanged from immediately before the drag.
2. **Given** a card in an arbitrary pipeline stage column, **When** a user drags it onto the
   "Lost" drop zone and releases it, **Then** the card's status becomes "lost" and its pipeline
   stage is unchanged from immediately before the drag.
3. **Given** a card being dragged near the boundary between a pipeline stage column and the
   won/lost drop zone, **When** the user releases it inside the won/lost zone, **Then** exactly
   one outcome is recorded (the status change) and no simultaneous, unintended stage change
   occurs.

---

### Edge Cases

- A user who has already applied a status filter reloads the page or navigates away and back —
  filter selections are not persisted today and this feature does not change that; the default
  (open-only) reapplies until the user filters again.
- A user explicitly requests every status via the filter system — the default must not silently
  reassert itself or interfere with that explicit choice.
- A card is dragged and dropped in a way that overlaps both a pipeline stage column and the
  won/lost drop zone visually — only one outcome (the intended one, based on where the user
  visually released the card) must be recorded.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST show only open opportunities on the Kanban board and List view when
  no status filter is applied by the user.
- **FR-002**: Users MUST be able to see opportunities of every status (open, won, lost) by
  explicitly selecting "all statuses" through the existing filter system.
- **FR-003**: Any explicit status selection made by the user through the existing filter system
  (e.g., "won" only, "lost" only, or any combination) MUST override the open-only default and
  show exactly the selected statuses.
- **FR-004**: A contact's opportunity history panel MUST continue to show that contact's
  opportunities of every status, unaffected by the new open-only default applied elsewhere.
- **FR-005**: The system MUST NOT display any visual indicator that a default status scope is
  active — discovering closed opportunities is a fully proactive action via the existing filter
  panel.
- **FR-006**: Dropping a card onto the won/lost drop zone MUST change only that opportunity's
  status; it MUST NOT change the opportunity's pipeline stage.
- **FR-007**: A single card drag-and-drop gesture MUST result in exactly one outcome (either a
  stage change or a status change, never both, and never neither when dropped on a valid target).

### Key Entities *(include if feature involves data)*

- **Opportunity**: A sales deal tracked through the pipeline; has a status (open, won, or lost)
  and a pipeline stage. The status determines whether it appears in the default board/list view.
  The pipeline stage records where in the sales process the deal currently sits (or last sat,
  once closed).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A newly opened Kanban board or List view with no filters applied shows 0 won/lost
  opportunities out of any mix of open, won, and lost opportunities present in the account.
- **SC-002**: 100% of opportunities of every status remain retrievable by users through the
  existing filter system, with no data loss or hidden records.
- **SC-003**: A contact's opportunity history panel shows 100% of that contact's opportunities
  regardless of status, matching pre-feature behavior.
- **SC-004**: Dragging a card onto the won/lost drop zone results in a pipeline-stage change 0% of
  the time (only a status change), across repeated manual trials from every pipeline stage column.
- **SC-005**: Users reviewing their pipeline report spending less time visually filtering out
  closed deals to find active ones, since the default view already excludes them.

## Assumptions

- The existing status filter (already supporting `open`, `won`, `lost`, and combinations thereof)
  is reused unchanged; no new filter options are introduced by this feature.
- Filter selections are not persisted across page reloads or navigation today, and this feature
  does not introduce persistence — the open-only default reapplies each time a user returns to an
  unfiltered board or list view.
- The pipeline stage a deal is left in after being marked won/lost is not automatically
  reassigned to any special "closed" stage; it simply retains its last stage before closing.
- This feature does not change how won/lost status or pipeline stage are used in existing
  reporting features — those already query opportunities directly with their own status scoping
  and are unaffected.
