# Feature Specification: Funnel Outcome-Stage Matching for Scout

**Feature Branch**: `059-funnel-outcome-stage-matching`

**Created**: 2026-08-30

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 10/scout/18-funnel-outcome-stage-matching/spec79.md"

## Clarifications

### Session 2026-08-30

- Q: When a turn's outcome could plausibly match more than one configured stage description at once, which stage should Scout move the opportunity to? → A: Most specific match — Scout judges which stage description is the closest/most specific textual match to the outcome, with no fixed precedence between stage types (e.g., the disqualification stage does not automatically win over another partial match).
- Q: Should automatic outcome-matching be allowed to move an opportunity backward (e.g., disqualifying one that already reached the qualified stage)? → A: Forward-only — automatic outcome-matching only ever advances an opportunity to a later/more-progressed stage; once an opportunity has reached the qualified stage, later turns do not automatically move it back out.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Outcome-Driven Stage Transitions (Priority: P1)

As a sales manager relying on Scout to run qualification conversations, I want the agent to compare
what actually happened in each conversation turn against the descriptions configured for each
pipeline stage, and move the opportunity the moment a clear match occurs — including into the
disqualification stage when the lead declines or stalls, and into the qualified stage when the lead
confirms — so that the pipeline reflects reality without a human having to notice and fix it later.

**Why this priority**: This is the core defect motivating the feature: opportunities silently stay in
the wrong stage even when the conversation outcome unambiguously matches a configured stage
description, which misleads reporting, wastes qualified leads sitting unqualified, and lets stale
deals accumulate in review queues without follow-up.

**Independent Test**: Can be tested by running a conversation where the lead clearly declines or
postpones the proposed action against an account whose disqualification stage description covers
that scenario, and separately a conversation where the lead confirms the action and supplies all
required qualification data; in both cases the opportunity must move to the matching stage without
being marked as a closed won/lost deal in the disqualification case.

**Acceptance Scenarios**:

1. **Given** an opportunity's stage descriptions are configured and a lead refuses or postpones the
   main proposed action in a way that matches the disqualification stage description, **When** the
   turn ends, **Then** the opportunity is moved to the disqualification stage as a review-queue item,
   not marked as lost or won.
2. **Given** a lead confirms the main proposed action and has already supplied every value required
   for the qualified stage (including any dates or scheduling details), **When** the turn ends,
   **Then** the opportunity is moved to the qualified stage with those values recorded, at the same
   time as or before the reply confirming the outcome to the customer — never after, and never
   replaced by a handoff that claims a missing capability.
3. **Given** an account has not configured a description for a given stage, **When** conversations
   proceed through that stage, **Then** behavior is unchanged from today (no new automatic transition
   is forced without a description to match against).
4. **Given** a turn's outcome could plausibly match more than one configured stage description,
   **When** Scout evaluates the match, **Then** it moves the opportunity to whichever stage's
   description is the closest, most specific textual match to the outcome, with no fixed precedence
   between stage types.
5. **Given** an opportunity has already reached the qualified stage, **When** a later turn's outcome
   would otherwise match an earlier stage or the disqualification stage, **Then** the opportunity is
   not automatically moved backward out of the qualified stage.

---

### User Story 2 - Correct Belief About Available Capabilities (Priority: P1)

As a sales manager, I want Scout to recognize that it can record any qualification data — including
dates and scheduling information the lead provides — directly through its existing opportunity tools,
so that it never prematurely hands the conversation to a human agent under the mistaken belief that a
capability (such as a scheduling system) is missing.

**Why this priority**: Premature handoffs caused by a false capability gap directly break the
promise of an autonomous qualification flow: a lead who has already given everything needed to
qualify is instead made to wait for a human, eroding the value of automation and delaying pipeline
progress.

**Independent Test**: Can be tested by having a lead confirm a scheduled time or similar structured
detail that satisfies a stage's requirements; the agent must record it and advance the stage using its
own tools instead of transferring to a human agent citing a missing tool.

