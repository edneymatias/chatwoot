# Feature Specification: Kanban Search and Filter

**Feature Branch**: `[028-kanban-search]`

**Created**: 2026-08-08

**Status**: Draft

**Input**: User description: "/speckit-specify @[docs/kanban/ciclo 7/02-search/spec35.md]"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Search Opportunities (Priority: P1)

As a user, I want to search for specific opportunities by title or contact name so I can quickly locate deals I'm working on.

**Why this priority**: Users need a fast way to find specific opportunities when the board has many deals.

**Independent Test**: Can be fully tested by entering text in the search bar and verifying only matching opportunities are displayed.

**Acceptance Scenarios**:

1. **Given** a list of opportunities, **When** I type a matching string in the search box, **Then** only opportunities with matching titles or contact names are shown.
2. **Given** a filtered view, **When** I clear the search box, **Then** all opportunities in that view are restored.

---

### User Story 2 - Filter by Assignee, Status, and Custom Attributes (Priority: P1)

As a user, I want to filter opportunities by assignee, status, and list-type custom attributes so I can focus on specific subsets of deals (e.g., my open deals, or deals in a specific segment).

**Why this priority**: Focus is essential for sales users who only want to see deals relevant to their immediate tasks.

**Independent Test**: Can be fully tested by selecting values from the filter dropdowns and confirming the list/board correctly updates.

**Acceptance Scenarios**:

1. **Given** a list of opportunities, **When** I select an assignee and a status, **Then** only opportunities matching both filters are displayed.
2. **Given** active filters on the board, **When** I navigate to another part of the application and return, **Then** the filters are reset to their default unselected state.

---

### User Story 3 - Sort List View (Priority: P2)

As a user, I want to sort opportunities in both Kanban and List views by value (high to low / low to high) or last activity so I can prioritize which deals to work on next.

**Why this priority**: Helps in prioritizing deals, but secondary to basic filtering and search.

**Independent Test**: Can be fully tested by changing the sort dropdown in the List view and verifying the order updates accordingly.

**Acceptance Scenarios**:

1. **Given** the List view, **When** I select "Value (high to low)", **Then** opportunities are ordered by their value descending.
2. **Given** the Kanban view, **When** I change the sort dropdown to "Value (high to low)", **Then** opportunities within each Kanban column are ordered by their value descending.

### Edge Cases

- **Search terms with special characters**: The system MUST escape special characters using standard SQL ILIKE sanitization (`sanitize_sql_like`), treating them as literal characters.
- **Deleted or deactivated assignee**: The system MUST safely return an empty result set (zero opportunities) without throwing an error.
- **Zero results in a Kanban column**: The system MUST keep the Kanban column visible but empty, maintaining the standard board structure.
- **Deleted custom attribute filtering**: The system MUST safely ignore the invalid attribute or return zero results without throwing an error.
## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow filtering opportunities by a search term that performs a case-insensitive partial match on the opportunity title or associated contact name.
- **FR-002**: System MUST allow filtering opportunities by assignee.
- **FR-003**: System MUST allow filtering opportunities by status.
- **FR-004**: System MUST allow filtering opportunities by custom attributes of type "list".
- **FR-005**: System MUST allow sorting opportunities in both Kanban and List views by value (ascending/descending) and last activity. Default sort MUST be created date descending.
- **FR-006**: System MUST support concurrent application of multiple filters (AND logic).
- **FR-007**: System MUST integrate all filters (including Stage) into a unified Query Builder popup, accessible from both Kanban and List views.
- **FR-008**: System MUST maintain filter and sort state as local view state, resetting automatically when the user navigates away from the opportunities page.
- **FR-009**: System MUST re-fetch data starting from page 1 whenever filters or sort criteria are changed.
- **FR-010**: System MUST apply filters simultaneously to Kanban and List views without introducing separate filtered board states.

### Key Entities

- **Opportunity**: Represents the deal, containing title, status, value, and timestamps.
- **Contact**: The associated person for the opportunity, whose name is searchable.
- **Custom Attribute**: List-type definitions that provide additional filtering dimensions for opportunities.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can locate specific opportunities via search or filters within 3 seconds of typing/selecting.
- **SC-002**: Filter operations complete and render updated results without page reload.
- **SC-003**: Navigation away from and back to the opportunities page correctly yields a 100% reset state with zero residual filters applied.

## Assumptions

- Users have a stable internet connection for responsive API requests during filtering.
- Filtering by custom attributes is restricted only to those configured with the "list" display type.
- Advanced value range filtering is out of scope. Global sorting applies equally to both List view and inside Kanban columns.
- The existing filter patterns established in the `contacts` module will adequately support opportunities.
