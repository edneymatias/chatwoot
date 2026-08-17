# Feature Specification: Opportunity Activity Log

**Feature Branch**: `040-opportunity-activity-log`

**Created**: 2026-08-17

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 9/14-opportunity-activity-log/spec69.md"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Viewing Opportunity Activity Timeline in Conversation Drawer (Priority: P1)

As a sales agent or manager managing deals on the Kanban board, I want to view a chronological activity timeline for an opportunity directly inside the conversation drawer, so that I have complete visibility into when the opportunity was created, when it moved between stages, when it was won or lost, and which conversations have been linked to it.

**Why this priority**: Core value of the feature. Without a visible timeline, agents have no way to audit deal progression or see historical stage transitions and conversation links.

**Independent Test**: Can be tested by opening the conversation drawer for any opportunity, toggling to the activity panel, and verifying that all recorded events (creation, stage change, won/lost, conversation link) appear with correct human-readable descriptions, actors, and timestamps.

**Acceptance Scenarios**:

1. **Given** an opportunity is selected in the Kanban board, **When** an agent opens the conversation drawer and clicks the Activity Log toggle button, **Then** the drawer view switches from the conversation view to the read-only activity timeline.
2. **Given** an opportunity has undergone stage changes (e.g. from "Lead" to "Negotiation"), **When** viewing the activity timeline, **Then** the stage transition event is displayed showing the previous stage name, new stage name, actor who performed the move, and relative timestamp.
3. **Given** an opportunity was marked as won or lost, **When** viewing the activity timeline, **Then** the win/loss event is displayed showing the actor and relevant details (e.g. stage from which it was closed).
4. **Given** a new conversation is opened or linked to an opportunity, **When** viewing the activity timeline, **Then** a conversation linkage event is displayed showing the conversation identifier and actor.
5. **Given** an agent is viewing the activity timeline, **When** they click the Conversation toggle button, **Then** the drawer switches back to the active conversation view.

---

### User Story 2 - Actor Attribution & Automated Action Identification (Priority: P2)

As a sales agent or administrator, I want to clearly identify whether an opportunity event was performed by a specific team member, an automation rule, or an automated background system task, so that accountability and automation behavior are transparent.

**Why this priority**: Understanding who made a change (human agent vs. automation rule vs. background sync) is crucial for auditability and resolving workflow questions.

**Independent Test**: Can be tested by performing actions as an agent, triggering an automation rule that updates an opportunity, and running a background system action, then verifying that each activity entry displays the appropriate actor name or "System" fallback.

**Acceptance Scenarios**:

1. **Given** an agent manually moves an opportunity or links a conversation, **When** viewing the timeline, **Then** the agent's name is displayed as the actor.
2. **Given** an automation rule changes an opportunity stage or status, **When** viewing the timeline, **Then** the automation rule's name is displayed as the actor.
3. **Given** a background job or system process creates or updates an opportunity without a user session, **When** viewing the timeline, **Then** the actor is displayed as "System" (or localized equivalent).

---

### User Story 3 - Historical Data Backfill & Approximation Transparency (Priority: P3)

As an agent reviewing an opportunity that existed before the activity logging system was deployed, I want pre-existing events to be visible in the timeline with clear indicators for approximate timestamps, so that historical context is available without misrepresenting estimated dates as exact facts.

**Why this priority**: Ensures continuity for existing accounts and pipeline data while maintaining data integrity through honest signaling of approximate historical timestamps.

**Independent Test**: Can be tested by inspecting pre-existing opportunities after the migration and verifying that accurate historical events (creation, past stage changes, conversation links) display normally, while estimated terminal state dates (won/lost) display an "(approximate)" caveat badge.

**Acceptance Scenarios**:

1. **Given** an opportunity created prior to feature deployment, **When** viewing its timeline, **Then** the creation event, historical stage changes, and conversation links are present with their original recorded timestamps.
2. **Given** an opportunity marked as won or lost prior to feature deployment, **When** viewing its timeline, **Then** the won/lost event displays a prominent approximate indicator/badge clarifying that the timestamp is estimated from the last record update.
3. **Given** an opportunity that underwent a historical reopen prior to feature deployment, **When** viewing its timeline, **Then** no speculative reopen event is displayed since reliable timestamp data did not exist.

---

### User Story 4 - Feature Toggle & Drawer Interface Integration (Priority: P4)

As an account administrator or agent in an account where the Opportunities module is disabled, I want the activity log interface elements to remain hidden, so that the user experience is clean and uncluttered when the feature is not active.

**Why this priority**: Prevents broken or irrelevant UI controls from appearing for accounts that do not use the Opportunities/Kanban module.

**Independent Test**: Can be tested by toggling the account-level Opportunities feature flag on and off and verifying the presence or absence of the Activity Log button in the drawer.

**Acceptance Scenarios**:

