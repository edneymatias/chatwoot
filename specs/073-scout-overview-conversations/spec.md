# Feature Specification: Scout Overview — Recent Conversations List

**Feature Branch**: `073-scout-overview-conversations`

**Created**: 2026-09-16

**Status**: Draft

**Input**: User description: "Scout Overview recent conversations list embedded at the bottom of the Scout Overview page, displaying contact, start time, duration, message count, and status badge (Qualified, Disqualified, Abandoned, In Progress, Transferred without opportunity) with status filter pills, pagination, and row click opening the full conversation in a new tab."


## Clarifications

### Session 2026-09-16

- Q: Confirmamos que uma conversa é classificada como "In Progress" enquanto não atingir um dos quatro desfechos terminais (Qualified, Disqualified, Abandoned via resgate, ou Transferred without opportunity)? (FR-005) → A: "In Progress" representa qualquer conversa ativa tratada pelo Scout que ainda não alcançou Qualified, Disqualified, Abandoned (estágio de resgate pós-backoff de inatividade) ou Transferred without opportunity.
## User Scenarios & Testing *(mandatory)*

### User Story 1 — View Scout Recent Conversations with Status Classification (Priority: P1)

As an operator or commercial manager, when viewing the Scout Overview page, I want to see a paginated list of recent conversations handled by the selected Scout, showing contact identity, start timestamp, duration, total message count, and funnel outcome status, filterable by status pills with counts, so that I can audit conversation-by-conversation behavior and lead disposition without navigating away to the Kanban board or Inbox.

**Why this priority**: This is the foundational capability of the feature. Without the list and its classification into the five funnel outcomes, operators have no granular visibility into how individual conversations unfolded or why they reached their respective dispositions.

**Independent Test**: Can be tested independently by populating conversations handled by a Scout covering all five outcome states (Qualified, Disqualified, Abandoned, In Progress, and Transferred without opportunity) within a selected period, and verifying that the table displays contact, start time, duration, message count, and appropriate status badges, while honoring status filter pills and period selections.

**Acceptance Scenarios**:

1. **Given** a Scout with handled conversations in the selected period covering the five status outcomes, **When** the operator opens the Scout Overview page, **Then** a "Recent Conversations" table is displayed at the bottom of the page showing each conversation's contact identity, start timestamp, conversation duration, total message count (lead + Scout), and corresponding status badge.
2. **Given** the Recent Conversations table is displayed, **When** the operator clicks a status filter pill (e.g., "Abandoned"), **Then** the table filters to show only conversations matching that outcome, and the pill displays the accurate count of matching conversations for the active period.
3. **Given** more than 25 conversations exist for the selected filter and period, **When** the operator clicks the next page control in the pagination bar, **Then** the next 25 conversations are loaded dynamically without triggering a full page reload.
4. **Given** the operator changes the period selector at the top of the Overview page, **When** the new period takes effect, **Then** the Recent Conversations table reloads to reflect conversations within the updated time window, maintaining alignment with the top-level metric cards.
5. **Given** a conversation where the Scout performed a handoff to a human agent without any sales opportunity being created or linked (e.g., non-commercial inquiry or explicit user request for a human), **When** the conversation is listed in the table, **Then** its status badge displays "Transferred without opportunity" with neutral visual styling (e.g., gray), and is never categorized as Disqualified or styled in a negative/error color.

---

### User Story 2 — Open Full Native Conversation History from Row (Priority: P2)

As an operator reviewing the Recent Conversations list, when I identify a conversation of interest (such as an unexpected abandonment or a qualification with an unusually high message count), I want to click the row to open the complete, native conversation view in a new tab, so that I can review the full transcript and determine whether operational intervention or follow-up is necessary.

**Why this priority**: Viewing summary rows is valuable for identifying patterns, but taking action or investigating anomalies requires reading the authentic message exchange. This depends directly on the list existing (User Story 1).

**Independent Test**: Can be tested independently by clicking a conversation row in a populated Recent Conversations table and verifying that a new browser tab opens pointing to the native conversation interface with the complete message history, leaving the Overview page state intact.

**Acceptance Scenarios**:

1. **Given** a populated Recent Conversations table, **When** the operator clicks anywhere on a conversation row, **Then** the full native conversation view opens in a new browser tab displaying the complete transcript and existing conversation actions.
2. **Given** a conversation record whose underlying conversation ID is invalid, missing, or blocked by the browser, **When** the operator attempts to open it from the table, **Then** the system presents an informative unavailable/error notification rather than navigating to a broken page or crashing the Overview interface.

---

### Edge Cases

