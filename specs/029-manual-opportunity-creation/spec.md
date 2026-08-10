# Feature Specification: Manual Opportunity Creation and Conversation Start

**Feature Branch**: `029-manual-opportunity-creation`

**Created**: 2026-08-09

**Status**: Draft

**Input**: User description: "/speckit-specify @[docs/kanban/ciclo 7/03-manual-opportunity-creation/spec36.md]"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create Opportunity Manually (Priority: P1)

Users need to create an opportunity independently of a specific kanban board column.

**Why this priority**: Without this, users cannot create opportunities unless they are on the Kanban board view, forcing a specific workflow that might not be desired.

**Independent Test**: Can be fully tested by navigating to the Opportunities list view and clicking "add opportunity" to create an opportunity without a pre-selected stage.

**Acceptance Scenarios**:

1. **Given** a user is on the Opportunities list view, **When** they click "add opportunity", **Then** a modal opens without a default stage selected.
2. **Given** the opportunity creation modal is open with no default stage, **When** the user fills out the required fields and selects a stage, **Then** the opportunity is created successfully.

---

### User Story 2 - Start Conversation from an Opportunity (Priority: P1)

Users need to initiate a conversation for opportunities that have no conversation linked. Currently, conversation-less opportunities are dead ends.

**Why this priority**: Unblocks users from engaging with contacts directly from an opportunity that was created manually or via automation without an initial conversation.

**Independent Test**: Can be tested by creating an opportunity without a conversation, hovering over it to see the action button, and starting a conversation from there.

**Acceptance Scenarios**:

1. **Given** an opportunity with no linked conversation, **When** the user hovers over its Kanban card, **Then** they see a quick action button to start a conversation.
2. **Given** a conversation-less opportunity row in the List View, **When** the user views it, **Then** they see an action to start a conversation.
3. **Given** the start conversation flow is opened via the opportunity quick action, **When** a new conversation is created, **Then** the opportunity is immediately linked to the new conversation without a page reload, and the normal clickable card/row behavior is enabled.

### Edge Cases

- What happens when a user attempts to link a conversation to an opportunity that already has one? (The system rejects the update and retains the original conversation).
- What happens if the start conversation flow is aborted without creating a conversation? (The opportunity remains unlinked, and the quick action button remains visible).
- What happens to the action button once a conversation is successfully linked? (It disappears, and the entire card/row becomes clickable).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow linking a conversation to an opportunity after the opportunity has been created.
- **FR-002**: System MUST prevent changing the linked conversation of an opportunity once it has been set.
- **FR-003**: System MUST provide a general entry point to create an opportunity from the Opportunities List view, independent of a specific pipeline stage.
- **FR-004**: System MUST require users to select an existing contact when creating an opportunity (inline contact creation is not supported).
- **FR-005**: System MUST provide a quick action on unlinked opportunities to start a new conversation with the associated contact.
- **FR-006**: System MUST automatically link the newly created conversation to the opportunity.
- **FR-007**: System MUST display the "start conversation" action on Kanban cards only for unlinked opportunities.
- **FR-008**: System MUST display the "start conversation" action on List View rows only for unlinked opportunities.
- **FR-009**: System MUST immediately make the opportunity card/row fully interactive once a conversation is linked, without requiring a page refresh.

### Key Entities

- **Opportunity**: Represents a deal. Updated to allow its linked conversation reference to be mutated only when it is currently empty.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can successfully create an opportunity from the list view (without a preset stage) in 100% of attempts where validation passes.
- **SC-002**: Users can successfully initiate and link a new conversation from an existing unlinked opportunity.
- **SC-003**: The UI updates immediately upon linking a conversation, requiring zero manual page refreshes.

## Assumptions

- We assume un-linking or re-linking an opportunity's conversation is out of scope.
- We assume a combined "create opportunity + start conversation" flow is intentionally out of scope and should remain separate actions.
- We assume there is no need for a dedicated "detail view" for conversation-less opportunities; actions on the card/row are sufficient.
