# Feature Specification: Multi-Conversation Opportunity Lifecycle

**Feature Branch**: `039-multi-conversation-opportunities`

**Created**: 2026-08-17

**Status**: Draft

**Input**: User description: "na definição inicial associamos única conversa a oportunidade. uma conversa é responsavel pela criação de uma oportunidade. a conversa tem um ciclo de vida diferente da oportunidade. ela pode se encerrar antes que a oportunidade chegue ao estágio de perdido/ganho. de forma complementar conseguimos criar uma oportunidade sem uma conversa associada. no card aparece um botão próprio para iniciar uma conversa para aquela oportunidade. a ideia aqui é fechar o ciclo: quando uma conversa que iniciou uma oporptunidade for fechada, a oportunidade ficará sem uma conversa associada e novamente o botão de iniciar conversa ficará disponivel para que uma nova conversa seja iniciada. na prática, estamos dizendo que agora uma oportunidade terá uma ou mais conversas associadas, mas sempre no máximo uma conversa aberta. inclusive, se ao clicar em uma nova conversa no card e houver uma conversa aberta, o sistema poderá avisar dizenod perguntando se quer associar com essa conversa ou abrir uma nova."

## Clarifications

### Session 2026-08-17

- Q: If a contact has an open conversation that is already actively associated with another opportunity, can that same conversation be linked to this opportunity as its active conversation? → A: Exclusive — an open conversation can be the active conversation of at most one opportunity at a time (if already linked, the prompt warns the agent or offers to transfer the active link).
- Q: When an opportunity is moved to a terminal stage (Won or Lost) while a conversation is still open, what should happen to that conversation's association? → A: Keep active — the conversation remains actively associated with the won/lost opportunity until the conversation itself is resolved.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Conversation Detachment on Closure (Priority: P1)

As a sales agent, when a customer conversation concludes and is marked as resolved, I want the related opportunity to remain active in its current pipeline stage while freeing up the opportunity's active conversation slot, so that I can re-engage the customer in a new conversation later without losing the deal context.

**Why this priority**: Solves the core lifecycle mismatch where closing a chat thread previously broke or permanently locked the opportunity's ability to receive new messages or initiate conversations.

**Independent Test**: Create an opportunity linked to an active conversation. Resolve the conversation in Chatwoot. Verify the opportunity stays in its pipeline stage, the active conversation indicator transitions to unlinked/idle, and the "Start Conversation" button appears on the card.

**Acceptance Scenarios**:

1. **Given** an opportunity is linked to an open conversation, **When** the conversation is resolved (closed), **Then** the opportunity retains all its pipeline, value, and contact data, but is marked as having no active conversation, and the card displays the "Start Conversation" action button.
2. **Given** an opportunity whose previous conversation was resolved, **When** viewing the opportunity card on the Kanban board, **Then** the card clearly indicates that no active conversation is ongoing and presents the action to initiate a conversation.

---

### User Story 2 - Smart Conversation Initiation & Linking (Priority: P1)

As a sales agent viewing an opportunity card without an active conversation, when I click "Start Conversation", I want the system to check if the contact already has an open conversation and prompt me to either link that existing conversation or start a new one, so that I don't create duplicate conversations unnecessarily.

**Why this priority**: Essential to provide a seamless interaction flow when agents want to resume communication from the Kanban board, preventing fractured chat histories with the same contact.

**Independent Test**: 
- Test A: Click "Start Conversation" on a card whose contact has an existing open conversation; verify a dialog asks whether to link the existing conversation or create a new one.
- Test B: Click "Start Conversation" on a card whose contact has no open conversations; verify it directly opens the new conversation flow.

**Acceptance Scenarios**:

1. **Given** an opportunity has no active conversation and its contact has an existing open conversation, **When** the agent clicks "Start Conversation" on the card, **Then** a modal/prompt appears asking if the agent wants to "Link existing open conversation" or "Start a new conversation".
2. **Given** the prompt modal is displayed, **When** the agent chooses "Link existing open conversation", **Then** that conversation is associated with the opportunity as its active conversation and the card updates to link to it. If that conversation was actively linked to another opportunity, the user is alerted to confirm transferring the active link.
3. **Given** the prompt modal is displayed, **When** the agent chooses "Start a new conversation", **Then** a new conversation flow is launched for the contact and automatically associated as the active conversation of this opportunity upon creation.
4. **Given** an opportunity has no active conversation and the contact has no open conversations, **When** the agent clicks "Start Conversation" on the card, **Then** the system directly launches the new conversation flow without extra prompts.

---

### User Story 3 - Multi-Conversation History in Opportunity Details (Priority: P2)

As a sales agent or manager reviewing an opportunity in the details drawer, I want to see the full timeline of all conversations associated with this opportunity over its entire lifecycle, so that I have complete context of past discussions, negotiations, and resolutions.

**Why this priority**: Ensures that decoupling the active conversation does not lose historical context, giving full visibility into multi-touch sales cycles.

**Independent Test**: Open an opportunity that has had two past closed conversations and one active conversation. Verify that all three conversations appear in the opportunity's conversation history section with status indicators, creation dates, and clickable links to view messages.

**Acceptance Scenarios**:

1. **Given** an opportunity has been associated with multiple conversations across its lifecycle, **When** the agent opens the opportunity details/drawer, **Then** a conversation history section lists all associated conversations (both past closed conversations and current active conversation if present).
2. **Given** the list of associated conversations, **When** the agent clicks on any past or current conversation entry, **Then** the agent can inspect or navigate to that conversation.

