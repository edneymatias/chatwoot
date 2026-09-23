# Feature Specification: Contact Memory Handoff Pretext Guardrail

**Feature Branch**: `077-contact-memory-handoff-guardrail`

**Created**: 2026-09-22

**Status**: Ready

**Input**: User description: "docs/kanban/ciclo 10/scout/32-contact-memory-handoff-pretext-guardrail/spec-preview.md — Scout treats a contact memory note about a past, already-resolved request for human assistance as sufficient justification to hand off a new, unrelated conversation to a human, even though the current conversation contains no such request and the lead is engaging normally; memory should keep enabling proactive personalization and anticipation, but must stop acting as a standalone handoff trigger."

## Clarifications

### Session 2026-09-23

- Q: Should the embedded origin date on new memory notes also show up as-is in the existing agent-facing Notes view (which already displays its own separate "written X ago" timestamp for every note), or is that dashboard view outside this feature's concern? → A: In scope, accepted as-is — the same note text (with its embedded date) renders in the dashboard's contact Notes view exactly as generated, alongside that view's own independent timestamp; this overlap is an accepted, intentional side effect, and acceptance testing must confirm the date is visible there too.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Stale memory of a resolved request never triggers handoff on its own (Priority: P1)

A contact previously asked, in a now-closed conversation, to speak with a human — Scout handed off
correctly at the time, and a memory note recorded that the contact had asked. Days later, the same
contact starts a brand-new conversation and engages normally: they never repeat the request, and
may even answer a follow-up question vaguely or uncertainly. Today, Scout can cite the old note as
part of its reasoning and hand off this new conversation to a human, even though nothing in the new
conversation itself asked for that. With this feature, a memory note describing a resolved past
request is never, by itself, enough to justify transferring the current conversation.

**Why this priority**: This is the core defect — a resolved event from a closed conversation is
being treated as if it were happening right now, causing Scout to abandon a lead who is actively
engaging and ready to be qualified, and to give the contact a confusing closing message that
references something they never said in the current conversation.

**Independent Test**: Can be fully tested by giving a contact a memory note describing a past,
already-resolved request for human assistance, then running a new conversation where the contact
engages normally and never repeats that request, and confirming Scout continues the normal
qualification flow instead of handing off to a human.

**Acceptance Scenarios**:

1. **Given** a contact whose memory includes a note that they previously asked to speak with a
   human in a prior, closed conversation, **When** the contact starts a new conversation and never
   repeats that request, **Then** Scout does not hand off to a human on the basis of that note alone.
2. **Given** the same contact, **When** Scout responds to a vague or uncertain answer from the
   contact within the new conversation, **Then** Scout continues the qualification flow (or asks a
   clarifying question) instead of transferring to a human by citing the old note as justification.

---

### User Story 2 - A genuine request for a human in the current conversation still hands off immediately (Priority: P1)

A contact explicitly asks, in the conversation they are having right now, to speak with a human.
This must keep producing an immediate handoff exactly as it already does today, with zero
regression introduced by tightening how memory notes are used.

**Why this priority**: The guardrail exists to fix a false trigger, not to make Scout hesitate on a
real one; a fix that weakens or delays a genuine, present-conversation request would trade one bug
for a worse one.

**Independent Test**: Can be fully tested by having a contact — with or without prior memory notes
on file — explicitly ask to speak with a human within the current conversation, and confirming
Scout hands off immediately.

**Acceptance Scenarios**:

1. **Given** a contact with no memory notes on file, **When** the contact asks to speak with a human
   in the current conversation, **Then** Scout hands off immediately.
2. **Given** a contact whose memory includes an unrelated or even contradictory note, **When** the
   contact asks to speak with a human in the current conversation, **Then** Scout hands off
   immediately, unaffected by the memory note.

---

### User Story 3 - Memory keeps powering proactive personalization and anticipation (Priority: P1)

When a returning contact starts a new conversation, Scout already uses memory notes to personalize
its greeting — recalling a past request (e.g., "you asked about our address before") to
proactively anticipate what the contact might want now, including nudging them toward scheduling.
This valuable behavior must not be suppressed as a side effect of tightening how memory is used for
handoff decisions.

