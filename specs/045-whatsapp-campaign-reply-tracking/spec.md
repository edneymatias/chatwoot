# Feature Specification: WhatsApp Campaign Reply Tracking

**Feature Branch**: `045-whatsapp-campaign-reply-tracking`

**Created**: 2026-09-03

**Status**: Draft

**Input**: User description: "Phase 72: WhatsApp Campaign Reply Tracking (Context, Analytics, Automation Chaining) — see docs/kanban/backlog/13-whatsapp-campaign-reply-tracking/spec72.md. Design already approved by the user on 2026-08-21."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Agent sees campaign context on a reply (Priority: P1)

An agent opens a new conversation that started because a customer replied to a WhatsApp broadcast campaign. Today the conversation shows only the bare reply ("I'm interested", "I want to schedule") with no idea which campaign or which outbound message prompted it, forcing the agent to guess at context before responding. Instead, the agent should immediately see which campaign generated the conversation and the original campaign message that the customer is responding to.

**Why this priority**: This is the core problem the feature exists to solve — agents currently respond blind to campaign-driven conversations, which directly hurts response quality and speed. Nothing else in this feature matters if this doesn't work.

**Independent Test**: Send a one-off WhatsApp campaign to a contact, have the contact reply (either by tapping a quick-reply button or typing free text), and verify the resulting conversation shows the originating campaign and the original campaign message as the first item in the conversation.

**Acceptance Scenarios**:

1. **Given** a contact received a campaign message and taps one of its quick-reply buttons, **When** the reply arrives and creates a new conversation, **Then** the conversation is tagged with the originating campaign, the original campaign message appears as the first message in the conversation, and which button was tapped is recorded.
2. **Given** a contact received a campaign message and instead types a free-text reply without quoting it, **When** exactly one campaign send to that contact is still awaiting a reply within the recent-activity window, **Then** the new conversation is attributed to that campaign and shows the original campaign message as context.
3. **Given** a contact received two different campaign sends close together, **When** the contact replies with free text that doesn't reference either message directly, **Then** the resulting conversation is created with no campaign attribution rather than guessing which one prompted the reply.
4. **Given** an agent is already in an open conversation with a contact, **When** that same contact separately receives a new campaign send, **Then** the open conversation's campaign attribution is left untouched.

---

### User Story 2 - Manager reviews campaign reply performance (Priority: P2)

A campaign manager wants to know not just how many messages were delivered and read, but how many customers actually replied, and specifically how many clicked each quick-reply button versus responding in free text — mirroring the "Desempenho" performance view they're used to from WhatsApp Manager.

**Why this priority**: Without reply-level insight, the manager cannot tell whether a campaign's call-to-action is actually working, only that it was seen. This depends on Story 1's correlation existing but is not required for an agent to respond to a customer, hence P2.

**Independent Test**: Run a completed campaign with a mix of button-tap and free-text replies, open its analytics page, and verify a unique-reply count and a per-button click breakdown (with rates) are shown, alongside the existing delivery metrics.

**Acceptance Scenarios**:

1. **Given** a campaign has received replies, **When** the manager opens the campaign's analytics page, **Then** they see the existing delivery metrics (sent, delivered, read, failed, skipped) unchanged, plus a count of unique customers who replied.
2. **Given** a campaign offered multiple quick-reply buttons, **When** the manager views the reply breakdown, **Then** each button shows its total click count and click rate, ordered by popularity, with all non-button replies grouped into a single "other replies" total.

---

### User Story 3 - Workflow builder conditions automation on campaign origin (Priority: P3)

Someone configuring automation rules wants to route or tag conversations differently depending on which marketing campaign brought the customer in — for example, applying a different label or assigning a different team to replies from a promotional campaign versus a support-oriented one.

**Why this priority**: This is a power-user capability that builds on Story 1's attribution; it adds workflow flexibility but isn't required for the base experience of tracking and displaying campaign context.

**Independent Test**: Create an automation rule that fires when a conversation's campaign matches a specific one (or when any campaign is present), trigger a matching and a non-matching conversation, and confirm the rule fires only for the matching case.

**Acceptance Scenarios**:

1. **Given** an automation rule is configured to match conversations that came from a specific campaign, **When** a new conversation is attributed to that campaign, **Then** the rule fires; **When** a conversation is attributed to a different campaign or none at all, **Then** the rule does not fire.
2. **Given** an automation rule is configured to match "conversation came from any campaign", **When** a conversation without campaign attribution is created, **Then** the rule does not fire.
3. **Given** a rule combines a campaign condition with an existing content condition, **When** both conditions are true for a conversation, **Then** the rule fires as with any other multi-condition rule.

