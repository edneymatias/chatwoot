# Feature Specification: Kanban Lane Visual Improvements

**Feature Branch**: `013-kanban-lane-visual-improvements`

**Created**: 2026-08-03

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 3/07-kanban-lane-visual-improvements/spec15.md" — Kanban board columns (lanes) today show only the lane name and the count of deals currently loaded into that column, which becomes misleading once a lane has more deals than are loaded on screen. Admins need each lane to show an accurate, lane-wide summary of open deals (count or total value), and to be able to give each lane a distinguishing color accent.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Accurate lane totals (Priority: P1)

A sales user working the kanban board glances at a lane's header and sees a total (either the number of open deals, or their combined value) that reflects every open deal in that lane — not just the ones currently scrolled into view.

**Why this priority**: The board's per-lane count today is already visibly wrong once a lane grows past its first page of loaded cards, which undermines trust in the board as a source of truth for pipeline size. This is the core problem the feature exists to fix.

**Independent Test**: Load a lane with more open deals than fit in the first page of cards; confirm the header total still reflects the full lane, not just the loaded cards.

**Acceptance Scenarios**:

1. **Given** a lane configured to show total value, **When** the board loads, **Then** the lane header shows the combined value of every open deal in that lane, formatted in the account's configured currency.
2. **Given** a lane configured to show count, **When** the board loads, **Then** the lane header shows the number of open deals in that lane.
3. **Given** a lane with more open deals than are currently loaded/scrolled into view, **When** the header total is shown, **Then** it still reflects every open deal in the lane, not only the loaded ones.
4. **Given** a deal is moved into or out of a lane, created in a lane, marked won/lost, reopened, or has its value edited, **When** that action completes, **Then** the affected lane's(s') header total updates to reflect the change, without a full page reload.

---

### User Story 2 - Per-lane color accent (Priority: P2)

An admin gives a lane a distinguishing color so the board is easier to visually scan, without that color affecting anything else about how deals are displayed.

**Why this priority**: A visual, glanceable way to tell lanes apart improves board usability, but it's a secondary enhancement to the header — the board is already usable without it, unlike accurate totals.

**Independent Test**: Set a color on one lane and confirm only that lane's header changes appearance; everything else on the board (including individual deal cards) stays visually identical to before.

**Acceptance Scenarios**:

1. **Given** an admin is editing a lane's settings, **When** they choose a color, **Then** that lane's header shows the chosen color as an accent after saving.
2. **Given** a lane has no color configured, **When** the board is viewed, **Then** that lane's header looks exactly as it does today (no accent).
3. **Given** a lane has a color configured, **When** the board is viewed, **Then** no other part of that lane — including individual deal cards — changes appearance because of it.
4. **Given** an admin wants to remove a lane's color, **When** they clear it in settings, **Then** the lane's header returns to its default, unaccented appearance.

---

### User Story 3 - Choosing what a lane's total shows (Priority: P3)

An admin picks, per lane, whether that lane's header shows a count of deals or their total value — whichever is more useful for that particular stage of the pipeline.

**Why this priority**: A sensible default (total value) makes the board useful immediately without this choice; letting admins tune it per lane is a refinement on top of User Story 1.

**Independent Test**: Change a lane's display choice from value to count (or vice versa) and confirm only that lane's header changes to the new format.

**Acceptance Scenarios**:

1. **Given** an admin is editing a lane's settings, **When** they choose "count" or "total value" for that lane, **Then** the lane's header shows only the chosen format after saving (never both at once).
2. **Given** no admin has changed the setting, **When** a lane is viewed, **Then** it shows total value by default.

---

### Edge Cases

- A lane with zero open deals shows a total of zero (or an empty/zero count), not a blank or missing header.
- Won/lost (closed) deals are excluded from both the count and the value total — a lane total reflects only open deals, consistent with "how much is currently in negotiation."
- While a lane's total is being refreshed (initial load, or right after a deal-affecting action), the header shows no loading indicator — it keeps its last known value until the new one is ready, then updates silently.
- If refreshing a lane's total fails (e.g., a network hiccup), there is no dedicated error message — the header simply continues showing its last known value, consistent with how other board actions already handle transient failures.
- Other open browser tabs/sessions do not see a lane's total update live when a different tab makes a change — they see the accurate number the next time they load or refresh the board.
- A lane's color accent does not appear anywhere on that lane's individual deal cards, and does not interact with a card's own visual states (won/lost badge, no-linked-conversation styling, missing-required-field styling).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Each lane MUST display a header total reflecting every open deal in that lane, independent of how many of that lane's deal cards are currently loaded/scrolled into view.
- **FR-002**: A lane's header total MUST exclude won and lost deals, counting/summing only open deals.
- **FR-003**: Each lane MUST have an admin-configurable display choice of either "count" (number of open deals) or "total value" (combined value of open deals), defaulting to "total value" when not explicitly set.
- **FR-004**: A lane MUST NOT show count and total value together — exactly one, per its configured display choice.
- **FR-005**: A lane's header total value MUST be formatted using the account's configured currency.
- **FR-006**: A lane's header total MUST update after any action that changes which deals are open in that lane or their value (a deal moving into/out of the lane, being created in it, marked won/lost, reopened, or having its value edited), without requiring a full board reload.
- **FR-007**: Admins MUST be able to set an optional color accent on each lane from that lane's settings, and clear it back to no accent.
- **FR-008**: A lane with no color configured MUST look exactly as lanes look today (no accent).
- **FR-009**: A lane's color accent MUST be visible only on that lane's own header, and MUST NOT alter the appearance of that lane's (or any other lane's) individual deal cards.
- **FR-010**: A lane's header total MUST show no loading indicator while being refreshed; it continues showing its last known value until an updated one is available.
- **FR-011**: A failure to refresh a lane's header total MUST NOT surface a dedicated error message to the user; the header simply retains its last known value.

### Key Entities

- **Lane (Pipeline Stage)**: A column on the kanban board. Gains two new admin-configurable properties: a display choice for its header total (count or total value) and an optional color accent.
- **Lane Total**: A computed, lane-wide summary (count and/or combined value of open deals) shown in a lane's header, kept accurate independent of pagination and refreshed after deal-affecting actions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A lane's header total is accurate for 100% of that lane's open deals, including lanes where not all deals are currently loaded on screen.
- **SC-002**: After any deal-affecting action (move, create, close, reopen, value edit), the affected lane's header total reflects the change without a page reload, in the same session.
- **SC-003**: Admins can set or clear a lane's color accent and see the change take effect after a single save action, with zero visual change anywhere else on the board.
- **SC-004**: 100% of lanes with no configured color accent remain visually identical to their current (pre-feature) appearance.
- **SC-005**: Admins can switch a lane's header between count and total value display, with the header showing exactly one of the two after each change.

## Assumptions

- "Open" deals are those not yet marked won or lost; this matches the existing status model already used elsewhere on the board.
- The account-wide currency setting used for formatting deal values elsewhere on the board (introduced by the deal-card-customization feature) is reused for lane total-value formatting — no separate currency configuration is introduced by this feature.
- Lane color is a freely chosen color (not a fixed palette), consistent with how label and card-badge colors already work elsewhere in the product.
- Cross-tab/cross-session live sync of lane totals is out of scope — a lane total is refreshed within the tab that performed the action; other tabs see the accurate number on their next load.
- A manual "refresh totals" action is out of scope — every deal-affecting action already triggers a refresh of the relevant lane's total.
