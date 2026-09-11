# Feature Specification: Scout Human Handoff on Manual Intervention

**Feature Branch**: `054-scout-human-handoff`

**Created**: 2026-08-28

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 10/scout/10-in-conversation-ui/spec68.md"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Human agent takes over a pending Scout conversation (Priority: P1)

A human agent (SDR) opens a conversation that is currently marked `pending` in an inbox where
Scout is active, and sends a public reply directly to the customer — stepping in before Scout has
answered. The system must guarantee that Scout does not also send a reply into the same
conversation after the human's message, which would create a confusing, duplicated, or
contradictory response for the customer.

**Why this priority**: This is the entire scope of the feature and the safety mechanism the MVP
depends on. Without it, Scout can talk over a human agent, which is unacceptable for any live test
of the product with real conversations.

**Independent Test**: In an inbox with Scout enabled, put a conversation into `pending` status
with a Scout response already queued/debounced, then have a human agent send a public reply before
the queued response fires. Confirm the conversation status becomes `open` before the queued Scout
response is evaluated, and that Scout's response is not sent.

**Acceptance Scenarios**:

1. **Given** a `pending` conversation in a Scout-enabled inbox with a Scout reply already
   queued/debounced, **When** a human agent sends a public reply to the customer, **Then** the
   conversation is synchronously reopened (`status: open`) before the queued Scout reply can be
   sent, and Scout's reply is not delivered.
2. **Given** a `pending` conversation in a Scout-enabled inbox, **When** a human agent sends a
   public reply to the customer, **Then** the conversation status changes to `open` as a direct,
   synchronous result of that message (no delay, no dependency on a background job completing).

---

### User Story 2 - Private notes do not trigger handoff (Priority: P2)

A human agent adds an internal private note to a `pending` conversation in a Scout-enabled inbox
(e.g., to coordinate with a teammate) without replying to the customer. Because the customer has
not received any human response, Scout should remain free to continue handling the conversation
normally.

**Why this priority**: Prevents an overly broad detection rule from silently disabling Scout on
conversations where no human has actually responded to the customer, which would undermine the
MVP test of "Scout handles conversations end-to-end."

**Independent Test**: In an inbox with Scout enabled, put a conversation into `pending` status,
have a human agent add a private note (not a public reply), and confirm the conversation status
does not change and Scout's own handling of the conversation is unaffected.

**Acceptance Scenarios**:

1. **Given** a `pending` conversation in a Scout-enabled inbox, **When** a human agent adds a
   private note (not sent to the customer), **Then** the conversation status does not change and
   no handoff is triggered.

---

### User Story 3 - Conversations without Scout are unaffected (Priority: P3)

A human agent works normally on a `pending` conversation in an inbox that does not have Scout
enabled (or where Scout is disabled for the account). The existing conversation status behavior
must remain exactly as it is today.

**Why this priority**: Guards against regressions to standard (non-Scout) conversation handling,
which is the majority of existing traffic and must not change.

**Independent Test**: In an inbox without Scout enabled, put a conversation into `pending` status,
have a human agent send a public reply, and confirm the existing (pre-feature) status-change
behavior is preserved unchanged.

**Acceptance Scenarios**:

1. **Given** a `pending` conversation in an inbox without Scout enabled, **When** a human agent
   sends a public reply, **Then** conversation status behavior is identical to current behavior
   (unaffected by this feature).

---

### Edge Cases

- What happens if Scout itself is the sender of the message (i.e., Scout's own reply) on a
  `pending` conversation — must not be mistaken for a human intervention and must not trigger the
  handoff.
- What happens when a human agent sends a public reply to a conversation that is already `open`
  (not `pending`) — no relevant status change is needed since it is not in the state this feature
  guards against.
- What happens when a conversation's inbox has no Scout attached at all, or has a Scout that is
  attached but currently disabled — either case must be treated as "Scout not effectively enabled"
  and follow existing behavior, consistent with User Story 3.
- What happens when a human agent's public reply and a Scout reply are both triggered at nearly
  the same instant — the synchronous, in-line status change (happening as part of processing the
  human's message, before any queued Scout send) must win the race so the customer never receives
  the colliding Scout reply.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST detect, at the moment a human agent's public reply is created, whether
  the conversation is currently `pending` and belongs to an inbox with Scout enabled.
- **FR-002**: When that condition is met, the system MUST synchronously transition the conversation
  status to `open` as part of handling the human agent's public reply — not via a delayed or
  background process.
- **FR-003**: This synchronous transition MUST complete before any Scout response already
  queued/debounced for that conversation can be delivered, so the customer never receives a Scout
  reply after a human has already responded.
- **FR-004**: The system MUST NOT trigger this status transition for private notes — only public
  replies visible to the customer count as human intervention.
- **FR-005**: The system MUST NOT change this behavior for conversations in inboxes without an
  attached, enabled Scout — existing status-change behavior for those conversations remains
  exactly as it is today.
- **FR-006**: The system MUST NOT treat a message sent by Scout itself as a human intervention.
- **FR-007**: This feature introduces no new user-facing UI element (no status badge, no Kanban
  link, no comparison indicator) and no manual pause/resume control — those are explicitly out of
  scope for this phase.

### Key Entities

- **Conversation**: Has a status (e.g., `pending`, `open`) and belongs to an inbox. Its status is
  the state this feature synchronously updates in response to human intervention.
- **Message**: Represents a reply or note in a conversation; distinguished by sender type (human
  agent vs. Scout) and visibility (public reply vs. private note). The triggering event for this
  feature is a public reply authored by a human agent.
- **Inbox / Scout configuration**: Determines whether Scout is enabled for a given conversation's
  inbox, which gates whether this feature's detection applies at all.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of the time a human agent sends a public reply to a `pending`, Scout-enabled
  conversation with a Scout reply already queued, the customer receives zero colliding or
  duplicate Scout replies after the human's message.
- **SC-002**: 0% of private-note-only interactions on `pending`, Scout-enabled conversations result
  in an unintended status change or interruption of Scout's normal handling.
- **SC-003**: 0% behavior change is observed in status-change outcomes for conversations in
  non-Scout-enabled inboxes, verified against current behavior.
- **SC-004**: The conversation status change is observable as complete within the same request/
  operation that processes the human agent's public reply, with no observable delay window during
  which a stale Scout reply could still be sent.

## Assumptions

- This feature governs backend conversation-status behavior only; it does not add or change any
  frontend UI, endpoint, or database field, per the reduced scope agreed in the source phase
  document.
- "Scout enabled" for a conversation is determined by the existing Scout-to-inbox configuration
  already present in the system (a conversation's inbox has an attached, enabled Scout); this
  feature does not introduce a new configuration surface.
- The equivalent, already-proven mechanism used for Chatwoot's existing AI agent (Captain) for the
  same pending/human-intervention scenario is the reference behavior this feature mirrors for
  Scout; where that existing mechanism already runs, this feature complements it rather than
  replacing it.
- "Synchronous" means the status transition is guaranteed to happen as part of processing the
  human agent's reply, before any independently queued/debounced Scout response for that
  conversation can be delivered — not that all downstream side effects of the status change must
  also complete before the request returns.
