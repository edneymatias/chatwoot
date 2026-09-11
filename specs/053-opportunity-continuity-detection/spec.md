# Feature Specification: Opportunity Continuity Detection

**Feature Branch**: `053-opportunity-continuity-detection`

**Created**: 2026-08-27

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 10/scout/14-opportunity-continuity-detection/spec75.md"

## Clarifications

### Session 2026-08-27

- Q: When an automation rule creates a deal for a contact who already has open deal(s), and there's no assistant declaration to validate against, how should the system decide between reusing an existing deal and flagging the case as ambiguous? → A: Apply the identical continuity decision rule as the conversational path, with no rule-specific shortcut. Because a rule has no way to declare which deal it means, it permanently sits in the "no declaration" branch of that rule: auto-create only when the contact has zero open deals; whenever one or more open deals already exist, treat it as ambiguous and flag for a human — never auto-reuse based on candidate count alone.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Continuing a known deal in a brand-new conversation (Priority: P1)

A contact who already has an open deal from a previous, unrelated conversation starts a
completely new conversation (no prior link to that deal) and brings up the same business again.
Today the system has no way to recognize this as the same deal, so it silently opens a duplicate
card. Instead, the assistant should recognize the existing open deal for that contact and update
it rather than creating a second one.

**Why this priority**: This is the core duplication problem the feature exists to solve — it is
silent, compounds over time (every follow-up conversation creates another card), and directly
corrupts the pipeline view humans rely on to manage deals.

**Independent Test**: Can be fully tested by creating a contact with one open deal from a past,
closed conversation, then starting a new conversation as that contact and expressing renewed
interest in the same business — the deal should be updated in place, not duplicated, and only one
open deal for that contact should exist afterward.

**Acceptance Scenarios**:

1. **Given** a contact has exactly one open deal (created from a previous, now-closed
   conversation) and no deal is linked to the current conversation, **When** the contact expresses
   interest in that same business in the current conversation, **Then** the assistant updates the
   existing open deal instead of creating a new one, and no duplicate card appears.
2. **Given** a contact has exactly one open deal already linked to the current conversation via an
   existing conversation-to-deal association (not necessarily the conversation where the deal
   originated), **When** the assistant acts on that deal in the current conversation, **Then** it
   recognizes and updates the already-linked deal rather than creating a duplicate.

---

### User Story 2 - Ambiguous continuity is never auto-resolved (Priority: P1)

When it is not clear-cut whether the current conversation continues an existing deal — because
the contact has more than one open deal, or the assistant's read of "which deal" doesn't match any
of the contact's actual open deals — the system must not guess. It must leave the deal(s)
untouched, flag the situation for a human, and continue the conversation normally in every other
respect.

**Why this priority**: An incorrect automatic guess is worse than no action — it either merges
unrelated business into the wrong deal or silently creates a duplicate anyway. Since this feature
exists specifically to eliminate silent, wrong outcomes, the "don't know" path is as critical as
the "do know" path and must ship together with it.

**Independent Test**: Can be fully tested by giving a contact two open deals and starting a new
conversation that expresses commercial interest without the assistant clearly pointing at one of
them — no deal should be created or modified, and a reviewable flag should appear for a human to
resolve.

**Acceptance Scenarios**:

1. **Given** a contact has two or more open deals, **When** the contact expresses commercial
   interest in the current conversation without the assistant clearly matching it to exactly one
   of those open deals, **Then** no deal is created or modified, a private note explaining the
   ambiguity is recorded, and the conversation continues normally.
2. **Given** the assistant identifies a specific deal to act on, **When** that deal does not
   actually belong to the contact's set of open deals, **Then** the system rejects that choice,
   takes no automatic action, and records the same ambiguity flag rather than trusting the
   assistant's claim at face value.

---

### User Story 3 - New contact, genuinely new deal (Priority: P2)

