# Feature Specification: Contact Panel Opportunity Quick Create

**Feature Branch**: `033-contact-panel-opportunity-quick-create`

**Created**: 2026-08-12

**Status**: Draft

**Input**: User description: "Create Opportunity Directly From the Open Conversation (Contact Panel) — the Contact Panel's Opportunities section lists a contact's opportunities but has no entry point to create one from the conversation currently open, and the list's ordering doesn't surface the opportunity tied to the current conversation."

## Clarifications

### Session 2026-08-12

- Q: If an agent opens the "Add opportunity" flow from conversation A and then switches to a different conversation before finishing it, what should happen to that open flow? → A: The flow closes automatically when the agent switches conversations, discarding any in-progress input — consistent with the existing behavior of the opportunity detail popup (backdrop overlay, click-outside-to-close), which already allows switching conversations by closing the popup first.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create an opportunity without leaving the conversation (Priority: P1)

An agent is chatting with a contact and identifies a sales opportunity. Today they must leave the
conversation and go to the Kanban or List view to create it, losing context. They need a way to
create the opportunity directly from the Contact Panel of the open conversation.

**Why this priority**: This is the core gap the feature closes — without it, nothing else in this
spec has value. It's also the highest-frequency action agents will take from this surface.

**Independent Test**: From an open conversation with a contact that has no opportunity linked to
it, click the new "Add opportunity" action in the Contact Panel's Opportunities section, complete
the creation flow, and confirm the opportunity is created and linked to both the contact and the
current conversation.

**Acceptance Scenarios**:

1. **Given** an open conversation whose contact has no opportunity linked to this conversation,
   **When** the agent opens the Contact Panel's Opportunities section, **Then** they see an
   "Add opportunity" action available to click.
2. **Given** the agent clicks "Add opportunity", **When** the creation flow opens, **Then** it is
   pre-linked to the current conversation and pre-filled with the current contact, requiring no
   extra lookup or selection.
3. **Given** the agent completes and confirms the creation flow, **When** the opportunity is
   saved, **Then** it is associated with both the current contact and the current conversation.

---

### User Story 2 - Prevent duplicate opportunities on the same conversation (Priority: P2)

Only one opportunity is allowed per conversation. An agent must not be able to attempt creating a
second opportunity for a conversation that already has one, and once inside the creation flow
launched from a conversation, must not be able to change which contact the opportunity is tied to
(since the flow only makes sense in the context of this specific conversation and its contact).

**Why this priority**: Protects a hard business rule (one opportunity per conversation) from being
violated or attempted through this new entry point; secondary to User Story 1 because it's a
guardrail on the new capability rather than the capability itself.

**Independent Test**: Open a conversation whose contact already has an opportunity linked to it,
and separately, launch the creation flow from a conversation and attempt to change the contact.

**Acceptance Scenarios**:

1. **Given** the current conversation already has an opportunity linked to it, **When** the agent
   views the Contact Panel's Opportunities section, **Then** the "Add opportunity" action is
   disabled.
2. **Given** the agent launched the creation flow from an open conversation, **When** they view
   the contact field in that flow, **Then** the contact is shown fixed/read-only with no way to
   search for or select a different contact.
3. **Given** the agent launches the opportunity creation flow from any other entry point (not from
   an open conversation), **When** they view the contact field, **Then** contact search-and-select
   behaves exactly as it does today, unaffected by this feature.

---

### User Story 3 - Find the current conversation's opportunity at a glance (Priority: P3)

An agent revisiting a conversation with an existing linked opportunity, or one who just created
one, wants to immediately see it at the top of the Contact Panel's opportunity list without
scanning through every opportunity the contact has, and without needing to refresh the page.

**Why this priority**: A convenience/visibility improvement on top of the creation capability —
valuable, but agents can still find the right opportunity by scanning the list without it, so it's
lower priority than the creation flow and its guardrail.

**Independent Test**: Open a conversation whose contact has multiple opportunities, including one
linked to the current conversation, and confirm it appears first and is visually distinguished.
Then create a new opportunity from that conversation and confirm it immediately appears at the
top without a page refresh.

**Acceptance Scenarios**:

1. **Given** a contact has multiple opportunities and one of them is linked to the currently open
   conversation, **When** the agent views the Contact Panel's Opportunities section, **Then** that
   opportunity appears first in the list, with the rest kept in their existing order.
2. **Given** the opportunity linked to the current conversation is shown first, **When** the agent
   looks at it, **Then** it is visually distinguished from the other opportunities in the list.
3. **Given** the agent creates a new opportunity from the current conversation (User Story 1),
   **When** creation completes, **Then** the new opportunity appears at the top of the Contact
   Panel's list immediately, without requiring a manual refresh.