---

### User Story 4 - Single Active Conversation Constraint (Priority: P2)

As a sales agent, I want the system to enforce that an opportunity has at most one active (open) conversation at any given time, so that communication context is clear and unambiguous.

**Why this priority**: Prevents conflicting states and ensures predictable card actions (e.g., clicking the card opens the single active conversation, or displays the start button if none is active).

**Independent Test**: Attempt to associate a second open conversation to an opportunity that already has an open conversation, verifying that the system requires resolving or replacing the current active association.

**Acceptance Scenarios**:

1. **Given** an opportunity already has an active open conversation, **When** viewing the opportunity card or details, **Then** the action button directs to the active conversation rather than showing "Start Conversation".
2. **Given** an opportunity already has an active open conversation, **When** a new conversation is initiated and linked for that opportunity, **Then** the previous active conversation is unlinked from the active slot (remaining in history) or must be closed before replacing.

---

### Edge Cases

- **Contact with multiple open conversations across channels/inboxes**: If a contact has multiple open conversations, the prompt allows selecting which open conversation to link.
- **Conversation already linked to another opportunity**: If an open conversation is already the active conversation of another opportunity, the prompt clearly displays the other deal name and requires explicit transfer confirmation before moving the active link.
- **Reopening a resolved conversation**: If a previously closed conversation linked to an opportunity is reopened by the customer or agent:
  - If the opportunity currently has no active conversation, the reopened conversation re-attaches as the active conversation.
  - If the opportunity already has another active conversation, the reopened conversation remains in history but does not overwrite the current active conversation.
- **Opportunity marked Won/Lost while conversation is open**: The active conversation association remains intact and active until the conversation itself is resolved (supporting post-sale onboarding, delivery, or resolution chats), maintaining independent lifecycles.
- **Deleting a conversation**: If a conversation in the opportunity's history is deleted, the opportunity remains intact and the deleted conversation is safely removed from the association history.
- **Manual Opportunity creation without contact**: Opportunity creation requires a contact; when starting a conversation from such an opportunity, the contact's inbox channels determine available options.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST support associating multiple conversations to a single opportunity over the opportunity's entire lifecycle.
- **FR-002**: An opportunity MUST have at most ONE active (open) conversation associated at any given time.
- **FR-003**: When an opportunity's active conversation is resolved (closed), the system MUST automatically release the active conversation slot on the opportunity while keeping the closed conversation in the opportunity's association history.
- **FR-004**: When an opportunity has no active conversation, the opportunity card on the Kanban board MUST display a "Start Conversation" action button.
- **FR-005**: When an agent clicks "Start Conversation" on an opportunity card and the contact has one or more existing open conversations, the system MUST prompt the agent with the choice to either link an existing open conversation or initiate a new conversation.
- **FR-006**: When an agent clicks "Start Conversation" on an opportunity card and the contact has no open conversations, the system MUST proceed directly to creating/opening a new conversation for that contact and opportunity.
- **FR-007**: When an existing open conversation is linked to an opportunity via the prompt, the system MUST set that conversation as the opportunity's active conversation and record the association. If the conversation was already actively linked to another opportunity, the system MUST require confirmation to transfer the active link.
- **FR-008**: When a new conversation is created from an opportunity, the system MUST automatically associate the newly created conversation with the opportunity as its active conversation.
- **FR-009**: The opportunity details view (drawer/modal) MUST display the complete history of all associated conversations (both past closed and current active), including their status, creation date, and direct navigation links.
- **FR-010**: Realtime Kanban updates MUST reflect conversation state changes (active conversation attached, conversation closed, or action button restored) across all active user sessions without requiring a manual page refresh.
- **FR-011**: Transitioning an opportunity to a terminal stage (Won or Lost) MUST NOT automatically close or detach an ongoing active conversation; the active conversation remains connected until explicitly resolved.

### Key Entities *(include if feature involves data)*

- **Opportunity**: Represents a deal/commercial lead in a pipeline stage. Key attributes include title, value, stage, status (open, won, lost), contact, and association to one active conversation and many historical conversations.
- **Conversation**: Represents a customer chat thread in an inbox. Has its own lifecycle (open, snoozed, resolved), messages, and assigned agent.
- **Opportunity Conversation Association**: Represents the relationship linking an opportunity to a conversation, tracking when it was linked, whether it is currently active, and the role/order in the opportunity lifecycle.
- **Contact**: The customer party associated with the opportunity and conversations.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of opportunities whose active conversations are resolved automatically transition to showing the "Start Conversation" action button without page reload.
- **SC-002**: Agents can initiate or link a conversation from any opportunity card in under 3 clicks.
- **SC-003**: 0% accidental duplicate conversations caused by unawareness of existing open conversations (due to the proactive linking prompt).
- **SC-004**: Complete conversation history (100% of past and active linked conversations) is accessible in the opportunity drawer within 1 click.
- **SC-005**: Closing a conversation never alters the opportunity's funnel stage or monetary value.

## Assumptions

- A contact may have multiple conversations across different channels or timeframes.
- An opportunity belongs to exactly one primary contact.
- When an opportunity is in a terminal stage (Won or Lost), starting a new conversation is still permitted if the business needs follow-up, but the default primary workflow focuses on open opportunities.
- The existing Kanban card action footer and opportunity drawer component architectures will be extended to support the multi-conversation association model and selection prompt.