**Acceptance Scenarios**:

1. **Given** a lead provides a date, time, or other structured value that satisfies the qualified
   stage's requirements, **When** Scout processes the turn, **Then** it records the value and advances
   the opportunity stage using its own tools instead of escalating to a human agent.
2. **Given** the qualified stage's handoff to a human team is already triggered automatically as part
   of the stage transition, **When** Scout moves an opportunity into that stage, **Then** it does not
   separately invoke a manual handoff for the same event.

---

### User Story 3 - Focused, Advancing Conversational Pace (Priority: P2)

As a lead chatting with Scout, I want each response to ask me at most one question and to always
leave me with something to respond to when relevant information was just shared, so the conversation
feels natural and keeps moving forward instead of stalling or overwhelming me.

**Why this priority**: Stacked questions and inert responses (informative replies with no next step)
are the most visible everyday quality issues reported from real conversations; they directly degrade
lead experience and stall qualification progress even when the underlying logic is otherwise correct.

**Independent Test**: Can be tested by reviewing a batch of Scout responses across live conversations
and confirming no response contains more than one question, and that any response presenting new
information ends with a question or next step unless the lead had just signaled a pause.

**Acceptance Scenarios**:

1. **Given** Scout needs several pieces of information from the lead, **When** it composes a
   response, **Then** it asks for only one piece of information per turn, deferring the rest to
   subsequent turns.
2. **Given** Scout shares relevant information (e.g., answering a product question), **When** it
   composes the response, **Then** it closes with a single question or next step that keeps
   qualification moving, unless the lead has just signaled they want to pause or end the conversation.
3. **Given** a lead signals they want to pause or end the conversation for now, **When** Scout
   replies, **Then** it does not reintroduce pending qualification questions in that same turn.

---

### User Story 4 - Discreet, Natural Action Confirmations (Priority: P2)

As a lead interacting with Scout, I want confirmations of actions taken on my behalf to sound like a
person talking to me, not like a system log, so I never see internal record identifiers, technical
field names, or CRM jargon in the conversation.

**Why this priority**: Exposing internal identifiers or system language breaks the illusion of a
natural sales conversation and can look unprofessional or confusing to leads, even though the
underlying action is correct.

**Independent Test**: Can be tested by triggering an opportunity update through conversation and
confirming the reply describes the outcome in plain customer-facing language without opportunity
IDs, internal field names, or log-style phrasing.

**Acceptance Scenarios**:

1. **Given** Scout successfully records or updates information via an internal tool, **When** it
   confirms this to the customer, **Then** the confirmation uses natural, customer-facing language and
   never exposes internal identifiers, technical field names, or system log phrasing.

---

### User Story 5 - Natural Clarification for List-Based Fields (Priority: P3)

As a lead being asked for a piece of information that corresponds to a predefined list of values
(e.g., an interest category), I want to be asked an open, natural question rather than being read a
menu of the exact configured options, so the conversation still feels like it's with a person.

**Why this priority**: Reciting configured value lists as a multiple-choice menu is a lower-frequency
but still noticeable naturalness issue; it doesn't block qualification progress the way the P1/P2
items do, but it undermines the conversational tone the feature otherwise protects.

**Independent Test**: Can be tested by triggering a data-collection moment for a list-valued field and
confirming the response asks an open question rather than enumerating the configured values, while
the lead's free-text answer is still correctly mapped to the right value internally.

**Acceptance Scenarios**:

1. **Given** Scout needs a value for a field with a predefined list of allowed options, **When** it
   asks the lead for that value, **Then** it phrases the question openly without reciting the list of
   allowed options as a menu, and still correctly maps the lead's free-text reply to the matching
   allowed value when recording it.

---

### User Story 6 - Operator Guidance for Actionable Stage Descriptions (Priority: P3)

As an account administrator configuring pipeline stages, I want a visible hint on the stage
description field explaining that the description is also used by the AI to decide when to move a
conversation into that stage, so I write descriptions that are objective and actionable rather than
purely internal notes.

