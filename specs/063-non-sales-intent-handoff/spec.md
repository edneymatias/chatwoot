# Feature Specification: Non-Sales Intent Recognition and Immediate Handoff

**Feature Branch**: `063-non-sales-intent-handoff`

**Created**: 2026-09-10

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 10/scout/23-non-sales-intent-immediate-handoff/spec86.md — Scout should proactively recognize when a contact is not a prospecting lead and hand off to a human immediately, instead of trying to resolve the request itself"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Existing customer with a support need is handed off immediately (Priority: P1)

A contact is chatting with Scout and makes it clear they are already a customer — they mention an
ongoing treatment, a past purchase, or otherwise state they are not looking for a new evaluation.
Today Scout tries to help as if the contact were a new prospect. With this feature, as soon as
Scout recognizes the contact is not seeking a new prospecting evaluation, it stops trying to
resolve the matter itself and hands the conversation off to a human right away.

**Why this priority**: This is the core problem the feature solves — Scout's job is prospect
qualification, and pushing existing-customer conversations to a human immediately is the main
value being delivered.

**Independent Test**: Can be fully tested by having a contact state, at any point in the
conversation, that they are already a customer or have a treatment in progress, and confirming the
final response hands the conversation to a human without Scout attempting to resolve the request.

**Acceptance Scenarios**:

1. **Given** a contact chatting with Scout, **When** the contact states they are already a
   customer or mentions a treatment already in progress, **Then** Scout hands the conversation off
   to a human immediately instead of continuing to try to qualify or help with the request itself.
2. **Given** a contact who has just stated they are an existing customer, **When** Scout responds,
   **Then** the response does not attempt to answer, diagnose, or resolve the customer's
   underlying question before handing off.

---

### User Story 2 - Reschedule, cancellation, or complaint requests are handed off immediately (Priority: P1)

A contact reaches out wanting to reschedule an appointment, cancel something, or raise a
complaint. None of these are new prospecting requests, but today Scout has no rule telling it to
stop and transfer — it may try to handle the request as if it were a qualification conversation.

**Why this priority**: These are common, high-frequency real-world contact reasons that are
unambiguously not prospecting; failing to recognize them wastes the contact's time and delays
resolution by a human who should own the request.

**Independent Test**: Can be fully tested by having a contact ask to reschedule, cancel, or file a
complaint, and confirming the final response hands the conversation to a human without Scout
attempting to resolve the request on its own.

**Acceptance Scenarios**:

1. **Given** a contact who asks to reschedule or cancel an appointment, **When** Scout responds,
   **Then** the conversation is handed off to a human immediately, without Scout attempting to
   process the reschedule/cancellation itself.
2. **Given** a contact who raises a complaint, **When** Scout responds, **Then** the conversation
   is handed off to a human immediately, without Scout attempting to resolve or placate the
   complaint itself.

---

### User Story 3 - Contact declines a triage question and is handed off immediately (Priority: P2)

Scout sometimes asks the contact whether they want to ask a quick question or are looking for
information about a specific treatment. When the contact answers that it is just a quick,
unrelated question rather than an interest in scheduling an evaluation, there is currently no rule
telling Scout to act on that answer.

**Why this priority**: This closes a real, observed gap — the triage question already occurs in
production, but its answer is currently ignored. It is a smaller slice than the direct-statement
cases above but recovers additional non-prospecting conversations.

**Independent Test**: Can be fully tested by having a contact respond to a Scout triage question by
indicating their question is unrelated to scheduling an evaluation, and confirming the final
response hands the conversation to a human without Scout attempting to answer the question itself.

**Acceptance Scenarios**:

1. **Given** Scout has asked the contact whether they want to ask a quick question or are seeking
   information about a specific treatment, **When** the contact answers that it is just a quick
   question unrelated to scheduling an evaluation, **Then** Scout hands the conversation off to a
   human immediately instead of attempting to answer the question.

---

### User Story 4 - Optional customer-status lookup reinforces, but never blocks, the handoff decision (Priority: P3)

When an account has an external tool configured to check whether a phone number belongs to an
existing customer, Scout may consult it to reinforce a handoff decision. This must never become a
requirement for the handoff to happen — the contact's own words are always sufficient on their
own.