### Edge Cases

- What happens when a contact replies to a campaign message but the reply cannot be unambiguously matched to a single campaign send (e.g., concurrent campaigns, or the lookback window has expired)? The conversation is created with no campaign attribution — the system never guesses.
- What happens when a contact who already has an open conversation receives a new campaign send and then replies? The existing conversation is not retroactively tagged with the campaign.
- What happens when a customer responds using a rich interactive form response (e.g., a WhatsApp Flow submission) rather than a plain quick-reply button? It is counted as a non-button reply alongside free text, not as a distinct button click.
- What happens to campaign analytics and automation behavior that existed before this feature shipped? Existing delivery metrics, the per-contact delivery table, and unrelated automation conditions continue to work exactly as before — this feature only adds new capability on top.
- What happens to conversations created before this feature ships? They are not retroactively attributed to a campaign; only new conversations created after go through correlation.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST track, per contact targeted by a WhatsApp broadcast campaign, the delivery outcome of that send (e.g., queued, skipped, sent, delivered, read, replied, failed).
- **FR-002**: System MUST correlate an inbound WhatsApp reply to the specific campaign send that prompted it when the reply directly references the original message.
- **FR-003**: System MUST correlate an inbound WhatsApp reply that does not directly reference the original message to a campaign send only when exactly one plausible candidate exists for that contact within a bounded recent-activity window; otherwise it MUST leave the conversation unattributed.
- **FR-004**: System MUST attach the identified campaign to a newly created conversation, and MUST NOT change the campaign attribution of a conversation that already existed before the reply arrived.
- **FR-005**: System MUST insert the original campaign message into the new conversation as context, once, before the customer's reply is shown.
- **FR-006**: System MUST record which quick-reply button (if any) a customer tapped, distinct from a free-text or other non-button reply.
- **FR-007**: System MUST continue to provide the existing campaign delivery metrics and per-contact delivery detail without behavior changes.
- **FR-008**: System MUST provide a count of unique customers who replied to a given campaign.
- **FR-009**: System MUST provide a breakdown of quick-reply button clicks per button option, including each button's click count and click rate (computed against total messages sent), plus one aggregated total for all non-button replies.
- **FR-010**: Users MUST be able to configure automation rules that trigger based on whether a conversation is attributed to a campaign at all, or to a specific campaign, for both new-conversation and new-message triggers.
- **FR-011**: This functionality MUST be available without requiring a paid subscription tier.
- **FR-012**: System MUST NOT create a conversation or message at the moment a campaign is sent — a conversation is only created lazily, when the customer actually replies.

### Key Entities *(include if feature involves data)*

- **Campaign Recipient**: One contact targeted by one campaign send. Tracks the delivery/read/reply lifecycle for that contact, which button (if any) they tapped, and links to the resulting conversation's context message once a reply arrives.
- **Conversation**: Gains an optional association to the campaign that generated it, set only at creation time and never altered afterward by later campaign activity.
- **Campaign Message Context**: The original outbound campaign message, surfaced as the first message of a newly attributed conversation so agents have the customer's original prompt in view.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When a customer taps a quick-reply button on a campaign message, the agent sees the originating campaign and the original message content in the new conversation with no manual lookup, 100% of the time.
- **SC-002**: Unambiguous free-text replies to a campaign are attributed to the correct campaign; ambiguous cases (e.g., concurrent campaigns) result in zero incorrect attributions.
- **SC-003**: Campaign managers can determine unique reply count and per-button click rates for any campaign directly from the analytics page, without exporting data or contacting engineering.
- **SC-004**: Automation rule builders can route or tag conversations by campaign origin using the existing rule-configuration UI, without needing a new tool or manual data lookup.
- **SC-005**: Existing campaign analytics and automation behavior show no regressions after this feature ships.

## Assumptions

- The user does not run concurrent WhatsApp campaigns to the same audience today, but the correlation logic is designed to degrade safely (no attribution) rather than misattribute if that changes in the future.
- A fixed 72-hour window is a reasonable default for how long an unreplied campaign send remains a candidate for free-text correlation; this is not user-configurable in this version.
- Reusing the existing campaign analytics screen's layout and metrics (only adding new sections) matches user expectations, since no redesign was requested.
- No historical backfill is needed — conversations created before this feature ships are out of scope for retroactive attribution.
- No manual UI is needed for an agent or manager to correct a missing or wrong campaign attribution after the fact.
- This capability must work standalone in a base (non-Enterprise-licensed) deployment, since the fork operates without a paid Enterprise subscription.
