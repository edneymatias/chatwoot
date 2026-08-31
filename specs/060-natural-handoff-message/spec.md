# Feature Specification: Natural Handoff Message

**Feature Branch**: `060-natural-handoff-message`

**Created**: 2026-08-30

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 10/scout/20-automatic-handoff-reevaluation/spec80.md — Fase 20: Mensagem de Handoff Natural e Contextual. Today every human handoff (whether decided by the assistant itself or triggered automatically when an opportunity reaches the qualified pipeline stage) shows the customer the exact same fixed sentence, regardless of what actually happened in the conversation. This breaks the natural tone the rest of the conversation has. This feature makes the assistant's own closing text become the customer-facing handoff message — never both messages together, never silently discarded — without reopening the earlier 'asks a question and transfers anyway' problem."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Contextual closing message on assistant-initiated handoff (Priority: P1)

A lead is chatting with the assistant. Partway through, the assistant determines the conversation
needs a human (it lacks an answer, context is insufficient, or the lead asks for a human) and
decides to transfer. Instead of receiving a generic, disconnected sentence, the lead sees a closing
message that reflects what was actually discussed and confirms what was registered, followed by a
human continuing the conversation.

**Why this priority**: This is the core complaint driving the feature — the flat, repetitive
handoff phrasing breaks the conversational tone that the rest of the interaction has, on the most
common handoff path (the assistant's own judgment call).

**Independent Test**: Start a conversation that leads the assistant to decide a human is needed;
confirm the final message the lead sees is a natural closing statement grounded in that
conversation, not the old fixed phrase, and that no other message repeats the fixed phrase
alongside it.

**Acceptance Scenarios**:

1. **Given** a conversation where the assistant decides a human agent is needed, **When** the
   assistant produces its final turn, **Then** the customer sees exactly one closing message, and
   that message is the assistant's own text for that turn (not the old generic sentence).
2. **Given** the assistant's closing turn text, **When** it is shown to the customer, **Then** it
   confirms what has been registered so far and explains a human will continue from here.

---

### User Story 2 - Contextual closing message on automatic qualification handoff (Priority: P1)

A lead's opportunity automatically reaches the qualified pipeline stage during the conversation
(a mechanical, event-driven trigger unrelated to what the assistant "decided" in that turn). The
lead still needs to be handed off to a human, and should see a natural closing message consistent
with the conversation, not the same disconnected fixed sentence used today.

**Why this priority**: This is the second handoff path in current production use and shares the
same customer-facing quality problem; both paths must behave consistently so the fix is not
partial. This mechanical trigger is also the safety net that guarantees a human is always looped
in even if the assistant's own judgment fails, so its message quality matters just as much.

**Independent Test**: Drive a conversation so the opportunity reaches the qualified stage
mid-conversation; confirm the customer-facing handoff message is the assistant's own turn text
rather than the fixed phrase, using the same behavior as User Story 1.

**Acceptance Scenarios**:

1. **Given** an opportunity that reaches the qualified stage during a conversation, **When** the
   handoff to a human is triggered, **Then** the customer sees a closing message sourced from the
   assistant's own text for that turn, not the fixed generic sentence.
2. **Given** this automatic trigger, **When** a human takes over, **Then** the mechanism that
   decided a handoff was needed is unchanged from current behavior — only the message shown to the
   customer differs.

---

### User Story 3 - Safe fallback when no usable closing text exists (Priority: P2)

The assistant's response for a turn ending in handoff cannot be reliably interpreted (parsing
fails) or comes back effectively empty. The customer must still receive a clear, non-broken closing
message rather than silence or an error.