**Why this priority**: This is a refinement of the primary behavior rather than new functionality
in its own right; it protects against a design pitfall (making handoff dependent on an external
system) rather than delivering new user-facing value.

**Independent Test**: Can be fully tested two ways — (a) with the external status tool configured
and the phone number available, confirming Scout may consult it without the outcome changing when
the contact has already given a clear non-prospecting signal; and (b) with no such tool configured
at all, confirming the handoff still happens on the strength of the contact's own statement alone.

**Acceptance Scenarios**:

1. **Given** an account with an external customer-status tool configured and the contact's phone
   number available, **When** the contact gives a clear non-prospecting signal, **Then** Scout may
   consult the tool to reinforce the decision, but the handoff still occurs even if the tool does
   not return a positive confirmation.
2. **Given** an account with no external customer-status tool configured, **When** the contact
   gives a clear non-prospecting signal, **Then** Scout hands off immediately without needing any
   external confirmation.

---

### Edge Cases

- What happens when the contact's non-prospecting intent is ambiguous (e.g., asks a treatment
  question that could be either a returning customer or a new prospect)? Scout continues to use
  its judgment; this feature only covers cases where the signal is clear.
- What happens when a contact who previously completed treatment says they want to purchase again?
  This is a legitimate new prospecting case and is explicitly not covered by this handoff rule —
  Scout continues to treat it as qualification.
- What happens to the existing reactive safety net (the mechanism that reviews a response after
  it is generated and flags out-of-scope commercial requests)? It continues operating unchanged,
  as a complementary layer for cases the proactive rule does not catch.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Scout MUST hand off the conversation to a human immediately once it is clear, from
  what the contact has said, that the contact is not seeking a new prospecting evaluation or
  treatment — including when the contact states they are already a customer, mentions a treatment
  already in progress, asks to reschedule or cancel, raises a complaint, or answers a triage
  question by indicating their need is a quick question unrelated to scheduling an evaluation.
- **FR-002**: Scout MUST NOT attempt to resolve a recognized non-prospecting request on its own,
  regardless of how simple the request appears, before handing off.
- **FR-003**: The decision to recognize non-prospecting intent and hand off MUST be based on the
  contact's own words in the conversation, not on an automatic trigger from any external system
  status.
- **FR-004**: When an external tool for checking a contact's customer/treatment status is
  configured for the account and the contact's phone number is available, Scout MAY consult it to
  reinforce a handoff decision already indicated by the conversation.
- **FR-005**: The absence of an external customer-status tool, or that tool's failure to return a
  positive confirmation, MUST NOT prevent or delay handoff when the contact's own words already
  give a clear non-prospecting signal.
- **FR-006**: The existing reactive safety-net mechanism that reviews generated responses for
  out-of-scope commercial requests MUST continue to operate without any change in behavior.
- **FR-007**: This capability MUST be delivered without introducing any new tool, data model, or
  schema change — it is guidance that shapes Scout's existing handoff behavior.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a review of test conversations covering existing-customer statements, ongoing
  treatment mentions, reschedule/cancel requests, complaints, and "just a quick question" triage
  answers, Scout hands off to a human in 100% of cases instead of attempting to resolve the
  request itself.
- **SC-002**: Handoff for a clear non-prospecting signal occurs consistently whether or not an
  external customer-status tool is configured for the account, and regardless of what that tool
  returns when it is consulted.
- **SC-003**: The existing reactive safety-net mechanism's behavior is unchanged, verified by its
  existing test coverage continuing to pass without modification.

## Assumptions

- "Scout" refers to the existing AI conversational assistant that already handles prospecting
  qualification and already has a human-handoff capability it can invoke.
- The external customer/treatment-status lookup capability referenced in User Story 4 already
  exists as a general-purpose external tool mechanism; configuring a specific status-check tool
  for an account is an operator action outside the scope of this feature.
- The existing reactive safety-net mechanism (which reviews a generated response after the fact
  for out-of-scope commercial requests) already exists and requires no changes for this feature.
- No new data is stored and no existing data model changes as a result of this feature — the
  change is entirely in the guidance that shapes Scout's conversational judgment.
