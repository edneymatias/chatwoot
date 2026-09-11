# Feature Specification: Scout Follow-Up Nudges and Rescue Handoff

**Feature Branch**: `022-scout-follow-up-nudges-and-rescue-handoff`

**Created**: 2026-09-07

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 10/scout/22-scout-follow-up-nudges-and-rescue-handoff/spec85.md — Scout follow-up nudges and rescue handoff for contacts who go silent in an open conversation"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Contact receives a re-engagement check-in after going silent (Priority: P1)

A contact is chatting with Scout about a deal, but stops replying while the conversation is still
waiting on them. Today nothing happens — the conversation just sits there until a human happens to
notice. With this feature, the contact gets a friendly, automatic check-in message after a
configured period of silence, without needing a human to intervene.

**Why this priority**: This is the core value of the feature — turning a silent, stalled
conversation into an active nudge, which is what recovers deals that would otherwise be lost to
inattention alone.

**Independent Test**: Can be fully tested by leaving a Scout conversation without a reply past the
first configured silence threshold and confirming the contact receives exactly one check-in
message, with no further action taken until the next threshold.

**Acceptance Scenarios**:

1. **Given** a conversation is awaiting the contact's reply and has had no activity for at least
   the first configured silence threshold (default: 2 hours), **When** the periodic check runs,
   **Then** the contact receives one re-engagement message and no other action is taken.
2. **Given** the contact already received the first re-engagement message and still has not
   replied by the second configured threshold (default: 12 hours of silence), **When** the
   periodic check runs, **Then** the contact receives a second re-engagement message.
3. **Given** the contact replies at any point after a re-engagement message, **When** the periodic
   check next runs, **Then** no further re-engagement message or handoff is sent for that silent
   period.

---

### User Story 2 - Unresponsive contact is handed off to a human with the deal flagged for follow-up (Priority: P1)

When a contact still doesn't respond after both automatic check-ins, the conversation needs to
stop being Scout's responsibility and become visible to a human, and the deal needs to land
somewhere a person will notice it needs attention — instead of remaining invisible in whatever
stage it was already in.

**Why this priority**: Without this step, the re-engagement attempts alone don't close the loop —
the conversation would still be a dead end when the contact truly disengages. The handoff and
stage change are what make the stall actionable by a person.

**Independent Test**: Can be fully tested by leaving a conversation silent through both
re-engagement attempts and the final configured threshold, then confirming the conversation is
released to human ownership and the associated open deal moves to the account's configured rescue
stage.

**Acceptance Scenarios**:

1. **Given** the contact has not replied after both re-engagement messages and the last configured
   silence threshold (default: 24 hours total) has passed, **When** the periodic check runs,
   **Then** the conversation is released for human attendance, the associated open deal moves to
   the account's configured rescue stage, and a note explaining why is attached for the human who
   picks it up.
2. **Given** the handoff message shown to the contact, **When** they read it, **Then** it reads as
   a continuation of service (e.g. connecting them with a team member) rather than a comment about
   their lack of response.
3. **Given** an account has not configured a rescue stage, **When** the periodic check runs for
   that account's conversations, **Then** no re-engagement message or handoff is sent for any of
   its conversations.
4. **Given** the conversation's only associated deal is already closed (won or lost), **When** the
   periodic check runs, **Then** the conversation is skipped entirely.

---

### User Story 3 - Automated outreach respects the inbox's business hours (Priority: P2)

A re-engagement message or handoff landing on a contact's phone at 2 AM feels intrusive and
undermines the "continuity of care" tone the feature is meant to convey. Accounts that have
configured business hours for an inbox expect all outbound contact, automated or not, to honor
that window.

**Why this priority**: This protects the customer experience and brand tone the feature depends
on, but the feature still functions (just less politely) without it, so it ranks below the core
nudge/handoff loop.

**Independent Test**: Can be fully tested by setting an inbox's business hours to exclude the
current time, letting a conversation reach a silence threshold, and confirming no message is sent
during that run but the attempt is still sent once business hours resume.

**Acceptance Scenarios**:

1. **Given** a conversation has reached a silence threshold outside the inbox's configured
   business hours, **When** the periodic check runs, **Then** no re-engagement message or handoff
   is sent, and the attempt is re-evaluated on a later run.
2. **Given** the same conversation once business hours resume, **When** the periodic check next
   runs, **Then** the appropriate re-engagement message or handoff is sent as if no time had been
   lost waiting.
3. **Given** an account has not configured business hours for an inbox, **When** the periodic
   check runs, **Then** behavior is unchanged from an account with business hours covering all
   hours.

---

### User Story 4 - Staff can spot Scout-owned conversations awaiting a reply directly on the deal board (Priority: P3)

Sales staff scanning the deal board today have no way to tell, at a glance, which deals have an
active Scout conversation waiting on the contact versus one that has already stalled or been
picked up by a human. A visible marker on the card closes that gap.

**Why this priority**: This is a visibility/convenience improvement on top of the automated
loop — valuable for staff awareness, but the underlying nudge/handoff behavior delivers its value
independent of this indicator.

**Independent Test**: Can be fully tested by opening the deal board for an opportunity whose
active conversation is awaiting the contact's reply and confirming a "Scout" indicator appears on
its card, then confirming it disappears once that conversation is handed off (manually or
automatically).

**Acceptance Scenarios**:

1. **Given** an opportunity's active conversation is awaiting the contact's reply, **When** a
   staff member views the deal board, **Then** that opportunity's card shows a "Scout" indicator.
2. **Given** that conversation is later handed off to a human (whether manually or through the
   rescue handoff), **When** the staff member views the board again, **Then** the indicator no
   longer appears on the card.

---

