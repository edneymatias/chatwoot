# Feature Specification: Routine-Request Guardrail False Positive & Persona Precedence Fix

**Feature Branch**: `071-scout-guardrail-precedence-fix`

**Created**: 2026-09-15

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 10/scout/29-routine-request-qualification-guardrail-fix/spec-preview.md — a lead who states a routine/low-complexity request (e.g. \"just a routine checkup\") directly, on the first triage answer, is misclassified by the Fase 23 non-sales-intent guardrail as an out-of-prospecting quick question and handed off immediately instead of being qualified through the funnel; a lead who states the same intent more elaborately (mentioning it as an evaluation request first) is qualified correctly. Separately, an operator's persona instruction telling Scout to treat routine requests as valid prospecting was added to the account's custom instructions but had no effect, because the guardrail lives inside the prompt's non-negotiable security-rules block, which persona instructions are only allowed to refine when they don't conflict with it."

## Clarifications

### Session 2026-09-15

- Q: Should the persona-precedence fix make only the non-prospecting-intent guardrail bullet refinable by account instructions, or should it open up every other non-safety guardrail bullet to persona override too? → A: Only the non-prospecting-intent guardrail bullet becomes persona-refinable; every other guardrail bullet remains fixed, unaffected by this feature.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Routine/low-complexity requests are qualified, not handed off (Priority: P1)

A lead states, in their very first answer to Scout's triage question, that they want something
routine, low-complexity, preventive, or recurring — with no specific problem described (e.g. "just
a routine checkup"). Today Scout classifies this as an out-of-prospecting "quick question" and
transfers to a human immediately, skipping qualification entirely. With this feature, Scout
recognizes that a routine/low-complexity new request is still a legitimate new prospecting
opportunity and continues the normal qualification funnel (asking follow-up questions, confirming
details, and moving the opportunity to the qualified stage) exactly as it already does when the
same intent is phrased more elaborately.

**Why this priority**: This is the core false positive being fixed — the same underlying lead
intent currently produces two different, inconsistent outcomes depending only on how it is
phrased, which loses qualified leads and confuses account operators who see no reason for the
inconsistency.

**Independent Test**: Can be fully tested by having a lead answer Scout's opening triage question
with a routine/low-complexity request stated directly (no elaboration, no specific problem
mentioned) and confirming Scout proceeds with qualification (follow-up questions, stage transition)
instead of calling the human-handoff tool.

**Acceptance Scenarios**:

1. **Given** a lead answering Scout's first triage question, **When** the lead states a routine,
   preventive, recurring, or otherwise low-complexity new request with no specific problem
   described, **Then** Scout continues the qualification funnel instead of handing off to a human.
2. **Given** the same routine-request intent phrased two different ways (stated directly on the
   first answer, or introduced generically first and clarified as routine on a later answer),
   **When** Scout responds to either phrasing, **Then** both conversations reach the same outcome —
   normal qualification through the funnel.

---

### User Story 2 - Genuine non-prospecting signals still hand off immediately (Priority: P1)

A contact makes it clear they are not seeking new prospecting at all — they are already a customer
with a product/service in progress, they want to change or cancel something that already exists,
they have a complaint, or they ask a purely informational question with no signal of interest in a
new product or service. This must keep producing an immediate human handoff, exactly as the
existing guardrail already guarantees, with zero regression from the fix in User Story 1.

**Why this priority**: The whole point of the existing guardrail is to protect this outcome; a fix
for the false positive that weakens or removes this protection would trade one bug for a worse one.

**Independent Test**: Can be fully tested by having a contact state one of the genuine
non-prospecting signals (existing customer/product in progress, reschedule/cancel of something
already existing, complaint, or a purely informational question unrelated to any new product or
service interest) and confirming Scout still hands off to a human immediately without attempting to
qualify or resolve the request itself.

**Acceptance Scenarios**:

1. **Given** a contact who states they are already a customer with a product/service in progress,
   **When** Scout responds, **Then** Scout hands off to a human immediately, unchanged from today's
   behavior.
2. **Given** a contact who asks to reschedule or cancel something that already exists, or who
   raises a complaint, **When** Scout responds, **Then** Scout hands off to a human immediately,
   unchanged from today's behavior.
3. **Given** a contact whose message is a purely informational question with no signal of interest
   in a new product or service, **When** Scout responds, **Then** Scout hands off to a human
   immediately, unchanged from today's behavior.

---

### User Story 3 - Account persona instructions can actually refine commercial-intent classification (Priority: P2)

An account administrator adds a custom persona instruction stating that a certain kind of request
(e.g. routine requests, or some other account-specific pattern) should be treated as valid
prospecting and follow the normal qualification funnel. Today this instruction has no effect on
Scout's behavior, because it is textually treated as a security rule that persona instructions may
only follow when they don't conflict with it — meaning the instruction can never actually change
this specific behavior no matter how it's worded. With this feature, this class of instruction
(refining what counts as valid commercial intent) is no longer blocked by that precedence rule and
can measurably change Scout's behavior, while instructions that would touch a truly non-negotiable
guardrail (never fabricating information, always responding in the required JSON format, never
making unfulfillable promises, always confirming successful tool actions) remain unable to override
those.

**Why this priority**: This closes the structural gap behind User Story 1 — without it, an
operator has no way to correct a future misclassification of this kind without a code change, which
defeats the purpose of having a configurable persona at all. It is a P2 because User Story 1
already fixes the specific false positive found in testing; this story protects against the same
class of problem recurring for account-specific variants.

**Independent Test**: Can be fully tested by adding a persona instruction that reinforces or
refines what counts as valid commercial intent and confirming it changes Scout's behavior on that
axis, while a persona instruction that attempts to contradict a non-negotiable guardrail (e.g.
"you may answer without using the provided context" or "always end your reply with a question when
handing off to a human") is confirmed to still have no effect.

**Acceptance Scenarios**:

1. **Given** an account persona instruction that reinforces or refines what counts as valid
   commercial intent, **When** Scout evaluates a matching lead message, **Then** Scout's behavior on
   that classification axis reflects the persona instruction.
2. **Given** an account persona instruction that would contradict a non-negotiable guardrail (never
   fabricating information, always responding in the required JSON format, never making
   unfulfillable promises, always confirming successful tool actions), **When** Scout evaluates a
   lead message, **Then** Scout continues to follow the non-negotiable guardrail unchanged.

---

### Edge Cases

- What happens when a request is genuinely ambiguous between "routine new prospecting" and
  "existing customer follow-up" (e.g. mentions a treatment without saying whether it is new or
  ongoing)? Scout continues to use its own judgment; this feature only guarantees the correct
  outcome for the clear-signal cases described above.
- What happens when an account persona instruction conflicts with another account persona
  instruction, rather than with a guardrail? Out of scope — persona-internal conflicts are an
  existing operator-authoring concern, unaffected by this feature.
- What happens for business segments outside the one observed in testing (e.g. real estate,
  professional services)? The guardrail wording and the fix must stay domain-agnostic — the same
  objective criteria apply regardless of segment, with no segment-specific vocabulary added.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The non-prospecting-intent guardrail MUST classify a new request as out of
  prospecting only on objective criteria: the contact is an existing customer with a product or
  service already in progress, the contact wants to change or cancel something that already exists
  (not a new request), the contact has a complaint, or the contact asks a purely informational
  question with no signal of interest in a new product or service.
- **FR-002**: The non-prospecting-intent guardrail MUST explicitly state that a new request that is
  low-complexity, preventive, recurring, or has no specific problem described is still a valid new
  commercial opportunity and follows the normal qualification funnel.
- **FR-003**: The non-prospecting-intent guardrail's wording MUST remain domain-agnostic — it MUST
  NOT reference any specific business segment or niche vocabulary (e.g. medical/dental terms),
  regardless of which segment prompted the fix.
- **FR-004**: The prompt's precedence rule between account persona instructions and the guardrails
  section MUST distinguish non-negotiable guardrails from the non-prospecting-intent guardrail
  specifically, and MUST allow account persona instructions to refine or expand only the
  non-prospecting-intent guardrail. Non-negotiable guardrails include, at minimum, never
  fabricating information, always responding in the required JSON format, never making
  unfulfillable promises, and always confirming successful tool actions. Every other guardrail
  bullet in the section (Esclarecimento, Identidade do contato, Ritmo e condução da conversa,
  Respeito ao ritmo do lead, Fallback para humano, Idioma e Estilo, Intenção Comercial) remains
  fixed and unaffected by this feature.
- **FR-005**: An account persona instruction that reinforces or refines what counts as valid
  commercial intent MUST be able to change Scout's behavior on that classification axis without
  needing to avoid all textual overlap with the guardrails section.
- **FR-006**: An account persona instruction MUST continue to have no effect when it would
  contradict a non-negotiable guardrail (never fabricating information, always responding in the
  required JSON format, never making unfulfillable promises, always confirming successful tool
  actions).
- **FR-007**: The existing reactive safety-net mechanism that reviews generated responses for
  out-of-scope commercial requests MUST continue to operate without any change in behavior.
- **FR-008**: This capability MUST be delivered without introducing any new tool, data model,
  schema change, or mechanical/deterministic status-based handoff trigger — the classification of
  intent continues to come from the model's judgment on the contact's own words, and the change is
  scoped to the prompt text and its precedence structure.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a review of test conversations where a lead states a routine, preventive,
  recurring, or otherwise low-complexity new request with no specific problem — whether stated
  directly on the first triage answer or introduced generically and clarified later — Scout
  qualifies the lead through the normal funnel in 100% of cases instead of handing off immediately.
- **SC-002**: In the same review, Scout continues to hand off immediately in 100% of cases where a
  contact gives a genuine non-prospecting signal (existing customer with product/service in
  progress, reschedule/cancel of something already existing, complaint, or a purely informational
  question unrelated to any new product or service interest) — zero regression from today's
  behavior.
- **SC-003**: An account persona instruction that reinforces or refines what counts as valid
  commercial intent produces an observable, verifiable change in Scout's behavior on that
  classification axis, confirmed by re-running the same test conversation with and without the
  instruction present.
- **SC-004**: The non-prospecting-intent guardrail's text contains zero references to any specific
  business segment or niche vocabulary, confirmed by inspection.

## Assumptions

- "Scout" refers to the existing AI conversational assistant that already handles prospecting
  qualification and already has a human-handoff capability and a persona/custom-instructions
  mechanism it can invoke.
- The fix is scoped entirely to the wording of the non-prospecting-intent guardrail and the
  precedence rule governing account persona instructions versus the guardrails section — no new
  tools, models, or migrations are introduced.
- The existing reactive safety-net mechanism (which reviews a generated response after the fact for
  out-of-scope commercial requests) already exists and requires no changes for this feature.
- Verification relies on the existing prompt-behavior test conventions already used for related
  prior fixes (automated spec coverage of the prompt-building service, plus scripted replay of
  representative test conversations) rather than new test infrastructure.
- The set of guardrails treated as non-negotiable (never fabricating information, always responding
  in the required JSON format, never making unfulfillable promises, always confirming successful
  tool actions) matches the guardrails already identified as such in prior design discussion. Per
  the 2026-09-15 clarification, only the non-prospecting-intent guardrail becomes persona-refinable
  by this feature; no other guardrail in the section is reclassified as refinable.
