# Feature Specification: Scout Contact Identity Detection

**Feature Branch**: `061-scout-contact-identity`

**Created**: 2026-09-02

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 10/scout/19-contact-identity-and-conversation-labeling/spec81.md"

## Clarifications

### Session 2026-09-02

- Q: Should Scout skip asking for the visitor's real name in a turn where the conversation is already ending in a handoff to a human? → A: Yes — the identity question must never appear in a turn that ends in handoff/transfer to a human, extending the existing "no questions when a turn ends in handoff" guardrail. Scout may still update the contact record with a name it already has (e.g. one given earlier in the same turn), but must never ask for the name and then transfer in the same turn.
- Q: When Scout has both an unanswered identity question and a pending qualification question competing for the single question-per-turn slot, which one takes priority? → A: The identity question takes priority — once a placeholder/handle-like name is detected, Scout should prioritize asking for the visitor's preferred name over a pending qualification question, even if that delays qualification (subject to the handoff-suppression rule above and the "not forced into the first message" rule).
- Q: Does the judgment-based guardrail for non-website channels (User Story 3) apply uniformly to every channel other than the website widget (WhatsApp, Instagram, email, API, etc.), or only to conversational/chat-style channels? → A: Applies uniformly to all channels other than the website widget — no closed list of covered channels in the requirement, consistent with the existing fork-wide practice of not hardcoding per-channel rules.
- Q: Should Scout be barred from asking the identity question in its very first response (as originally drafted, mirroring a "don't force it into the first message" rule), or is asking it right away actually the desired flow? → A: There is no "not on the first message" restriction. The normal flow of a good sales/service conversation is: if you don't already know who you're talking to, ask early — ideally in the very first response — so you can address the person by name for the rest of the conversation; if the name is already known, greet them by name instead (e.g. "Olá, Maria, que bom te ver de novo"). This applies to both the website-widget case and the judgment-based non-website-channel case, and supersedes the earlier "not forced into the first message" wording.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ask a site visitor for their real name (Priority: P1)

A visitor starts a conversation through the website widget without identifying themselves. The
system has already assigned them an automatically generated placeholder name (e.g.
"empty-meadow-50"). Today, Scout (the AI sales agent) never notices this and completes the entire
qualification conversation without ever asking who it's actually talking to. Instead, Scout should
recognize that the stored name is a placeholder and, as early as possible — ideally in its very
first response to the visitor — politely ask what they'd like to be called, so it can address them
by name for the rest of the conversation, and save the real name once given.

**Why this priority**: This is the core gap the feature exists to close — confirmed in two real
qualified-lead conversations where the operator noticed the agent never learned the customer's
name. It directly affects lead quality and how personal/credible the sales conversation feels.

**Independent Test**: Start a website widget conversation as a new, unidentified visitor, go
through a normal qualification flow, and confirm the agent asks for a name in its first response
and records the answer once given — independent of any other change in this feature.

**Acceptance Scenarios**:

1. **Given** a website widget contact whose stored name is a system-generated placeholder,
   **When** Scout sends its first response to the visitor, **Then** Scout asks how they'd like to
   be called (subject to Acceptance Scenario 4's handoff exception).
2. **Given** a website widget contact with a placeholder name who has just answered Scout's
   question with their real name, **When** the answer is received, **Then** the contact's name is
   updated to the value they provided.
3. **Given** a website widget contact with a placeholder name, **When** Scout has already asked
   for their name earlier in the same conversation, **Then** Scout does not ask again.
4. **Given** a website widget contact with a placeholder name whose response would end in a
   handoff to a human (e.g. qualification just completed), **When** Scout sends that response,
   **Then** it does not ask for the visitor's name in that same response.
5. **Given** a website widget contact with a placeholder name and a pending qualification question
   Scout would otherwise ask next, **When** Scout has not yet asked for the visitor's name and the
   turn does not end in handoff, **Then** Scout asks for the name instead of the qualification
   question in that turn.

---

### User Story 2 - Never address the customer by their placeholder name (Priority: P1)

While a contact's name is still an unclaimed placeholder, Scout must never use that value to
address the customer directly (e.g. never say "Hi, Empty Meadow!"). This must hold at every point
in the conversation, not only up until the moment the real name is asked for.

**Why this priority**: Greeting a real customer by a nonsense system-generated string is
immediately visible, undermines trust, and is the most damaging symptom of the underlying gap —
independent of whether or how the name gets corrected.

**Independent Test**: Start a website widget conversation as an unidentified visitor and review
every agent message for direct address using the placeholder value; none should appear, regardless
of conversation length or outcome.

**Acceptance Scenarios**:

1. **Given** a website widget contact with a placeholder name, **When** Scout sends any message
   during the conversation, **Then** the message never uses the placeholder value to address the
   customer.

---

### User Story 3 - Use judgment on channels without a reliable system signal (Priority: P2)

On channels other than the website widget (e.g. WhatsApp, Instagram, email, API-created
conversations), the contact's name comes from the channel's own profile data, which may already be
a real name, a nickname, or a system/app-assigned handle — there's no reliable, deterministic way
to tell which. For these channels, Scout should use judgment: if the available name looks like a
system identifier or handle rather than a person's name, ask politely how the person prefers to be
addressed, as early as possible (ideally in the first response, same as User Story 1), following
the same non-intrusive rules otherwise (no repeating the question if already asked, and no asking
at all when the name already looks like a real person's name).

**Why this priority**: This closes the same underlying gap for the majority of real-world traffic
(non-website channels), but depends on model judgment rather than a deterministic signal, so it
carries more risk of false positives/negatives and is scoped as a secondary priority after the
deterministic website case.

**Independent Test**: Start conversations on a non-website channel with (a) a contact whose profile
name is clearly a real person's name and (b) a contact whose profile name looks like a generic
handle or system identifier; confirm the agent asks for a preferred name only in case (b), and only
once.

**Acceptance Scenarios**:

1. **Given** a non-website-channel contact whose available name looks like a system identifier or
   handle, **When** Scout sends its first response to the contact, **Then** Scout politely asks how
   the person prefers to be addressed (subject to the handoff exception in FR-011).
2. **Given** a non-website-channel contact whose available name already looks like a real person's
   name, **When** the conversation proceeds, **Then** Scout does not ask an identity question.
3. **Given** a non-website-channel contact who has already been asked their preferred name earlier
   in the conversation, **When** the conversation continues, **Then** Scout does not ask again.

---

### Edge Cases

- What happens when a website widget contact's name is a real name that happens to contain a
  number or hyphen (e.g. a two-word name)? The agent must not treat it as a placeholder and must
  not ask an unnecessary identity question.
- What happens when the visitor never responds to the identity question, or the conversation ends
  before Scout gets a chance to ask? The conversation should proceed normally; there is no
  requirement to force the question before continuing.
- What happens on a non-website channel when the profile name is ambiguous (neither clearly a
  system handle nor clearly a real name)? Judgment is left to the agent; the feature does not
  define a hard boundary for these channels since no deterministic signal exists.
- What happens if the visitor already provided their real name earlier in the conversation history
  (e.g. said "I'm Maria") but the stored contact name is still the placeholder? Behavior for this
  case follows the same judgment-based, non-repeating approach as asking generally — Scout should
  not ask again for information already given in the visible conversation history.
- What happens when the same response would both need to ask for the visitor's name and hand the
  conversation off to a human (e.g. qualification just completed, or the lead asked for a human)?
  Scout must never ask for the name and then transfer in the same turn — the identity question is
  suppressed for that turn, consistent with the existing rule that a handoff-ending turn contains no
  questions at all (see Clarifications).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST be able to recognize when a website-widget contact's stored name
  matches the shape of the automatically generated placeholder name (two lowercase word-like
  segments joined by a hyphen, followed by a short number), independent of the specific words used.
- **FR-002**: When a website-widget contact's name is recognized as a placeholder, Scout MUST be
  instructed never to use that name to address the customer directly.
- **FR-003**: When a website-widget contact's name is recognized as a placeholder, Scout MUST
  politely ask the visitor how they'd like to be called as early as possible — ideally in its very
  first response to the visitor. The only thing that suppresses this ask is FR-011 (never in a
  handoff-ending turn); FR-013 does not suppress it either — it only prevents an unrelated rule
  from being misread as suppressing it. FR-005 additionally bounds how many times this ask may
  happen (at most once), independent of when it first happens.
- **FR-004**: When a visitor responds with their preferred name, the system MUST update the
  contact's stored name to the value provided.
- **FR-005**: Scout MUST NOT ask the identity question more than once per conversation, regardless
  of channel.
- **FR-006**: For every channel other than the website widget (including but not limited to
  WhatsApp, Instagram, email, and API-created conversations — no closed list of covered channels),
  Scout MUST use judgment to decide whether the available contact name resembles a system
  identifier or handle rather than a person's name, and if so, ask for the preferred name as early
  as possible (same "ask once, ideally in the first response" behavior as the website-widget case).
- **FR-007**: Contacts whose name is already a real (non-placeholder, non-handle-like) name MUST
  see no behavior change — no identity question, no internal warning, no altered conversation flow.
- **FR-008**: The placeholder-detection capability MUST NOT modify, validate, or normalize the
  contact's name in any way — it only classifies the existing name for the purpose of deciding
  whether to warn/ask.
- **FR-009**: This behavior MUST be unconditional (no per-account or per-agent toggle) once shipped.
- **FR-010**: The automatic name-generation behavior for unidentified website-widget contacts
  itself MUST remain unchanged — this feature only changes whether Scout is made aware of and
  reacts to that existing name.
- **FR-011**: Scout MUST NOT ask the identity question in any turn whose response ends in a handoff
  to a human, regardless of channel — this applies the existing "no questions in a handoff-ending
  turn" rule to the identity question as well. Scout MAY still record a name it already has (e.g.
  provided earlier in the same turn) via the existing contact-update capability before transferring;
  it just MUST NOT ask for it and transfer in the same turn.
- **FR-012**: When Scout has both an unanswered identity question and a pending qualification
  question competing for the same turn's single question slot, the identity question MUST take
  priority — Scout asks for the visitor's preferred name rather than the qualification question,
  subject only to FR-011 (never in a handoff-ending turn).
- **FR-013**: The identity question MUST NOT be treated as one of the account's configured
  qualification fields for the purpose of any existing guidance limiting Scout to asking only about
  configured fields — Scout MUST still ask it even though it is not itself a configured funnel
  field. (Added 2026-09-02 per alignment-audit finding: this guidance already exists and is
  assembled immediately after the contact-context section, so without this exemption the model
  could read the two instructions as being in conflict and suppress the identity question.)

### Key Entities

- **Contact**: The person on the other end of a conversation; relevant attribute is its display
  name, which may be a system-generated placeholder (website widget only), a channel-provided
  profile name/handle (other channels), or a real name provided directly by the person.
- **Conversation**: The message thread between the contact and Scout; relevant for determining
  whether the identity question has already been asked, so it is not repeated.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a replayed real qualification conversation where the contact had a placeholder
  name and Scout previously completed qualification without ever asking for it, Scout now asks for
  the visitor's preferred name in its first response, before any qualification question.
- **SC-002**: Across conversations with placeholder-named website contacts, the placeholder value
  is never used by Scout to address the customer.
- **SC-003**: Contacts with an already-real name experience no additional questions or behavior
  changes compared to current behavior.
- **SC-004**: On non-website channels, contacts whose channel-provided name already looks like a
  real person's name are not asked the identity question (no regression on channels like WhatsApp).
- **SC-005**: Within any single conversation, the identity question is asked at most once,
  regardless of channel.

## Assumptions

- The automatically generated placeholder name for unidentified website-widget contacts follows a
  consistent, recognizable shape (two lowercase word segments joined by a hyphen, plus a short
  number), and this shape can be distinguished from genuine two-part real names reliably enough for
  production use, without depending on a fixed dictionary of generated words.
- Asking "as early as possible" is interpreted as Scout's very first response to the contact
  whenever the name is already known to be a placeholder/handle at that point (deterministic on the
  website widget; judgment-based elsewhere) — not deferred to a later point in the conversation.
- Deterministic identity detection is only feasible for the website widget channel, where the
  placeholder-generation mechanism is fully known; other channels rely on the agent's judgment since
  there is no equivalent system-level signal available.
- Saving the customer's provided name reuses the contact-update capability the agent already has
  available, rather than introducing a new one.
- The related idea of tagging/labeling conversations (raised alongside this gap during discovery)
  is explicitly out of scope for this feature per prior product decision, and is not addressed by
  any requirement above.