A contact with no prior deals expresses commercial interest for the first time. The system should
behave exactly as it does today: create a new deal automatically, with no extra friction.

**Why this priority**: This is the existing, already-working baseline behavior. It is included as
a guardrail — the fix for duplication and ambiguity must not regress the simple, common case where
there is nothing to disambiguate.

**Independent Test**: Can be fully tested by using a contact with zero existing deals and
expressing commercial interest — a new deal is created automatically with no ambiguity flag and no
extra steps.

**Acceptance Scenarios**:

1. **Given** a contact has no open deals, **When** the contact expresses commercial interest,
   **Then** a new deal is created automatically without requiring human review.

---

### User Story 4 - Rule-triggered deal creation never silently duplicates either (Priority: P2)

Deals are not only created through the conversational assistant — an automated rule can also
create one directly (for example, in response to a form submission or a tagged event), independent
of the conversational flow. That path has the same blind spot: it only recognizes a deal already
linked to the current conversation, never checks whether the contact already has an open deal from
elsewhere. Because a rule has no assistant judgment available to declare which specific deal it
means, the same continuity decision applies without a rule-specific shortcut: a rule only creates a
deal automatically when the contact has zero open deals; whenever the contact already has one or
more open deals, the rule-triggered creation is treated as ambiguous and flagged for a human — the
same outcome as the conversational path's "no declared match" case.

**Why this priority**: Leaving this second creation path unfixed reintroduces the exact duplication
problem User Story 1 solves, just through a different trigger — the fix is incomplete without it,
but it is lower priority than the conversational path because it affects a narrower, automation-only
slice of deal creation.

**Independent Test**: Can be fully tested by configuring an automation rule that creates a deal for
a contact who already has one open deal, triggering that rule, and confirming no duplicate deal is
created and no existing deal is silently modified — instead a reviewable ambiguity flag is
recorded, matching the conversational path's behavior when candidates exist without a declared
match.

**Acceptance Scenarios**:

1. **Given** a contact already has one or more open deals, **When** an automation rule that creates
   a deal for that contact fires, **Then** no deal is created or modified automatically, and a
   private note explaining the ambiguity is recorded.
2. **Given** a contact has no open deals, **When** an automation rule that creates a deal for that
   contact fires, **Then** a new deal is created, matching today's behavior.

### Edge Cases

- A contact has one open deal and one already closed (won/lost) deal; only the open one counts as
  a continuity candidate — the closed deal is never reused or reopened.
- The assistant recognizes commercial interest partway through a conversation that started on an
  unrelated topic (e.g., a billing question that turns into a sales inquiry) — continuity detection
  must trigger at that point in the conversation, not only at its start.
- Two conversations for the same contact happen concurrently and both attempt to act on deals at
  nearly the same time — the ambiguity/validation check must be based on the true current state of
  the contact's open deals at the moment of the attempt, not a stale read.
- The assistant's stated choice of deal is syntactically well-formed but refers to a deal that
  belongs to a different contact entirely — treated the same as "not a valid candidate": rejected,
  flagged, no automatic action.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST, whenever a deal is about to be created or acted upon for a contact
  during a conversation, first look for that contact's other open deals rather than considering
  only a deal already tied to the current conversation.
- **FR-002**: When a contact has zero open deals, the system MUST create a new deal automatically,
  with no human review required — unchanged from current behavior.
- **FR-003**: When a contact has exactly one open deal and the assistant's identification of that
  deal matches it, the system MUST update that existing deal instead of creating a new one,
  automatically and without requiring human review.
- **FR-004**: When the assistant identifies a specific deal to act on, the system MUST verify that
  identification against the contact's actual open deals before acting — an identification that
  does not match any real open deal for that contact MUST be treated as invalid, never acted upon
  automatically.