### Edge Cases

- What happens if the contact replies, or a human takes over the conversation, in the brief window
  between the periodic check identifying a stalled conversation and the check actually acting on
  it? The system must detect this and take no action, since the situation is no longer stalled.
- What happens if a human is reviewing/approving Scout's next reply (a separate automated review
  step) at the exact moment the contact or another human responds? The contact must not receive a
  duplicate message, and no incorrect handoff should occur from that in-flight review.
- What happens to the count of re-engagement attempts already sent if the account changes its
  silence thresholds mid-sequence? The system re-derives progress from what has actually been sent
  in the current silent period, so a threshold change takes effect on the next check without
  needing a manual reset.
- What happens if a contact goes silent, receives both re-engagement messages, gets handed off,
  and then later reopens a new conversation? The new conversation starts its own independent
  silence tracking.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST send the contact a re-engagement message when a conversation awaiting
  their reply has had no activity for at least the account's first configured silence threshold.
- **FR-002**: System MUST send the contact a second re-engagement message if they remain silent
  through the account's second configured silence threshold.
- **FR-003**: System MUST hand the conversation off to a human and move its associated open deal
  to the account's configured rescue stage if the contact remains silent through the account's
  third (final) configured silence threshold.
- **FR-004**: The number of re-engagement attempts before handoff is fixed at two per conversation
  in this phase and is not configurable per account: changing the account's configured thresholds
  (FR-005) changes *when* each step fires, never *how many* steps there are.
- **FR-005**: System MUST let each account configure its own ordered sequence of exactly three
  ascending, positive silence thresholds — the first two are re-engagement steps, the third is the
  final handoff threshold — defaulting to 2 hours, 12 hours, and 24 hours of silence respectively.
  A sequence with more or fewer than three values MUST be rejected, so the attempt count in FR-004
  cannot be changed by adding or removing thresholds.
- **FR-006**: System MUST let each account configure which pipeline stage serves as the "rescue"
  destination for deals whose conversation went fully unanswered.
- **FR-007**: Accounts that have not configured a rescue stage MUST NOT have any of their
  conversations affected by this automation — including the re-engagement messages in FR-001/FR-002,
  not only the final handoff.
- **FR-008**: System MUST NOT send a re-engagement message or perform the rescue handoff outside
  an inbox's configured business hours; the attempt MUST be re-evaluated on a subsequent periodic
  check rather than being skipped permanently.
- **FR-009**: System MUST take no further re-engagement or handoff action for a conversation once
  the contact has replied or a human has taken ownership of it.
- **FR-010**: System MUST skip conversations whose only associated deal is already closed (won or
  lost) — the automation, including the re-engagement messages in FR-001/FR-002, only applies to
  conversations tied to an open deal.
- **FR-011**: The message shown to the contact at the point of rescue handoff MUST convey
  continuity of care (e.g., being connected with a team member) and MUST NOT reference their lack
  of response.
- **FR-012**: When a separate automated review step is deciding what Scout's next reply should be,
  the system MUST re-check whether the conversation is still awaiting the contact's reply
  immediately after that review completes, so a contact or human who responds during the review
  cannot receive a duplicate message or trigger an incorrect handoff.
- **FR-013**: The deal board MUST display an indicator on an opportunity's card whenever its
  active conversation is awaiting the contact's reply on an inbox with an enabled Scout, and MUST
  remove that indicator once the conversation is handed off (manually or automatically). This
  indicator reflects Scout's general engagement state and applies regardless of whether the
  account has configured the follow-up/rescue automation from FR-005/FR-006 — it is not gated by
  FR-007.

### Key Entities

- **Scout**: The account-level automation configuration that owns the re-engagement/rescue
  behavior; holds the ordered silence thresholds and the designated rescue pipeline stage for its
  inboxes.
- **Conversation**: The ongoing dialogue between a contact and Scout; tracked as awaiting the
  contact's reply or not, and as within or outside business hours via its inbox.
- **Opportunity (deal)**: The sales record linked to a conversation, moved between pipeline
  stages; only open deals are affected by this automation.
- **Rescue stage**: A pipeline stage designated per account as the destination for deals whose
  conversation went fully unanswered, where a human decides the next step.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every conversation left unanswered past an account's first silence threshold
  receives a re-engagement check-in without any manual staff action.
- **SC-002**: Every conversation left unanswered through all configured silence thresholds is
  released to human ownership, with its deal visibly flagged for follow-up, within one periodic
  check cycle (30 minutes) of crossing the final threshold.
- **SC-003**: Zero automated re-engagement messages or handoffs are sent outside an inbox's
  configured business hours.
- **SC-004**: Staff can identify, from the deal board alone, which open deals currently have a
  Scout conversation waiting on the contact, without opening each conversation individually.
- **SC-005**: No contact reports receiving a duplicate message or an out-of-place handoff caused by
  timing overlap between the automated review step and their own reply.

## Assumptions

- The account's existing configuration already distinguishes conversations "awaiting the contact's
  reply" (pending) from conversations a human owns (open) — this feature builds on that existing
  state rather than introducing a new one.
- Silence is measured from the conversation's last visible activity, regardless of which side
  produced the most recent Scout-only messages in between.
- Accounts without business hours configured for an inbox are treated as always within business
  hours, matching current behavior elsewhere in the product.
- A conversation can only have a rescue handoff performed on it once per silent period; if the
  contact re-engages and later goes silent again, the sequence restarts from the first threshold.
- Token/quota telemetry and end-to-end automated test coverage for the broader follow-up mechanism
  are handled separately and are out of scope here.
- The number of re-engagement attempts (two) before handoff is a fixed product decision for this
  phase, not left open for account-level configuration.
