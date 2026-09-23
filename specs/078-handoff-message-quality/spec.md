# Feature Specification: Response Auditor Handoff Message Quality

**Feature Branch**: `078-handoff-message-quality`

**Created**: 2026-09-23

**Status**: Draft

**Amendment (2026-09-23, post-implementation)**: T007–T011 (Phase 3) shipped a carve-out that only
excluded the literal scenario from the source production case (`display_id 45007`) — the customer
*declining* one qualification question. A second, unrelated production conversation
(`display_id 132`) surfaced the mirror-image false positive: the customer *accepting/confirming* an
option the assistant itself offered (an appointment time) in a short reply was still misclassified as
`out_of_scope_commercial_request`, because nothing in User Story 1's original scope, the prompt
carve-out, or its test excluded that pattern — even though the codebase already documented the same
"terse reply to an offered choice" failure mode for a different reason
(`response_auditor.rb`'s comment on `evaluate_action`, re: `human_offer_accepted`). User Story 1,
FR-001, and the Edge Cases below have been broadened accordingly (see Requirements and Edge Cases);
the fix and a regression test were added directly (no separate feature branch), consistent with this
being the same defect class this feature already owns.

**Input**: User description: "docs/kanban/ciclo 10/scout/33-response-auditor-handoff-message-quality/spec-preview.md — when the response auditor's classifier hands a conversation off to a human, the internal transfer note shows a raw English enum code instead of a readable reason, and the customer sees one generic cold message regardless of why the handoff happened; separately, the classifier's out_of_scope_commercial_request criterion is vague enough that a customer who declines a single point-blank qualification question, after already showing clear commercial intent earlier in the same conversation, gets misclassified as out of scope and handed off instead of being kept in the normal flow."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Classifier stops misreading a single declined question as out-of-scope (Priority: P1)

A customer has already asked for help twice, described a concrete need, and answered every
qualification question the assistant asked — then declines or defers exactly one specific
question (for example, whether they already have a quote elsewhere, or whether they're ready to
schedule). Today the classifier can read that one decline as the customer's request being "outside
commercial scope" and hands the conversation off to a human. With this feature, that single,
isolated decline — on a conversation that already demonstrated valid commercial intent — is no
longer enough by itself to trigger an out-of-scope handoff; the assistant keeps engaging normally
(acknowledging the customer's pace and leaving the door open, per the existing conversational
guardrails) instead of ending the conversation.

**Why this priority**: This is the actual root-cause defect — a customer who wants to buy is being
prematurely and incorrectly routed away from the automated flow into a human queue, sometimes with
no human actually available promptly. Every other issue in this feature only affects how clearly
that (right-or-wrong) handoff is communicated; this one affects whether the handoff should have
happened at all.

**Independent Test**: Can be fully tested by replaying a conversation where the customer requests
help, states a concrete need, answers qualification questions, then declines or defers exactly one
specific question — and confirming the classifier no longer flags it as `out_of_scope_commercial_request`
and no handoff occurs. Verifiable independently of the message-wording changes in User Story 2 and 3.

**Acceptance Scenarios**:

1. **Given** a conversation where the customer has asked for help, described a concrete need, and
   answered prior qualification questions, **When** the customer declines or defers exactly one
   further qualification question (e.g., "I don't want to schedule yet", "I haven't gotten a quote
   elsewhere"), **Then** the classifier does not hand the conversation off as
   `out_of_scope_commercial_request`, and the assistant continues the conversation normally.
2. **Given** a conversation where the customer has already demonstrated commercial intent and the
   assistant offers a choice between options (e.g., an appointment time, a period of day, a contact
   method), **When** the customer accepts or confirms one of the offered options in a short reply,
   **Then** the classifier does not hand the conversation off as `out_of_scope_commercial_request`,
   and the assistant continues the conversation normally.
3. **Given** a conversation where the customer is already an existing customer describing an
   ongoing, unrelated service issue, filing a complaint, or asking a purely informational question
   with no commercial intent, **When** the response auditor evaluates the conversation, **Then**
   the classifier still correctly identifies it as `out_of_scope_commercial_request` and hands it
   off (no regression in genuine cases).

---

### User Story 2 - Internal team reads a clear handoff reason instead of a raw code (Priority: P2)

When the classifier hands a conversation off to a human, it leaves an internal note recording why.
Today that note shows the raw internal reason code exactly as used in code (e.g.
`out_of_scope_commercial_request`) — an English identifier never meant for human reading. A team
member reviewing the handoff has to guess what it means. With this feature, the note shows a short,
readable label describing the actual reason, in the team's own working language.

**Why this priority**: Operational clarity for the team reviewing handoffs — doesn't change whether
a handoff happens, only how understandable the audit trail is once it does. Independent of, but
complementary to, the classification-accuracy fix in User Story 1.

**Independent Test**: Can be fully tested by triggering a classifier-driven handoff for each of the
four defined reasons and confirming the resulting internal note shows a readable label (not the raw
enum code) in the account's configured language, regardless of the wording changes in User Story 3.

**Acceptance Scenarios**:

1. **Given** a classifier-driven handoff is triggered for any of the four defined reasons, **When**
   the internal transfer note is created, **Then** the note shows a short, readable label describing
   that reason instead of the raw enum code.
2. **Given** an account configured with a given working language, **When** a classifier-driven
   handoff note is created, **Then** the reason label appears in that account's language, regardless
   of the language the customer used in the conversation.
3. **Given** a classifier-driven handoff occurs with an unrecognized or missing reason value,
   **When** the internal note is created, **Then** the note falls back to today's existing generic
   "reason not provided" text, unchanged.

---

### User Story 3 - Customer receives a warm, reason-specific closing message (Priority: P3)

When the classifier hands a conversation off, the customer currently sees one fixed, generic
message ("Transferring you so another agent can assist.") no matter why the handoff happened or
what they just told the assistant. It doesn't acknowledge urgency, frustration, or anything the
customer already shared. With this feature, the customer sees one of a small set of warmer,
reason-appropriate closing messages, still fully automated and consistent for a given reason.

**Why this priority**: Customer-facing tone polish — improves the experience of a handoff that is
(now, after User Story 1) more likely to be a genuinely correct one, but doesn't change routing
behavior or team-facing clarity.

**Independent Test**: Can be fully tested by triggering a classifier-driven handoff for each of the
four defined reasons and confirming the customer-facing message matches that reason's dedicated
text, in the conversation's language, independent of the internal note wording in User Story 2.

**Acceptance Scenarios**:

1. **Given** a classifier-driven handoff is triggered for any of the four defined reasons, **When**
   the closing message is sent to the customer, **Then** the customer sees the message dedicated to
   that specific reason instead of the current single generic message.
2. **Given** a conversation conducted in a given language, **When** a classifier-driven handoff
   message is sent, **Then** the message appears in that conversation's language, regardless of the
   account's own default working language.
3. **Given** a classifier-driven handoff occurs with an unrecognized or missing reason value,
   **When** the closing message is sent, **Then** the customer sees today's existing generic
   fallback message, unchanged.

---

### Edge Cases

- What happens when the handoff reason value is null or not one of the four currently defined
  reasons? → Both the internal note and the customer-facing message fall back to today's existing
  generic text, unchanged (Users Story 2 & 3, Scenario 3).
- What happens when the account's working language and the conversation's language differ (e.g., a
  Portuguese-speaking team account serving a customer who wrote in English)? → The internal note
  label and the customer-facing message may legitimately appear in different languages from each
  other, since each is resolved independently for its own audience; this is expected, not a defect.
- What happens for a handoff triggered by the customer directly asking for a human, or by the
  assistant's own offer being accepted (the other two of the four defined reasons)? → Same
  mechanism applies: readable note label and reason-specific message, just with different content
  for those reasons.
- What happens for the two handoff paths not driven by this classifier (the assistant's own
  free-text tool-triggered handoff, and the qualified-stage handoff)? → Unaffected; both already
  show human-authored or otherwise-addressed text and are out of scope for this feature.
- What happens if a customer declines or defers **two or more** distinct qualification questions
  across the conversation, or shows other signals beyond a single decline? → Not covered by the
  User Story 1 narrowing; the classifier retains discretion to flag out-of-scope in that case,
  subject to its existing double-confirmation requirement.
- What happens when a customer accepts/confirms an option the assistant offered (e.g., picks a
  proposed appointment time) instead of declining anything? → Also covered by User Story 1 (added in
  the 2026-09-23 amendment, `display_id 132`): this MUST NOT be classified as
  `out_of_scope_commercial_request` either — the same "terse reply to an offered choice" pattern
  already guarded against for `human_offer_accepted` now applies to this reason too.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The classifier's `out_of_scope_commercial_request` criterion MUST NOT, by itself,
  classify a conversation as out-of-scope solely because the customer (a) declined or deferred
  exactly one specific qualification-related question, or (b) accepted or confirmed an option the
  assistant itself offered (e.g., an appointment time, a period of day, a contact method) in a short
  reply — when the customer has already demonstrated valid commercial intent earlier in the same
  conversation.
- **FR-002**: The revised `out_of_scope_commercial_request` criterion MUST continue to correctly
  identify genuine out-of-scope conversations (e.g., an existing customer's unrelated ongoing
  service issue, a complaint, or a purely informational question with no commercial intent).
- **FR-003**: The existing requirement that a classifier-driven handoff be confirmed by two
  independent classifier evaluations before it takes effect MUST remain unchanged.
- **FR-004**: For each of the four defined classifier handoff reasons, the internal transfer note
  MUST show a short, human-readable label describing that reason instead of the raw internal reason
  code.
- **FR-005**: The internal transfer note's reason label MUST be resolved in the account's own
  configured working language, independent of the language used in the conversation.
- **FR-006**: For each of the four defined classifier handoff reasons, the customer-facing closing
  message MUST be a message dedicated to that specific reason, replacing today's single generic
  message for classifier-driven handoffs.
- **FR-007**: The customer-facing closing message MUST be resolved in the conversation's own
  language, independent of the account's configured working language.
- **FR-008**: When a classifier-driven handoff note is created for one of the four defined
  reasons, both the note's shared prefix text and its reason label MUST be resolved in the same
  language, so the note is never a mix of two languages. This does not extend to the other two
  existing handoff paths' notes (raw human-authored reason text, or a missing/blank reason), whose
  prefix rendering MUST remain unchanged per FR-012.
- **FR-009**: When the handoff reason is missing or not one of the four defined reasons, both the
  internal note and the customer-facing message MUST fall back to today's existing generic text,
  unchanged.
- **FR-010**: Readable note labels and reason-specific customer messages MUST be available in
  Portuguese and English, with both languages kept in sync (every reason has both a note label and
  a customer message defined in both languages).
- **FR-011**: Resolving the readable note label and the reason-specific customer message MUST be
  fully deterministic and MUST NOT require any additional AI/model call beyond the classification
  that already determined the reason.
- **FR-012**: This feature's message-quality changes (FR-004 through FR-011) apply only to handoffs
  triggered by the response auditor's classifier; they MUST NOT change the behavior of the other two
  existing handoff paths (the assistant's own direct request for a human, and the qualified-stage
  handoff).

### Key Entities

- **Handoff Reason**: One of four fixed classifications the auditor's classifier can assign to a
  conversation it decides to hand off (customer explicitly asked for a human; customer accepted an
  earlier offer to be transferred; customer showed repeated frustration or the conversation is
  stuck in a loop; customer's request is outside the assistant's commercial scope). Each reason has
  a dedicated internal-note label and a dedicated customer-facing closing message, each available in
  Portuguese and English.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A customer who (a) declines or defers exactly one qualification question, or (b)
  accepts/confirms an option the assistant offered, after already showing valid commercial intent in
  the same conversation, is not handed off as `out_of_scope_commercial_request` — verified by
  replaying the conversations that surfaced this defect (`display_id 45007` for (a), `display_id 132`
  for (b)) and confirming no handoff occurs in either case.
- **SC-002**: Genuine out-of-scope conversations (existing customer with an ongoing issue,
  complaint, purely informational question) continue to be classified and handed off correctly,
  with no observed regression versus current behavior.
- **SC-003**: 100% of classifier-driven handoff internal notes, across all four defined reasons,
  show a human-readable label rather than a raw reason code.
- **SC-004**: 100% of classifier-driven handoff customer-facing messages, across all four defined
  reasons, show a message dedicated to that reason rather than today's single generic message.
- **SC-005**: Portuguese and English translation files remain fully synchronized — every reason
  label and customer message key introduced for this feature exists, with real content, in both
  languages.

## Assumptions

- The four handoff reasons and their identifiers are the ones already defined by the response
  auditor's classifier today; adding, removing, or renaming reasons is out of scope for this
  feature.
- Only Portuguese and English are in scope, matching this fork's existing supported languages for
  user-facing and team-facing strings.
- Team-facing text (the internal note label) is resolved by the account's own configured working
  language; customer-facing text (the closing message) is resolved by the conversation's own
  language — these may legitimately differ for the same handoff, matching how the rest of the
  handoff flow already resolves each audience's language independently.
- Draft wording for the four reason labels and four customer messages exists as a starting point
  and may be refined for tone during implementation, as long as each remains specific to its reason
  and distinct from the others (no reverting to one shared generic message).
- Personalizing the customer-facing message further (e.g., inserting the account's name) is a
  nice-to-have refinement, not required for this feature to be considered complete.
- The two other existing handoff paths (the assistant directly asking to bring in a human, and the
  automatic handoff once a conversation reaches a qualified stage) already use different,
  previously-decided mechanisms for their own wording and are unaffected by this feature.