**Why this priority**: Without this safeguard, the main feature (using the assistant's own text)
would introduce a regression risk — a broken or missing handoff message — on top of the existing
tone problem it's meant to fix. This preserves the "fail closed" behavior already relied upon
elsewhere in the system.

**Independent Test**: Force a turn ending in handoff where the assistant's response is unparseable
or blank; confirm the customer still receives the existing fixed generic message, unchanged from
today's behavior.

**Acceptance Scenarios**:

1. **Given** a turn ending in handoff whose response text cannot be parsed, **When** the handoff
   message is sent, **Then** the customer sees the existing fixed generic sentence.
2. **Given** a turn ending in handoff whose response text is blank, **When** the handoff message is
   sent, **Then** the customer sees the existing fixed generic sentence.

---

### User Story 4 - No question left unanswered at handoff (Priority: P2)

A lead reaches the end of a conversation that results in handoff. The closing message must not ask
the lead anything, since there is no further opportunity for the lead to answer before a human
joins — repeating the "asks a question and transfers anyway" problem this feature must not
reopen.

**Why this priority**: This is a known prior failure mode (documented from earlier production
incidents) that this feature must explicitly avoid reintroducing while switching to model-authored
closing text.

**Independent Test**: Review a sample of real historical conversations that ended in handoff (via
replay) and confirm none of the resulting closing messages end in a question directed at the
customer.

**Acceptance Scenarios**:

1. **Given** a conversation ending in handoff, **When** the closing message is generated, **Then**
   it does not pose a question to the customer.

---

### User Story 5 - Unchanged behavior for the independent consistency-review handoff path (Priority: P3)

A separate mechanism reviews the whole conversation history (independent of any single turn) and
decides on its own that a handoff is warranted. Because this decision isn't tied to a specific
turn's closing text, the customer continues to see the existing fixed generic message on this path,
unchanged.

**Why this priority**: Lower priority because it's an explicit "preserve current behavior" decision
rather than new functionality, included to guard against accidental scope creep when this feature
is implemented.

**Independent Test**: Trigger a handoff via the standalone consistency-review path and confirm the
customer-facing message is still the existing fixed generic sentence.

**Acceptance Scenarios**:

1. **Given** a handoff decided by the standalone conversation-review mechanism, **When** the
   handoff message is sent, **Then** the customer sees the existing fixed generic sentence, not any
   assistant-authored text.

### Edge Cases

- What happens when the assistant's turn text is unparseable or blank at the moment of handoff?
  The customer must receive the existing fixed generic message (User Story 3).
- What happens when a handoff is triggered by a system-level failure (quota exhausted, unhandled
  error) rather than a normal turn? The customer must receive the existing fixed generic message,
  same as today — this path is unaffected by this feature.
- What happens if the assistant's closing text technically satisfies the "no question" guideline
  but is otherwise off-tone or inaccurate? Out of scope — this feature relies on the prompt-level
  guideline as the only control; no additional automated content validation is introduced.
- What happens in playground/simulation runs? The existing simulated confirmation text is
  unaffected by this feature.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When a conversation is handed off to a human — whether via the assistant's own
  explicit decision or via the opportunity automatically reaching the qualified pipeline stage —
  the customer-facing handoff message MUST be the assistant's own closing text for that turn.
- **FR-002**: The customer-facing handoff message MUST never contain both the assistant's own
  closing text and the existing fixed generic sentence together; exactly one of the two is shown.
- **FR-003**: When the assistant's turn text cannot be reliably interpreted or is blank, the system
  MUST fall back to the existing fixed generic handoff message.
- **FR-004**: The assistant's closing text for any turn ending in handoff MUST be guided to never
  pose a question to the customer, since the customer has no opportunity to answer before the
  transfer completes.
- **FR-005**: When handoff is triggered by the standalone conversation-consistency review mechanism
  (independent of the current turn's text), the customer-facing message MUST continue to use the
  existing fixed generic sentence, unchanged from current behavior.
- **FR-006**: Handoffs triggered by system-level failures (quota exhaustion, unhandled errors, or
  failure to interpret the response) MUST continue to always use the existing fixed generic
  message.
- **FR-007**: This feature MUST NOT change which mechanism decides that a handoff is needed
  (assistant's own judgment vs. automatic pipeline-stage qualification) — only which message the
  customer sees.
- **FR-008**: Playground/simulation runs MUST continue to show their existing simulated
  confirmation text, unaffected by this feature.

### Key Entities

- **Handoff message**: The single message the customer sees when a conversation is transferred to
  a human; either the assistant's own closing text for that turn, or the existing fixed generic
  sentence, never both.
- **Conversation turn**: One cycle of the assistant producing a response, which may end in a
  decision to hand off to a human.
- **Opportunity qualification event**: The automatic, event-driven trigger that fires when an
  opportunity reaches the qualified pipeline stage during a conversation, independent of the
  assistant's own turn-level decision.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of human handoffs where the assistant produced usable closing text show that
  text to the customer, instead of the old generic sentence.
- **SC-002**: 0% of handoff messages combine the assistant's closing text and the fixed generic
  sentence in the same message.
- **SC-003**: 0% of assistant-authored handoff messages end in a question directed at the customer,
  verified by replaying the known historical evidence conversation that previously exhibited this
  problem (`conversation_id 43` / `display_id 41`).
- **SC-004**: 100% of handoffs where the assistant's response is unparseable or blank still deliver
  a complete, non-blank closing message to the customer.
- **SC-005**: 100% of handoffs triggered by the standalone consistency-review mechanism continue
  showing the existing fixed generic message, with no observable change from current behavior.

## Assumptions

- Only the content of the customer-facing handoff message changes; the decision of which mechanism
  triggers a handoff (assistant's own judgment vs. automatic pipeline-stage qualification) is out
  of scope and stays exactly as it works today.
- The prompt-level guideline instructing the assistant to write a natural closing statement and
  never ask a question when a turn ends in handoff is treated as a sufficient control; no
  additional automated validation or sanitization of the assistant's text (e.g., pattern-matching
  for question marks) is introduced by this feature.
- The existing fixed generic handoff sentence and its translations are reused as-is for every
  fallback case; this feature does not change their wording.
- The standalone conversation-consistency review mechanism (which decides handoffs independently of
  a single turn's text) is unaffected by this feature and keeps using the fixed generic message,
  since it has no turn-specific closing text to draw from.
