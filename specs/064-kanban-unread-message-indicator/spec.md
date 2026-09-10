# Feature Specification: Kanban Unread Message Indicator (Post-Handoff Only)

**Feature Branch**: `064-kanban-unread-message-indicator`

**Created**: 2026-09-10

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 10/scout/24-kanban-unread-message-indicator/spec87.md. um adendo à spec: não quero que a bolinha apareça para oportunidades que ainda estão com o scout, apenas para conversas que já estão com humanos e que possuem mensagens novas. ou seja, somente depois que o scout tiver feito o handoff essencialmente ou em conversas em que scout não está engajado."

## Clarifications

### Session 2026-09-10

- Q: For an opportunity with more than one linked conversation, should the unread dot's
  Scout-engagement gate consider all of the opportunity's conversations, or only its single
  "active" conversation? → A: Gate considers all linked conversations (any of them still
  Scout-engaged suppresses the dot for the whole card), matching the existing "Scout" badge's own
  logic exactly; the unread-message check itself stays scoped to the active conversation only.
- Q: What is the maximum acceptable delay between the underlying event (new message, read,
  handoff) and the indicator updating on the board, without a reload? → A: Up to 5 seconds,
  consistent with the existing "Scout" badge's ActionCable broadcast latency (Phase 22) — no new
  infrastructure, pure reuse.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See which handed-off opportunities have new customer replies (Priority: P1)

An agent scans the Kanban board and needs to know, without opening every card, which opportunities
already owned by a human have a new customer message waiting for a reply.

**Why this priority**: This is the entire value of the feature — surfacing attention-needed cards
without manual inspection. It only delivers value, and avoids being misleading, if it is scoped
correctly to cards a human is actually responsible for.

**Independent Test**: Can be fully tested by opening the board with a mix of opportunities (some
still being worked by Scout, some already handed off to a human, some that never involved Scout)
and confirming the indicator appears only on the cards a human owns and that have an unread
customer message.

**Acceptance Scenarios**:

1. **Given** an opportunity whose linked conversation was handed off from Scout to a human and has
   an unread incoming message, **When** the agent views the Kanban board, **Then** the card shows
   the unread indicator.
2. **Given** an opportunity whose linked conversation never involved Scout (Scout was not engaged)
   and has an unread incoming message, **When** the agent views the Kanban board, **Then** the card
   shows the unread indicator.
3. **Given** an opportunity whose linked conversation is still being actively worked by Scout,
   **When** the agent views the Kanban board, **Then** the card does NOT show the unread indicator,
   regardless of how many unread customer messages exist in that conversation.
4. **Given** an opportunity with no unread incoming messages, **When** the agent views the Kanban
   board, **Then** the card does not show the unread indicator.

---

### User Story 2 - Indicator clears in real time once the conversation is read (Priority: P2)

An agent opens and reads a handed-off conversation that was showing the unread indicator on the
board.

**Why this priority**: Without real-time clearing, the indicator becomes noise the agent learns to
distrust and ignore, undermining Story 1.

**Independent Test**: Can be fully tested by marking a flagged conversation as read and confirming
the indicator disappears from the board without a page reload.

**Acceptance Scenarios**:

1. **Given** a card showing the unread indicator, **When** the agent reads the linked conversation,
   **Then** the indicator disappears from the card in real time, without reloading the board.

---

### User Story 3 - Indicator appears the moment a handed-off conversation gets a new message (Priority: P2)

A customer sends a new message in a conversation that is already owned by a human and currently
visible, unflagged, on the board.

**Why this priority**: The board must reflect new work as it arrives, not only on refresh, for the
indicator to be trustworthy for ongoing monitoring.

**Independent Test**: Can be fully tested by sending a new incoming message on a handed-off,
currently-visible conversation and confirming the indicator appears on its card without a page
reload.

**Acceptance Scenarios**:

1. **Given** a handed-off conversation with no unread messages, **When** a new incoming customer
   message arrives, **Then** the indicator appears on its opportunity's card in real time.

---

### User Story 4 - Indicator turns off automatically if Scout re-engages (Priority: P3)

An opportunity that had been handed off (and was showing the indicator) becomes Scout-engaged
again.