**Why this priority**: This is the behavior the fix must protect, not just avoid breaking as an
afterthought — memory-driven personalization is already working correctly in production, and an
overly broad fix (e.g., telling Scout to ignore old notes entirely) would remove real value while
fixing the bug.

**Independent Test**: Can be fully tested by giving a contact a memory note describing a past
request or interest, starting a new conversation, and confirming Scout's response can still
reference that history to personalize its greeting or proactively suggest a relevant next step,
without that reference constituting or requiring a handoff.

**Acceptance Scenarios**:

1. **Given** a contact whose memory includes a note about a past request or interest, **When** the
   contact starts a new conversation, **Then** Scout may reference that history to personalize its
   response and proactively anticipate the contact's likely current interest.
2. **Given** the same scenario, **When** Scout uses a memory note this way, **Then** doing so does
   not, by itself, cause or require a handoff to a human.

---

### User Story 4 - Every memory note shows when it was recorded (Priority: P2)

Each memory note is a summary from a specific past conversation, but today notes carry no visible
date wherever they are used — Scout (and anyone reviewing a contact's memory) cannot tell whether a
note is from three days ago or three months ago. This feature adds a visible origin date to every
new memory note going forward.

**Why this priority**: Dating notes reinforces the primary guardrail (User Story 1) by making a
note's age legible wherever it is used, but the primary fix does not depend on it — it is a
secondary, additive improvement rather than the mechanism the core fix relies on.

**Independent Test**: Can be fully tested by generating a new memory note and confirming it shows a
human-readable date of when it was recorded, wherever that note is later surfaced.

**Acceptance Scenarios**:

1. **Given** a new memory note is generated, **When** it is later surfaced, **Then** it shows a
   human-readable date indicating when it was recorded.
2. **Given** a memory note that already existed before this feature shipped, **When** it is
   surfaced today, **Then** it is shown unchanged, without a retroactively added date.
3. **Given** a new memory note is generated, **When** it is viewed in the dashboard's contact
   Notes view, **Then** the embedded date is visible there too, alongside that view's own
   separate timestamp for the note.

---

### Edge Cases

- What happens when a contact has no memory notes at all (first-ever conversation)? No behavior
  change — there is nothing for the guardrail to act on.
- What happens when a memory note describes something unrelated to a handoff (e.g., a stated
  preference or budget)? Unaffected — it continues to be usable for personalization exactly as
  before.
- What happens when the current conversation's own messages are themselves ambiguous and happen to
  touch a similar topic to an old memory note? Scout decides the handoff outcome using only the
  current conversation's own signal; a related historical note does not turn an otherwise
  insufficient current signal into a sufficient one.
- What happens to a memory note that was itself generated by a past incorrect handoff (which in
  turn cited an even older note)? It remains in the contact's memory unmodified, but under the
  revised interpretation it can no longer, alone, justify a further handoff — the reinforcement
  loop stops producing incorrect transfers going forward even though the note itself is not
  removed or edited.
- What happens to memory notes generated before this feature ships, which carry no date? They
  continue to be shown and used as before; the revised interpretation still applies to them since
  it depends on the note being from a prior conversation, not on whether a date happens to be
  visible.
- What happens when a dated memory note is viewed in the dashboard's contact Notes view, which
  already shows its own separate timestamp for every note? The embedded date appears as part of
  the note's own text there too, alongside that view's existing timestamp — the overlap is
  expected and not a defect.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Scout MUST treat every memory note about a contact as a summary of a previous,
  already-concluded conversation — never as a fact or request active in the current turn.
- **FR-002**: Scout MUST NOT rely on a memory note describing a past request for human assistance,
  by itself, as sufficient grounds to transfer the current conversation to a human; the transfer
  signal MUST come from the contact's own words in the current conversation.
- **FR-003**: Scout MUST remain free to use memory notes to personalize its responses to a
  returning contact and to proactively anticipate what the contact is likely seeking now (including
  inviting the contact toward scheduling), independent of any handoff decision.
- **FR-004**: Scout MUST continue to hand off immediately when the contact explicitly requests
  human assistance within the current conversation, regardless of what memory notes exist for that
  contact.
- **FR-005**: Every memory note generated from this feature onward MUST include a human-readable
  indication of the date it was generated, embedded in the note's own text so it is visible
  everywhere that text is later shown — including both Scout's own context and the dashboard's
  contact Notes view, where it appears alongside that view's separate, independently computed
  timestamp for the same note. The embedded date MUST reflect the conversation's effective
  timezone (the same source Scout already uses for its clock: the conversation/inbox timezone,
  else the account default, else the app default) so a late-evening conversation is never
  mislabeled with the next UTC day.
- **FR-006**: Memory notes generated before this feature ships MUST NOT be retroactively modified
  to add a date; Scout's revised interpretation of memory notes (FR-001, FR-002) applies to them
  regardless.
- **FR-007**: The existing reactive safety-net mechanism that reviews generated responses for
  handoff correctness MUST continue to operate without any change in behavior.
- **FR-008**: This capability MUST be delivered without introducing any new tool, data model,
  schema change, or deterministic/mechanical trigger — the interpretation of memory notes and the
  transfer decision continue to come from Scout's own judgment, guided by updated instructions.

### Key Entities *(include if feature involves data)*

- **Memory Note**: A short, durable summary fact recorded about a contact after a conversation
  concludes (e.g., an interest, objection, or past request). Notes accumulate across all of a
  contact's conversations and are surfaced to Scout at the start of every subsequent conversation
  with that contact, and are also visible to human agents in the contact's Notes view in the
  dashboard. From this feature onward, every newly recorded note also carries a visible origin
  date embedded in its own text, so it appears wherever that text is shown.
- **Handoff Decision**: Scout's per-turn determination of whether the current conversation should
  be transferred to a human. Must be grounded in the current conversation's own signals; memory
  notes may inform tone and anticipation but can never stand alone as the deciding signal.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a review of test conversations reproducing a contact whose memory includes a past,
  already-resolved request for human assistance, engaging normally in a new conversation that
  contains no such request of its own, Scout completes the normal qualification flow instead of
  transferring to a human in every conversation of the reviewed sample.
- **SC-002**: In the same review, a contact who explicitly asks for human assistance within the
  current conversation is still transferred to a human immediately in every conversation of the
  reviewed sample — zero regression from today's behavior.
- **SC-003**: A returning contact with relevant memory notes continues to receive a personalized,
  anticipatory response referencing that history at the same rate observed before this change —
  zero reduction in proactive personalization.
- **SC-004**: 100% of memory notes generated after this change carry a human-readable origin date
  wherever they are surfaced.
- **SC-005**: A sample review of conversations transferred to a human after this change finds zero
  cases where the stated justification is a memory note with no corresponding signal in the current
  conversation's own messages.

## Assumptions

- "Scout" refers to the existing AI conversational assistant that already has a per-contact memory
  capability (durable summary notes carried across conversations) and an existing human-handoff
  capability, both already in production.
- Only accounts/assistants with the memory capability enabled generate and receive memory notes;
  assistants without it are unaffected by this change, since they have no notes to guard against.
- The existing reactive safety-net mechanism that reviews generated responses for handoff
  correctness already exists and requires no changes for this feature.
- Preventing a memory note generated by a past incorrect handoff from causing a further incorrect
  handoff (the reinforcement-loop risk observed in production) is achieved through Scout's revised
  interpretation of memory notes (FR-001/FR-002), not by deduplicating or suppressing note
  generation itself; deduplicating semantically repeated notes is out of scope for this feature.
- A known, unrelated defect where a specific kind of internal note occasionally fails to render in
  the conversation dashboard timeline is out of scope for this feature and is tracked separately.
- Verification relies on the same conversation-replay and prompt-behavior test conventions already
  established for prior, similar guardrail fixes.