**Why this priority**: This is a cosmetic, low-risk guidance addition (not a hard requirement or
validation) that improves the odds operators write stage descriptions the outcome-matching logic can
act on; it has no bearing on runtime behavior and can ship independently of the prompt-level items.

**Independent Test**: Can be tested by opening the add and edit pipeline stage forms in both English
and Portuguese and confirming the hint text appears below the description label regardless of whether
the field is empty, without affecting save behavior.

**Acceptance Scenarios**:

1. **Given** an administrator opens the add or edit pipeline stage form, **When** they view the
   description field, **Then** a short hint explaining the field's use by the AI is visible below the
   label, in the account's configured language, regardless of whether the field already has content.

---

### Edge Cases

- **No stage description configured**: Accounts that have not written a description for a given stage
  see no forced automatic transition into or out of that stage based on outcome matching — existing
  behavior is preserved (User Story 1, Acceptance Scenario 3).
- **Ambiguous or non-matching outcome**: When the turn's outcome does not clearly match any configured
  stage description, no automatic stage transition is forced; the agent continues qualification as
  today.
- **Multiple simultaneous stage matches**: When a turn's outcome could plausibly match more than one
  configured stage description at once, the opportunity moves to whichever stage's description is the
  closest, most specific textual match — there is no fixed precedence between stage types (User Story
  1, Acceptance Scenario 4).
- **Already-qualified opportunities are protected from automatic regression**: Once an opportunity has
  reached the qualified stage, automatic outcome-matching never moves it back to an earlier stage or
  to disqualification; only forward progress is automated (User Story 1, Acceptance Scenario 5).
- **Stochastic behavior**: Because the underlying agent behavior is model-driven, matching is expected
  to be probabilistic, not deterministic; the feature's acceptance criteria describe the intended
  behavior, not a guarantee enforceable on every single conversation.
- **Disqualification is not deal closure**: Moving an opportunity to the disqualification stage must
  never be conflated with marking the deal won or lost; it represents a human review queue.
- **No hardcoded keyword rules**: No business rule may hardcode a specific keyword, phrase, or trigger
  condition; all matching relies on the operator-authored stage descriptions already available.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: At the end of each conversation turn, Scout MUST compare the observable outcome of that
  turn against the descriptions configured for each pipeline stage and, when the outcome clearly
  matches a stage's description, move the opportunity to that stage in the same turn rather than
  waiting for an explicit keyword or a direct question from the lead. When the outcome plausibly
  matches more than one stage's description at once, Scout MUST move the opportunity to whichever
  stage's description is the closest, most specific textual match, with no fixed precedence between
  stage types.
- **FR-001a**: Automatic stage transitions driven by outcome matching MUST only ever advance an
  opportunity to a later, more-progressed stage. Once an opportunity has reached the qualified stage,
  Scout MUST NOT automatically move it back to an earlier stage or to disqualification based on a
  later turn's outcome.
- **FR-002**: When an opportunity is moved into the disqualification stage, the system MUST treat it
  as a human review-queue item, never as a deal marked won or lost, and any disqualification reason
  MUST be captured as an internal note rather than a customer-facing statement.
- **FR-003**: When an opportunity is moved into the qualified stage, the corresponding human handoff
  MUST happen automatically as part of that transition, and Scout MUST NOT separately trigger a manual
  handoff for the same event.
- **FR-004**: Scout MUST treat its own opportunity-management tools as sufficient to record any
  qualification data the lead has already provided — including dates and scheduling details — and
  MUST NOT conclude that an external capability (e.g., a scheduling system) is missing when the data
  needed to satisfy a stage's criteria has already been given.
- **FR-005**: Scout MUST NOT include more than one question in a single response.
- **FR-006**: Any Scout response that presents information relevant to qualification MUST close with a
  single question or next step that keeps qualification moving, except when the lead has just
  signaled they want to pause or end the conversation, in which case pending qualification questions
  MUST NOT be reintroduced in that same turn.