- **FR-005**: When the assistant does not identify a specific deal to act on but the contact has
  one or more open deals, or when the assistant identifies a deal that fails validation (FR-004),
  the system MUST NOT create or modify any deal automatically. Instead it MUST record a reviewable,
  human-facing flag explaining the ambiguity and continue the conversation normally otherwise.
- **FR-006**: The system MUST make the contact's open deals visible to the assistant as structured,
  identifiable information (not only as narrative memory) so the assistant has a real basis for
  choosing which deal it means, in addition to — not instead of — whatever narrative history about
  the contact the assistant already sees.
- **FR-007**: The system MUST instruct the assistant to consider whether a conversation relates to
  a deal at any point during the conversation, not only at its outset, so a conversation that starts
  on an unrelated topic and later turns commercial is still caught.
- **FR-008**: The automation-rule-triggered deal creation path MUST apply the identical continuity
  decision rule described in FR-001–FR-005 — not a rule-specific shortcut. Because a rule has no
  mechanism to declare which specific deal it means, it MUST behave as the "no declared match" case
  whenever the contact already has one or more open deals: create automatically only when the
  contact has zero open deals, and flag as ambiguous (never auto-reuse) whenever one or more open
  deals already exist, regardless of candidate count.
- **FR-009**: A closed (won or lost) deal MUST never be treated as a continuity candidate for reuse
  — only open deals are eligible.
- **FR-010**: Every automatic outcome of the continuity decision (reuse an existing deal, create a
  new one, or flag as ambiguous) MUST be traceable after the fact to why that outcome occurred —
  it must never look like a silent, unexplained side effect of an unrelated action.

### Key Entities

- **Deal (Opportunity)**: A tracked sales pipeline item belonging to a contact; has an open/closed
  status and a pipeline stage. A contact may legitimately have more than one deal over time, but
  this feature only ever considers a contact's currently *open* deals as reuse candidates.
- **Contact**: The person or account the conversation and the deal both belong to; the anchor used
  to look up continuity candidates, replacing today's narrower conversation-based lookup.
- **Continuity candidate list**: The set of a contact's currently open deals, made visible to the
  assistant at decision time as structured, identifiable entries (not just narrative text) so it
  can point at a specific one.
- **Ambiguity flag**: A reviewable, human-facing record created whenever the system cannot
  deterministically resolve reuse-vs-create; surfaces the reason so a human can resolve it through
  existing deal-review channels.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Zero duplicate open deals are created for the same contact and the same underlying
  business across separate conversations, for all cases where the assistant is able to identify the
  correct existing deal.
- **SC-002**: 100% of situations where the system cannot deterministically tell whether a
  conversation continues an existing deal result in no automatic deal creation or modification —
  never a guess.
- **SC-003**: Every ambiguous case produces a reviewable flag a human can act on, with zero
  ambiguous cases left unflagged.
- **SC-004**: Contacts with no prior deals experience no added friction — a new deal is created
  automatically, exactly as today, with no measurable change in behavior or added steps.
- **SC-005**: The duplication fix and the "never guess" guarantee hold identically for both deal
  creation paths — conversation-triggered and automation-rule-triggered — with no separate, looser
  decision rule for either one.

## Assumptions

- "Open" deal means any deal not yet marked won or lost; the exact set of pipeline stages counted
  as open follows whatever the pipeline already defines today.
- The assistant's own judgment of commercial intent and conversational context (deciding *that* a
  conversation is about a deal at all) is out of scope for this feature; only the reuse-vs-create
  decision *once* commercial intent is recognized is in scope.
- Human resolution of an ambiguous case happens through the existing deal-review workflow (the
  pipeline board and its existing note-based alerts); no new review interface is introduced by this
  feature.
- A contact's identity for continuity-matching purposes is the same contact identity already used
  elsewhere in the system (no new identity/merge logic is introduced).
- Concurrent attempts to act on the same contact's deals are resolved by re-checking true current
  state at the moment of the attempt rather than by introducing new locking/queuing mechanisms not
  already present in the system.