**Why this priority**: Lower priority because Scout re-engagement after handoff is an edge
transition rather than the common path, but the exclusion rule from Story 1 must hold consistently
regardless of when Scout-engagement starts or ends.

**Independent Test**: Can be fully tested by causing an opportunity's conversation to become
Scout-engaged again and confirming the indicator is not shown even if unread messages are present.

**Acceptance Scenarios**:

1. **Given** a card showing the unread indicator, **When** its opportunity becomes Scout-engaged
   again, **Then** the indicator disappears in real time, independent of the unread message state.

### Edge Cases

- An opportunity has more than one linked conversation, and only the active one has been handed off
  while another is still Scout-engaged: the indicator does NOT appear. Scout-engagement is
  evaluated across all of the opportunity's linked conversations (the same signal already used for
  the existing "Scout" status badge), so any conversation still with Scout suppresses the indicator
  for the whole card, even if the active conversation itself has an unread message. The
  unread-message check, by contrast, only looks at the active conversation.
- An opportunity has never had any conversation routed through Scout (e.g., created manually, or on
  an inbox without Scout automation): it is treated as "Scout not engaged," so an unread message
  makes the indicator appear normally.
- A conversation has unread messages but they are all private notes/internal messages: the
  indicator does not appear (only unread *incoming customer* messages count, consistent with how
  "unread" already works elsewhere in the product).
- Scout hands a conversation off and, in the same moment, a new unread message arrives: the
  indicator appears (both conditions — handed off, unread — are independently true).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST show a visual "unread message" indicator on a Kanban card when its
  opportunity's linked conversation has at least one unread incoming customer message.
- **FR-002**: System MUST NOT show the unread indicator while the opportunity is still considered
  actively engaged by Scout, regardless of unread message count.
- **FR-003**: System MUST show the unread indicator once an opportunity's conversation has been
  handed off from Scout to a human and has an unread incoming message.
- **FR-004**: System MUST show the unread indicator on opportunities where Scout was never engaged,
  when there is an unread incoming message.
- **FR-005**: The unread indicator MUST appear and disappear in real time, reflecting new messages,
  read state, and Scout-engagement changes, without requiring the agent to reload the board.
- **FR-006**: The unread indicator MUST be visually distinct from, and MUST NOT replace or alter,
  the existing "Scout" status badge shown on the same card.
- **FR-007**: The unread indicator MUST show presence/absence only — no unread message count.

### Key Entities

- **Opportunity**: The Kanban card's subject. For this feature, it exposes two independent,
  observable states: whether it is still Scout-engaged, and whether its linked conversation has an
  unread incoming message. The unread indicator is shown only when the former is false and the
  latter is true.
- **Conversation**: Source of both the "unread incoming message" state and the "Scout engaged"
  state (Scout involvement plus whether it is still actively handling the conversation versus
  already handed off to a human).
- **Message**: The individual incoming/outgoing record within a conversation. A new, non-private,
  incoming message is what makes a conversation's unread state change; this is what Story 3 needs
  to observe in real time.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An agent can identify every handed-off opportunity with a new, unread customer
  message by scanning the Kanban board alone, without opening any card.
- **SC-002**: 0% of opportunities still being actively worked by Scout display the unread indicator,
  no matter how many unread messages accumulate in that conversation.
- **SC-003**: The indicator reflects a message being read, a new message arriving, or a handoff
  occurring within 5 seconds, without a board reload.
- **SC-004**: Agents never need to open a card to confirm whether a visible unread indicator is
  actually about a Scout-owned conversation — the indicator's presence alone is a reliable signal
  that a human reply is awaited.

## Assumptions

- "Scout engaged" reuses the same engagement concept that already drives the existing "Scout"
  status badge on the Kanban card — an opportunity is Scout-engaged when it has a conversation
  Scout is still actively handling, and stops being Scout-engaged once that conversation is handed
  off to a human. The unread indicator and the "Scout" badge are effectively mutually exclusive
  states on the same card.
- Only presence/absence of unread messages is shown, matching the original request — no unread
  count.
- The feature is scoped to the Kanban board card only, not other views (opportunity list, drawer).
- Existing product rules for what counts as an "unread incoming message" (customer-facing messages
  only, not private notes) are reused as-is, with no new definition introduced.
