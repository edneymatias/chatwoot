# Feature Specification: Pipeline Stage Reordering

**Feature Branch**: `009-pipeline-stage-reordering`

**Created**: 2026-08-03

**Status**: Draft

**Input**: User description: "no nosso módulo de kanban, no início eu deixei de lado a possibilidade de ordenar os stages no pipeline stage. a tela já esta pronta, suporta drag and drop, mas não reordena. preciso implementar essa lógica."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reorder pipeline stages from settings (Priority: P1)

An account admin managing pipeline stages drags a stage to a new position in the Pipeline Stages settings list and expects that new order to be saved permanently, so the sequence reflects how the sales/support process actually flows.

**Why this priority**: This is the core capability requested — the drag-and-drop interaction already exists visually, but the new order is not reliably saved, making the feature unusable today.

**Independent Test**: Can be fully tested by dragging a stage to a different position in the Pipeline Stages settings list, reloading the page, and confirming the stage remains in its new position and all other stages keep a consistent, non-conflicting order.

**Acceptance Scenarios**:

1. **Given** an account with multiple pipeline stages in a known order, **When** an admin drags a stage from the end of the list to the beginning, **Then** the stage appears first and every other stage shifts down by one position, both immediately and after reloading the page.
2. **Given** an account with multiple pipeline stages, **When** an admin drags a stage from the beginning to the middle of the list, **Then** the stages between the old and new position shift accordingly and the overall order remains unique and gapless.
3. **Given** an admin has just reordered stages, **When** any other user in the same account loads the Pipeline Stages settings or the Kanban board, **Then** they see the same, updated stage order.

---

### User Story 2 - Kanban board reflects the configured stage order (Priority: P2)

A support/sales agent viewing the Kanban board expects the columns to appear in the same order that was configured in Pipeline Stage settings, since the columns represent the stages of the pipeline.

**Why this priority**: The reordering capability only delivers value if it is visible where agents actually work day-to-day (the Kanban board), not just in the settings screen.

**Independent Test**: Can be fully tested by reordering stages in settings, then opening the Kanban board and confirming the columns appear left-to-right in the newly configured order.

**Acceptance Scenarios**:

1. **Given** stages have been reordered in settings, **When** an agent opens the Kanban board, **Then** the columns are displayed in the same order as configured, without requiring any additional manual action.

---

### User Story 3 - Reorder failures do not corrupt the pipeline (Priority: P3)

An admin attempting to reorder stages while offline or during a backend error expects the list to recover gracefully rather than end up in a broken or inconsistent order.

**Why this priority**: Prevents data integrity issues (duplicate or missing positions) and confusing UI states, but is a safeguard rather than the primary value delivered by the feature.

**Independent Test**: Can be fully tested by simulating a failed save request during a drag-and-drop reorder and confirming the list visually reverts to its last known-good order with an error message, and that no stage ends up sharing a position with another.

**Acceptance Scenarios**:

1. **Given** an admin drags a stage to a new position, **When** the save request fails, **Then** the list reverts to the previous order, an error message is shown, and no stage positions are left duplicated or inconsistent.

---

### Edge Cases

- What happens when a stage is dragged and dropped back into its original position (no actual change)? No update should be sent, and no position values should change.
- What happens when there is only one pipeline stage? Reordering controls should have no effect since there is nothing to reorder against.
- What happens when two admins reorder stages at nearly the same time? The system must not end up with two stages sharing the same position; the later save should win and produce a consistent, gapless order.
- What happens when a stage is dragged to the exact same index it started in but the list re-renders? No unnecessary save request should be triggered.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST persist the new order of pipeline stages when an admin drags a stage to a different position in the Pipeline Stages settings list.
- **FR-002**: System MUST update the position of every pipeline stage affected by a reorder (not only the stage that was dragged), so the resulting order is unique, sequential, and gapless within the account.
- **FR-003**: System MUST reflect the persisted stage order consistently across every screen that lists pipeline stages, including the Pipeline Stages settings list and the Kanban board columns.
- **FR-004**: System MUST scope pipeline stage ordering to a single account; reordering stages in one account MUST NOT affect stage order in any other account.
- **FR-005**: System MUST restrict the ability to reorder pipeline stages to users who already have permission to manage pipeline stages, consistent with existing pipeline stage management permissions.
- **FR-006**: System MUST revert the displayed order and inform the user when a reorder action fails to save, without leaving stages in a duplicated or inconsistent position state.
- **FR-007**: System MUST avoid sending or persisting a reorder update when a stage is dropped back into its original position.

### Key Entities

- **Pipeline Stage**: Represents a step in the kanban pipeline (e.g., "Leads Recebidos", "Em Contato"). Belongs to an account and has a position that determines its display order relative to other stages in the same account. Reordering changes the position of the moved stage and of any other stages between its old and new position.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of drag-and-drop reorder actions in Pipeline Stages settings persist correctly, so the same order is shown after a page reload.
- **SC-002**: The Kanban board column order matches the configured Pipeline Stages settings order in 100% of cases, with no manual refresh workaround required beyond a normal page load.
- **SC-003**: After any sequence of reorder actions, no account ever ends up with two pipeline stages sharing the same position.
- **SC-004**: A failed reorder save is visibly communicated to the admin and the on-screen order recovers to a valid state within the same interaction, without requiring a page reload.

## Assumptions

- Reordering is available only to users who already have permission to manage pipeline stages (the same permission that currently gates creating, editing, and deleting stages); no new role or permission is introduced.
- Reordering applies to the full list of an account's pipeline stages; there is no separate grouping or filtering of stages to reorder independently.
- The existing drag-and-drop interaction and visual list in Pipeline Stages settings is the entry point for this feature; no new UI surface for reordering is introduced.
- Real-time propagation of a reorder to other users' already-open sessions (e.g., via WebSocket) is out of scope; users see the updated order on their next page load or data refresh.