1. **Given** the Opportunities feature is enabled for an account, **When** an agent opens the opportunity conversation drawer, **Then** the Activity Log toggle button is visible and active.
2. **Given** the Opportunities feature is disabled for an account, **When** an agent interacts with the conversation drawer, **Then** the Activity Log toggle button is hidden.

---

### Edge Cases

- **Zero activities on a deal**: When an opportunity has no recorded activities (e.g. edge case or initial migration state), the panel displays a clean, friendly empty state message rather than a blank or broken screen.
- **Large volume of activity events**: When an opportunity has dozens or hundreds of stage changes and conversations over months, the activity panel scrolls smoothly within the drawer container without overflowing or clipping.
- **Deleted actor or missing entity**: If a user or automation rule associated with an activity was deleted from the system, the timeline gracefully displays the fallback actor name or generic identifier without crashing.
- **Deleted pipeline stage**: If a stage referenced in a historical `stage_changed` event was subsequently deleted, the timeline gracefully falls back to a neutral stage identifier or generic label.
- **Read-only enforcement**: The activity timeline provides no edit, delete, or add controls; activities are strictly immutable records.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST automatically record an activity log entry whenever an opportunity is created, moved between pipeline stages, marked as won, marked as lost, reopened, or linked to a conversation.
- **FR-002**: System MUST persist the following attributes for each activity: account scoping, opportunity reference, event type, actor reference (type and ID, optional), event-specific metadata, and occurrence timestamp.
- **FR-003**: System MUST capture event-specific metadata:
  - For `opportunity_created`: empty metadata.
  - For `opportunity_stage_changed`: previous stage ID and new stage ID.
  - For `opportunity_won` and `opportunity_lost`: previous stage ID, lost reason (when available), and approximate flag (if backfilled).
  - For `conversation_opened`: conversation ID, display ID, and origin flag.
- **FR-004**: System MUST accurately attribute the actor for each event as a User, an Automation Rule, or null (system/background context).
- **FR-005**: System MUST provide a read-only endpoint returning activities for a specific opportunity in reverse chronological order (newest first).
- **FR-006**: System MUST enforce account-level scoping and authorization matching the opportunity access rules for retrieving activities.
- **FR-007**: System MUST provide a toggle button in the Kanban opportunity conversation drawer to switch the drawer content between the conversation view and the activity timeline.
- **FR-008**: System MUST render each activity in the timeline with a distinct icon per event type, localized descriptive text, actor name (or "System" fallback), and relative timestamp.
- **FR-009**: System MUST render a visible caveat badge or tooltip (e.g. "(approximate)") whenever an activity entry has the approximate flag set to true.
- **FR-010**: System MUST include a one-time data migration backfilling historical creation, stage change, and conversation link events with exact timestamps, and historical won/lost events with approximate timestamps.
- **FR-011**: System MUST fully localize all user-facing labels, event descriptions, actor fallbacks, and caveat messages in both English (`en`) and Brazilian Portuguese (`pt-BR`).
- **FR-012**: System MUST hide the activity log toggle button in the conversation drawer when the Opportunities feature is disabled for the current account.

### Key Entities

- **Opportunity Activity (`OpportunityActivity`)**: Represents an immutable chronological event recorded against an opportunity. Attributes include `account_id`, `opportunity_id`, `event_type` (`opportunity_created`, `opportunity_stage_changed`, `opportunity_won`, `opportunity_lost`, `opportunity_reopened`, `conversation_opened`), polymorphic `actor` (`User`, `AutomationRule`, or null), `metadata` (structured JSON payload), `occurred_at` (timestamp), and system timestamps.
- **Opportunity (`Opportunity`)**: The core sales opportunity entity that owns zero or more activities and provides the context for the timeline.
- **Actor**: The initiator of an opportunity event (a team `User`, an `AutomationRule`, or the automated `System`).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of opportunity lifecycle events (creation, stage transition, win, loss, reopen, conversation link) produce an immutable activity record automatically.
- **SC-002**: Users can toggle between the conversation view and activity timeline in the conversation drawer in 1 click.
- **SC-003**: 100% of historical pre-existing opportunities receive backfilled creation, stage change, and conversation link entries, and terminal status entries flagged with approximate indicators.
- **SC-004**: 100% of user-facing timeline copy and caveats are localized in both English (`en`) and Brazilian Portuguese (`pt-BR`).
- **SC-005**: Activity list API returns results ordered by occurrence time in under 200ms for typical opportunity histories.

## Assumptions

- Opportunities feature flag (`opportunities`) governs access to the opportunity activity log within the UI.
- All additions follow the decoupled architecture of the repository (`custom/` module hierarchy and existing extension points) without modifying upstream core (`app/`) or `enterprise/` source files.
- Pagination is not required for v1 given typical opportunity lifecycle event counts per deal; the list renders in reverse chronological order with smooth vertical scrolling.
- Call records and task management events are deferred to future phases and are out of scope for v1.
