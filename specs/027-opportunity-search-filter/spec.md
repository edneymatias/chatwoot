# Feature Specification: Opportunity Search and Filter

**Feature Branch**: `[027-opportunity-search-filter]`

**Created**: 2026-08-08

**Status**: Draft

**Input**: User description: "/speckit-specify docs/kanban/ciclo 7/02-search/spec35.md"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find Specific Opportunity by Name (Priority: P1)

As a sales agent, I want to search opportunities by title or contact name so I can quickly locate a specific deal without scrolling.

**Why this priority**: Basic keyword search is the most common and fastest way to find a known item.

**Independent Test**: Can be tested by typing a partial or full title in the search box and verifying only matching opportunities appear.

**Acceptance Scenarios**:

1. **Given** I am on the Kanban or list view, **When** I type "Acme" in the search input, **Then** the view updates to show only opportunities where the title or contact contains "Acme".

---

### User Story 2 - Filter Opportunities by Criteria (Priority: P2)

As a sales manager, I want to filter opportunities by assignee, stage, or value range so I can focus on specific subsets of my pipeline.

**Why this priority**: Essential for pipeline management and reporting on specific segments.

**Independent Test**: Can be tested by selecting an assignee and stage in the filter controls and verifying the results match.

**Acceptance Scenarios**:

1. **Given** I am on the view, **When** I apply a filter for "Assignee: John" and "Status: Open", **Then** I only see open opportunities assigned to John.

---

### User Story 3 - Sort Opportunities (Priority: P3)

As a sales agent, I want to sort opportunities by value or last activity so I can prioritize my work effectively.

**Why this priority**: Helps agents determine which deals need immediate attention.

**Independent Test**: Can be tested by selecting "Sort by Value (High to Low)" and verifying the list reorders accordingly.

**Acceptance Scenarios**:

1. **Given** I have multiple opportunities, **When** I sort by "Value (Descending)", **Then** the opportunity with the highest monetary value appears first.

## Edge Cases

- What happens when a search query yields no results? (Show a clear empty state message).
- What happens if invalid values are manually entered in URL parameters for filters? (Fallback gracefully to default/unfiltered state).
- How does system handle sorting when opportunities have identical values for the sort key? (Secondary sort by created_at or ID).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a search input to query opportunities by title and contact name.
- **FR-002**: System MUST provide filter controls for assignee, stage, value range, and status.
- **FR-003**: System MUST provide sort options including: by value, by last activity, and by stage.
- **FR-004**: System MUST apply search, filter, and sort operations to [NEEDS CLARIFICATION: Both Kanban and List views, or just List view?].
- **FR-005**: System MUST [NEEDS CLARIFICATION: Update existing views in-place or open a separate results view?].
- **FR-006**: System MUST [NEEDS CLARIFICATION: Persist filter/sort state in URL params/localStorage, or reset on navigation?].

### Key Entities *(include if feature involves data)*

- **Opportunity**: The primary record being searched, filtered, and sorted.
- **User**: Used for filtering opportunities by assignee.
- **Contact**: Used for searching opportunities by associated person/company.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can locate a specific opportunity by name in under 5 seconds.
- **SC-002**: Filter and search queries return results in under 500ms on datasets of up to 10,000 opportunities.
- **SC-003**: 90% of users can successfully apply a combination of filters and sorting without assistance.

## Assumptions

- Search uses standard database capabilities (e.g. ILIKE) and no external search engine is required for MVP.
- The same filter criteria apply logically regardless of which view is active.
- Pagination or infinite scroll will handle large result sets after filtering.