- **FR-007**: When confirming that an action was recorded or updated, Scout MUST use natural,
  customer-facing language and MUST NOT expose internal record identifiers, technical field or
  attribute names, or system log-style phrasing.
- **FR-008**: When requesting a value for a field that has a predefined list of allowed values, Scout
  MUST phrase the request as an open, natural question rather than reciting the allowed values as a
  multiple-choice menu, while still correctly mapping the lead's free-text answer to the matching
  allowed value internally.
- **FR-009**: The pipeline stage description field MUST display a short, always-visible hint (not
  dependent on the field being empty) explaining that the description is also used by the AI to decide
  stage transitions, on both the add and edit stage forms, in the account's configured language.
- **FR-010**: Accounts without a configured description for a given stage MUST retain current behavior
  with no new forced automatic transition introduced by this feature for that stage.
- **FR-011**: No stage-transition or conversational-pacing rule introduced by this feature may hardcode
  a specific keyword, phrase, or business condition; all matching MUST rely on operator-authored stage
  descriptions and general conversational guidance.

### Key Entities

- **Pipeline Stage Description**: Operator-authored free text per stage that documents when an
  opportunity belongs in that stage; now doubles as the basis the AI agent uses to decide on outcome
  matches, with a UI hint communicating this dual purpose.
- **Conversation Turn Outcome**: The observable result of a single exchange with the lead (e.g.,
  refusal, postponement, silence, confirmation, scheduling) that gets compared against stage
  descriptions.
- **Opportunity Stage Transition**: The act of moving an opportunity from one pipeline stage to
  another, which may carry side effects (e.g., automatic human handoff on entering the qualified
  stage) that must not be duplicated by separate agent actions.
- **Qualification Data**: Structured values (including dates/scheduling details) the lead provides
  during conversation that satisfy a stage's requirements and that the agent must record using its
  existing tools.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Conversations where the lead clearly declines or postpones the proposed action, against
  a stage description covering that scenario, result in the opportunity landing in the
  disqualification review queue rather than remaining stuck in an earlier stage.
- **SC-002**: Conversations where the lead confirms the proposed action and has already supplied all
  required qualification data result in the opportunity reaching the qualified stage in the same turn
  the confirmation is given, with zero instances of a handoff being used instead on the grounds of a
  missing tool.
- **SC-003**: Zero Scout responses in reviewed conversation samples contain more than one question.
- **SC-004**: Zero Scout responses that present new qualification-relevant information end without a
  question or next step, except where the lead signaled a pause.
- **SC-005**: Zero Scout responses expose an internal opportunity identifier, technical field name, or
  system log-style phrasing when confirming an action.
- **SC-006**: Zero Scout responses recite a field's full list of allowed values as a multiple-choice
  menu when requesting that value.
- **SC-007**: Accounts with no stage descriptions configured show no behavior change compared to
  before this feature.
- **SC-007a**: Zero opportunities that have already reached the qualified stage are automatically
  moved back to an earlier stage or to disqualification by outcome matching.
- **SC-008**: The pipeline stage description hint is visible on both the add and edit stage forms, in
  English and Portuguese, without altering existing save behavior.

## Assumptions

- The pipeline stage configuration (including per-stage descriptions and the qualified/disqualified
  stage roles) and the opportunity-management tools Scout already has access to remain functionally
  unchanged by this feature; only the guidance the agent receives about using them changes.
- The automatic human handoff that occurs when an opportunity enters the qualified stage is an
  existing behavior this feature relies on rather than introduces.
- Verifying agent behavior against real conversation transcripts is a manual/scripted smoke-test
  activity outside of automated test coverage, since automated tests can confirm instructions were
  delivered to the model but not that the model reliably follows them on every conversation.
- No new qualification or pipeline data fields are introduced; this feature only changes how existing
  configured data (stage descriptions, allowed value lists, qualification fields) is used and
  communicated.
