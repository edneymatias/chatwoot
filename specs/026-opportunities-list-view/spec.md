# Feature Specification: List View for the Kanban Board

**Feature Branch**: `[###-opportunities-list-view]`

**Created**: 2026-08-08

**Status**: Draft

**Input**: User description: "/speckit-specify @[docs/kanban/ciclo 7/01-list-view/spec8.md]"

## Clarifications

### Session 2026-08-08
- Q: What text should be displayed in the tooltip for the disabled "add opportunity" button? → A: "Coming soon"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Toggle between List and Kanban views (Priority: P1)

As a user, I want to toggle between a list view and a Kanban board so that I can choose the layout that best fits my workflow and scanning preferences.

**Why this priority**: Without the toggle, the list view cannot be accessed.

**Independent Test**: Can be tested by clicking the list and Kanban icons on the new view bar and observing the layout change.

**Acceptance Scenarios**:

1. **Given** I am on the opportunities index, **When** I click the list icon in the view bar, **Then** the opportunities are displayed in a list of cards format instead of the Kanban board, and my preference is saved.
2. **Given** I am in the list view, **When** I reload the page, **Then** the list view is still active because my preference was persisted.
3. **Given** I am in the list view, **When** I click the Kanban icon, **Then** the view switches back to the standard Kanban board.

---

### User Story 2 - View opportunities in a list of cards (Priority: P1)

As a user, I want to see all opportunities across all stages in a single, dense list of cards so that I can quickly scan them without horizontally scrolling through Kanban columns.

**Why this priority**: This is the core value of the list view.

**Independent Test**: Can be tested by switching to list view and verifying that the rows display the correct data (title, contact, assignee, stage, value, status, last activity).

**Acceptance Scenarios**:

1. **Given** I have switched to the list view, **When** I look at the list, **Then** I see opportunities from all stages sorted by creation date descending.
2. **Given** I am viewing the list, **When** I reach the bottom, **Then** I can use the pagination footer to navigate through pages (15 items per page).
3. **Given** I click a row that has an origin conversation, **Then** the conversation drawer opens for that opportunity.
4. **Given** I click a row that does not have an origin conversation, **Then** nothing happens, keeping it read-only.

---

### User Story 3 - View pipeline aggregates (Priority: P2)

As a user, I want to see the total lead count and total value of all opportunities in the pipeline at the top of the view so that I have a quick summary of the pipeline's health.

**Why this priority**: Provides high-level context that currently requires manual summing across Kanban columns.

**Independent Test**: Can be tested by checking the view bar in either Kanban or list view and ensuring the totals match the sum of all columns.

**Acceptance Scenarios**:

1. **Given** I am on the opportunities index (in either view), **When** I look at the view bar, **Then** I see the total count and total currency-formatted value of all open opportunities across all stages.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display an Opportunities View Bar above the board/list content on the opportunities index page.
- **FR-002**: System MUST allow users to toggle between Kanban and list view modes via the view bar.
- **FR-003**: System MUST persist the selected view mode in the browser so it survives page reloads.
- **FR-004**: System MUST display the total lead count and total opportunity value for open opportunities across all stages in the view bar.
- **FR-005**: System MUST display a disabled "add opportunity" button with a "Coming soon" tooltip in the view bar.
- **FR-006**: System MUST display an Opportunity List View when the view mode is set to list.
- **FR-007**: System MUST display title, contact, assignee, stage name, formatted value, status badge, and last-activity timestamp in each list row.
- **FR-008**: System MUST open the conversation drawer when a user clicks a row that has an associated origin conversation.
- **FR-009**: System MUST NOT allow editing stage or status directly from the list view (read-only list).
- **FR-010**: System MUST support standard pagination (15 items per page) with a fixed footer in the list view, instead of infinite scrolling.
- **FR-011**: System MUST retrieve and display opportunities from all stages in a single unified list without stage filtering.
- **FR-012**: System MUST maintain data synchronization between the Kanban view and List view so that updates in one are reflected globally without data duplication.

### Key Entities

- **Opportunity**: Represents a deal or lead, containing fields like title, value, status, assignee, and stage.
- **Pipeline Stage**: Represents a phase in the sales process.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can toggle between Kanban and list views, with their preference persisting across page reloads.
- **SC-002**: The list view correctly displays opportunities across all stages, supporting standard pagination (15 items per page) for large datasets.
- **SC-003**: Total lead count and value are accurately calculated and displayed in the view bar based on the loaded pipeline stages.
- **SC-004**: Clicking a row with an associated conversation successfully opens the conversation drawer.
- **SC-005**: The introduction of the list view does not break or duplicate data in the existing Kanban board view.

## Assumptions

- Target users are on modern browsers that support standard browser storage capabilities.
- The list view order is fixed to creation date descending, with sorting/filtering deferred to a future phase.
- The "add opportunity" button is intentionally non-functional in this phase.
- The existing per-stage Kanban board functionality remains functionally unchanged.