---

### Edge Cases

- What happens if the agent opens the creation flow from a conversation, then switches to a
  different conversation before completing it? The flow closes automatically (discarding any
  in-progress input) as soon as the agent navigates away, consistent with the existing
  backdrop-overlay / click-outside-to-close behavior of the opportunity detail popup — it never
  stays open bound to a conversation that is no longer on screen.
- What happens if two agents attempt to create an opportunity for the same conversation at nearly
  the same time? The one-opportunity-per-conversation rule must still be enforced; the second
  attempt must fail cleanly rather than create a duplicate or silently overwrite the first.
- What happens if the current conversation's contact has no opportunities at all yet? The list is
  empty except for the newly created opportunity once one is added; no special empty-state changes
  are required beyond what exists today.
- What happens if the conversation's contact has an opportunity linked to a different conversation
  (not the current one)? It appears in the list in its normal position — only the opportunity
  matching the *current* conversation is surfaced first and highlighted.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Contact Panel's Opportunities section MUST offer an "Add opportunity" action,
  presented as a subtle, secondary-style action consistent with other lightweight actions already
  present in the Contact Panel (not a prominent call-to-action).
- **FR-002**: The "Add opportunity" action MUST be disabled whenever the currently open
  conversation already has an opportunity linked to it, reflecting the one-opportunity-per-
  conversation rule.
- **FR-003**: Clicking "Add opportunity" MUST open the opportunity creation flow pre-linked to the
  current conversation and pre-filled with the current contact.
- **FR-004**: When the opportunity creation flow is launched from an open conversation, the
  contact MUST be shown as fixed/read-only, with no ability to search for or select a different
  contact for the duration of that flow.
- **FR-005**: When the opportunity creation flow is launched from any entry point other than an
  open conversation, contact search-and-select behavior MUST remain unchanged from current
  behavior.
- **FR-006**: In the Contact Panel's Opportunities list, the opportunity linked to the currently
  open conversation (if one exists) MUST be shown first, with all other opportunities for that
  contact retained in their existing relative order.
- **FR-007**: The opportunity linked to the currently open conversation, when shown first in the
  list, MUST be visually distinguished from the other opportunities in the list.
- **FR-008**: When a new opportunity is created from the current conversation, it MUST appear at
  the top of the Contact Panel's Opportunities list immediately, without requiring a manual page
  refresh.
- **FR-009**: The one-opportunity-per-conversation rule itself (including how it is enforced) MUST
  NOT be changed by this feature — it is only surfaced and respected through the new UI additions.
- **FR-010**: If the agent navigates away from the conversation the creation flow was launched
  from (e.g. switches to a different open conversation) before completing it, the flow MUST close
  automatically, discarding any in-progress input, consistent with the existing close behavior of
  the opportunity detail popup.

### Key Entities

- **Opportunity**: A sales opportunity tied to exactly one contact and, optionally, to exactly one
  originating conversation (immutable once set). Multiple opportunities may exist per contact, but
  at most one opportunity may be linked to any given conversation.
- **Contact**: The person an opportunity is associated with; always present on an opportunity.
- **Conversation**: The currently open conversation an agent is viewing; may or may not have an
  opportunity linked to it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An agent can create an opportunity from an open conversation, without leaving the
  conversation, in under 30 seconds.
- **SC-002**: 100% of attempts to create a second opportunity for a conversation that already has
  one are blocked before submission (the action is disabled, not merely rejected after the fact).
- **SC-003**: An agent revisiting a conversation with a linked opportunity can identify it within
  the Contact Panel's opportunity list in under 3 seconds, without scrolling past unrelated
  opportunities in the common case.
- **SC-004**: A newly created opportunity is visible at the top of the Contact Panel's list
  immediately after creation, with zero manual refreshes needed, in 100% of cases.

## Assumptions

- The opportunity creation flow, contact search, and the Contact Panel's Opportunities section
  already exist and are being extended, not built from scratch.
- The one-opportunity-per-conversation rule is an existing, unchanged constraint enforced
  elsewhere in the system; this feature only needs to respect it in the UI (disable the action,
  fix the contact) rather than re-implement or re-validate it.
- The reordering/highlighting behavior and the new creation entry point are scoped to the Contact
  Panel's Opportunities section only; other surfaces where opportunities are listed or created
  (e.g. a board/kanban view, a standalone list view) are unaffected.
- The inverse flow — starting a conversation from an existing opportunity — is unaffected and out
  of scope.
- Changing which contact an opportunity is tied to, once fixed at creation time via this flow, is
  out of scope; the contact is fixed for the life of that creation attempt.