- **Zero conversations in period or status filter**: When no conversations match the selected Scout, period, or status pill, the table displays an informative empty state layout (explaining that no conversations match the current criteria) rather than a blank space or broken table layout.
- **Single-message conversation**: When a conversation contains only a single message (e.g., lead initiated contact but no response was exchanged), the duration column displays a neutral dash placeholder (" — ") rather than failing or reporting an inaccurate zero-minute duration.
- **Status change during session**: If a conversation's status evolves (e.g., transitions from In Progress to Qualified) while the operator is viewing the table, the static paginated view preserves consistency for the current view and reflects the updated outcome upon next filter click or page refresh.
- **Scout switch in multi-Scout accounts**: When an account has multiple Scouts and the operator switches the top-level Scout selector, the Recent Conversations table instantly clears and reloads conversations exclusively for the newly selected Scout.
- **Long contact names or phone numbers**: Contact identities with extensive character length truncate cleanly with standard text truncation to prevent row stretching or horizontal layout breaks.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST embed a dedicated "Recent Conversations" section at the bottom of the Scout Overview page, positioned below the summary metric cards and funnel distribution charts.
- **FR-002**: The Recent Conversations section MUST provide a status filter bar featuring six options: "All", "Qualified", "Disqualified", "Abandoned", "In Progress", and "Transferred without opportunity".
- **FR-003**: Each status filter pill MUST display the count of conversations matching that status within the currently selected period.
- **FR-004**: The table MUST present five distinct columns for each conversation:
  1. Contact identity (name, identifier, or channel handle)
  2. Start timestamp (formatted with date and time)
  3. Duration (elapsed time between first and last message)
  4. Messages count (total number of incoming and outgoing messages)
  5. Status badge (visual indicator reflecting the conversation's funnel disposition)
- **FR-005**: The system MUST classify each handled conversation into exactly one of five mutually exclusive statuses based on its outcome:
  - **Qualified**: An opportunity associated with the conversation reached the Scout's configured qualified stage.
  - **Disqualified**: An opportunity associated with the conversation reached the Scout's configured unqualified stage.
  - **Abandoned**: An opportunity associated with the conversation reached the Scout's configured rescue/inactivity stage (e.g., via follow-up backoff exhaustion).
  - **In Progress**: The conversation is actively handled by the Scout and has not reached any terminal outcome stage (whether an opportunity is in its initial or non-terminal stage, or not yet created while conversation status remains pending).
  - **Transferred without opportunity**: The conversation underwent a handoff to a human agent, but no opportunity was created or linked to the conversation (conversation status is not pending and no opportunity exists).
- **FR-006**: The "Transferred without opportunity" status badge MUST use a neutral visual treatment (e.g., slate/gray) and MUST NOT be styled or grouped as a failure or disqualification.
- **FR-007**: Conversation duration MUST be computed as the elapsed time between the first and last message recorded in the conversation. When a conversation contains only one message, duration MUST be rendered as " — ".
- **FR-008**: Message count MUST calculate the total sum of messages in the conversation exchange, including both lead-sent and Scout-sent messages.
- **FR-009**: The table MUST synchronize with the Scout selector and Period selector from the top of the Overview page. Changing either selector reloads the conversation list and status pill counts for the active Scout and period without requiring a full page refresh.
- **FR-010**: The table MUST implement standard page-based pagination with 25 records per page, displaying total item counts, current page indicator, and previous/next page controls.
- **FR-011**: Conversations MUST be ordered chronologically by start timestamp descending (most recent conversations first) by default.
- **FR-012**: Clicking a conversation row MUST open the native conversation interface in a new browser tab, allowing access to the complete conversation history.
- **FR-013**: When no conversations match the active filters, the table MUST display an informative empty state instead of an empty grid or broken layout.
- **FR-014**: If an underlying conversation record is deleted or inaccessible (e.g., missing conversation ID or window popup blocked), the application MUST handle the action gracefully with an error or warning notice, preventing application crashes.
- **FR-015**: Access to the Recent Conversations table and its data MUST adhere to the standard Scout Overview authorization model, allowing access to any authenticated account member (agent or administrator).

### Key Entities

- **Scout**: The AI agent entity responsible for handling conversations across configured inboxes, with configured qualified, unqualified, and rescue outcome stages.
- **Handled Conversation**: A communication thread created in an inbox assigned to the Scout within the active period, carrying a contact identity, exchange timestamps, message volume, and an associated outcome disposition.
- **Contact**: The individual or external user communicating with the Scout through an inbox channel.
- **Conversation Status / Funnel Disposition**: The classified resolution state of the conversation (Qualified, Disqualified, Abandoned, In Progress, or Transferred without opportunity).
- **Opportunity**: The commercial deal record created or linked during the conversation, whose stage determines the funnel outcome.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can view and review recent conversations, verify their outcomes, and assess individual interactions within 15 seconds of opening the Overview page.
- **SC-002**: Switching status filter pills or navigating pagination pages loads and displays the requested conversation list within 1 second on account datasets containing up to 10,000 conversations.
- **SC-003**: 100% of conversations that undergo handoff without an opportunity are classified as "Transferred without opportunity" with neutral visual styling, with 0% erroneously categorized as Disqualified.
- **SC-004**: Clicking a conversation row successfully opens the full native conversation in a new tab in 100% of valid test cases.
- **SC-005**: The table strictly isolates data by Scout and account; 0% of displayed conversations leak from other Scouts or unassociated accounts.

## Assumptions

- The Scout Overview page shell, top-level Scout selector, and period selector are established in Phase 30 (Feature 072); this feature builds directly upon that page structure.
- Status classification leverages existing `Opportunity`, `OpportunityConversation`, `Conversation`, and `Message` relationships; no new database tables or background aggregation jobs are introduced.
- Clicking a conversation opens the existing Chatwoot native conversation URL (`/app/accounts/:account_id/conversations/:conversation_id`) in a new browser tab; no custom chat viewer is built.
- Table ordering is fixed to most recent first; column re-sorting is out of scope for this initial delivery.
- Real-time event streaming (e.g., live updates via WebSockets) is out of scope; pagination and filtering query state on demand.
- User-facing text and status labels are provided synchronously in both English (`en.json`) and Brazilian Portuguese (`pt_BR.json`), adhering to repository internationalization requirements.
