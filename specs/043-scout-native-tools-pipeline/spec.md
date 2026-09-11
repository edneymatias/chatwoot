# Feature Specification: Scout Native Tools & Message Pipeline

**Feature Branch**: `043-scout-native-tools-pipeline`

**Created**: 2026-08-19

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 9/scout/02-native-tools-and-pipeline/spec63.md" (Phase 2 of
the Scout AI agent engine — see master doc `docs/kanban/ciclo 9/scout/spec60.md` §2, §4, §5, §8,
§10). Depends on Phase 1 (`Scout`/`ScoutInbox`/`ScoutTool` models and `ruby_llm` client integration,
`specs/042-scout-core-data-model/`), which is already implemented.

## Clarifications

### Session 2026-08-19

- Q: When new messages keep arriving before the debounce window closes, does the window reset (restart the countdown from the latest message) or stay fixed (fire at a fixed time after the first message, regardless of later arrivals)? → A: Sliding — each new message resets the window; processing fires N seconds after the *last* message in the burst.
- Q: Should a runtime failure during the actual LLM call (network error, provider 5xx, timeout) also trigger the fail-safe hand-to-human path, or is fail-safe limited to the pre-call quota/API-key checks? → A: Yes — adopt the same strategy as Captain (`Captain::Conversation::ResponseBuilderJob`), which wraps the whole response-generation run and hands off on any `StandardError` while the conversation is still `pending`, not just pre-call checks.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A qualifying conversation flows end-to-end through the Scout (Priority: P1)

A lead sends one or more WhatsApp messages to a Scout-enabled inbox. Instead of replying to every
message immediately, the system waits briefly to let a burst of messages settle, then produces a
single reply that reflects the whole burst, using tools to update the sales pipeline (create/update
the Opportunity, move its stage, update the contact, leave an internal note, or hand the conversation
to a human) as appropriate for what the lead said.

**Why this priority**: This is the core value of the feature — without it, a Scout is just a
configuration record from Phase 1 with no live behavior. Every other story in this phase depends on
this pipeline existing.

**Independent Test**: Can be fully tested by sending a real (or simulated) WhatsApp message to a
Scout-enabled inbox and observing exactly one Scout reply per burst of messages, with any resulting
Opportunity/contact/note changes matching what the lead's messages justified.

**Acceptance Scenarios**:

1. **Given** a Scout-enabled inbox with no in-flight processing, **When** a lead sends a single
   incoming message, **Then** the system waits for the debounce window before invoking the Scout, and
   produces exactly one response.
2. **Given** a Scout-enabled inbox with no in-flight processing, **When** a lead sends three messages
   in rapid succession within the debounce window, **Then** the Scout is invoked exactly once for the
   whole burst, not once per message.
3. **Given** a debounce window that is already counting down for a conversation, **When** another
   message from the same lead arrives before the window closes, **Then** the window resets and
   restarts its countdown from that new message, so processing fires only after the lead has gone
   quiet for a full window.
4. **Given** a qualifying conversation in progress, **When** the lead provides information that
   justifies creating or updating the Opportunity, moving its stage, or updating the contact, **Then**
   the Scout calls the corresponding native tool and the change is persisted before the Scout's reply
   is sent.
5. **Given** an incoming message with an audio or image attachment, **When** the Scout processes the
   buffered turn, **Then** the attachment is included in the request sent to the LLM provider instead
   of being ignored.
6. **Given** an inbox that is currently outside its configured business hours, **When** the Scout
   processes a turn, **Then** the out-of-office status is made available to the Scout's reply without
   blocking or delaying the response itself.

---

### User Story 2 - A lead from a paid ad keeps its campaign attribution through qualification (Priority: P1)

A lead clicks a WhatsApp ad (CTWA) and is routed to a Scout-enabled inbox. The Scout qualifies the
lead over several turns, then creates or updates an Opportunity for them. The Opportunity must carry
the same campaign/creative attribution (thumbnail, headline, campaign) that the fork's existing
referral-attribution pipeline already extracts from the lead's first message — not a separate or
divergent computation.

**Why this priority**: Preserving ad attribution is the primary business driver for Scout on the
commercial funnel (per the master spec's stated purpose); an Opportunity that loses this data
defeats the point of qualifying ad-driven leads with an AI agent.

**Independent Test**: Can be fully tested by simulating a first incoming message carrying a referral
payload, running a qualification conversation through the Scout, and confirming the resulting
Opportunity's attribution fields match what the existing referral-attribution service would have
produced from that same first message, independent of how many turns the qualification took.

**Acceptance Scenarios**:

1. **Given** a conversation whose first incoming message carries a referral payload, **When** the
   Scout's `manage_opportunity` tool creates an Opportunity for that conversation, **Then** the
   Opportunity's campaign attribution fields (platform, source id, headline, body, thumbnail) match
   what the existing referral-attribution pipeline extracts from that same message.
2. **Given** an Opportunity already created with referral attribution, **When** the Scout later
   updates that Opportunity (e.g., adding qualification data) in a later turn, **Then** the original
   attribution fields remain unchanged.

---

### User Story 3 - No conversation is ever stuck waiting on the bot (Priority: P1)

Whenever the Scout cannot produce a response — because its account has run out of allotted responses,
its configured API key fails, or the provider itself fails mid-call (network error, outage, timeout)
— the conversation is immediately handed over to the human queue, instead of sitting unanswered. The
sales team is alerted with an internal note explaining why. This mirrors how the fork's existing
Captain feature already guarantees a handoff on any unhandled error during response generation, not
just its own pre-call checks.

**Why this priority**: This is the fork's explicit fail-safe guarantee (master spec §4). A stalled
conversation with no human visibility is the single worst outcome this feature must prevent, on par
with the qualification pipeline itself.

**Independent Test**: Can be fully tested by forcing a Scout's quota to zero, supplying an invalid API
key, or simulating a provider error mid-call, and sending an incoming message, then confirming the
conversation status changes and an internal note is created in every case, with no dependency on a
successful LLM call.

**Acceptance Scenarios**:

1. **Given** a Scout whose `responses_quota` is exhausted, **When** an incoming message is processed,
   **Then** the LLM is never called, the conversation moves out of `pending` status, and an internal
   note alerting the sales team is created.
2. **Given** a Scout whose configured API key is invalid or rejected by the provider, **When** an
   incoming message is processed, **Then** the same hand-to-human outcome occurs as in the quota-
   exhausted case.
3. **Given** a Scout that passes both pre-call checks, **When** the LLM provider call itself fails
   (network error, provider outage, timeout, or any other unhandled error during response generation),
   **Then** the same hand-to-human outcome occurs as in the quota-exhausted case.
4. **Given** a conversation that is not currently in `pending` status, **When** a fail-safe condition
   is triggered, **Then** the system does not attempt to force it back to `pending` or otherwise
   corrupt its existing status.

---

### User Story 4 - A qualified or lost lead leaves a memory for whoever picks it up next (Priority: P2)

When a Scout hands a conversation to a human (successful handoff) or is forced to hand off via the
fail-safe path, it summarizes what it learned about the contact during qualification, so the next
person (or the next Scout run) working with that contact has that context immediately, without
re-asking the same questions.

**Why this priority**: This materially improves handoff quality and avoids redundant questioning, but
the pipeline is fully functional without it — a human can still work the conversation using its
message history alone. Secondary to the core pipeline and fail-safe guarantee.

**Independent Test**: Can be fully tested by enabling `feature_memory` on a Scout, running a
qualification conversation to a handoff (human-initiated or fail-safe), and confirming a new contact
note is created summarizing that conversation, then confirming a subsequent Scout or Captain run for
the same contact sees that note in its context. Independently, disabling `feature_memory` and
repeating the same flow must produce no note.

**Acceptance Scenarios**:

1. **Given** a Scout with `feature_memory` enabled, **When** it hands a conversation to a human via
   its `handover_to_human` tool, **Then** a contact note summarizing the qualification is created.
2. **Given** a Scout with `feature_memory` enabled, **When** a fail-safe hand-to-human occurs, **Then**
   a contact note summarizing the qualification is created.
3. **Given** a Scout with `feature_memory` disabled, **When** either handoff path occurs, **Then** no
   contact note is created.
4. **Given** a contact with a note produced by a prior Scout run, **When** a later Scout or Captain
   run builds its context for that same contact, **Then** that note is visible in the context supplied
   to the LLM.
5. **Given** a qualification conversation still in progress (no handoff yet), **When** the Scout
   completes an intermediate turn, **Then** no contact note is generated for that turn (notes are only
   generated at handoff, not on every turn).

---

### Edge Cases

- What happens when new messages keep arriving before the debounce window closes? The window slides —
  each new message resets the countdown, so processing only fires once the lead has gone quiet for a
  full window, never mid-burst.
- What happens when a Scout-enabled inbox receives a message while a previous debounce window for the
  same conversation is still open? The system must not enqueue a second, independent processing pass
  for the same conversation — the existing window's reset (above) already accounts for the new
  message.
- What happens when the LLM provider call itself fails at runtime (network error, provider outage,
  timeout) after both pre-call checks (quota, API key) already passed? The same fail-safe hand-to-
  human path is triggered as for the pre-call checks — the whole response-generation run is treated as
  a single unit that must either succeed or fail safely, matching how the fork's Captain feature
  already handles this.
- What happens when `move_opportunity_stage` is called with a lost outcome but no Opportunity exists
  yet for the conversation? The tool call must fail gracefully and not crash the turn — the Scout's
  response continues, describing that no opportunity exists.
- What happens when `handover_to_human` is called without an explicit `assignee_id`/`team_id`? The
  system falls back to the Scout's configured default handover team.
- What happens when both the quota-exhausted and invalid-API-key fail-safe conditions occur on the
  same turn? The outcome is identical either way — a single hand-to-human with a single alert note,
  not two.
- What happens when a Scout is invoked for a conversation the account has already resolved or closed
  outside the bot's knowledge? The pipeline must not resurrect a closed conversation into `pending`
  purely because a stray message arrived.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST process an incoming WhatsApp message to a Scout-enabled inbox through a
  debounce buffer, so that a burst of messages arriving close together produces one Scout turn, not
  one per message.
- **FR-002**: System MUST NOT enqueue a second, redundant processing pass for a conversation whose
  debounce window is already open.
- **FR-002a**: Each new incoming message for a conversation whose debounce window is already open MUST
  reset that window's countdown (sliding window), so processing fires only after the configured
  window has elapsed since the *last* message in the burst, not the first.
- **FR-003**: Before invoking the LLM, the system MUST check that the Scout has available response
  quota (`quota_available?`) and that its configured API key is present; if either check fails, the
  system MUST follow the fail-safe path (FR-013–FR-014) instead of calling the LLM.
- **FR-003a**: System MUST also follow the same fail-safe path (FR-013–FR-014) when the LLM
  provider call itself fails at runtime (network error, provider outage, timeout, or any other
  unhandled error during response generation) after the pre-call checks in FR-003 already passed —
  the entire response-generation run, not just the pre-call checks, is covered by the fail-safe
  guarantee, mirroring the fork's existing Captain feature.
- **FR-004**: System MUST detect audio and image attachments on the buffered incoming message(s) and
  include them in the request sent to the LLM provider.
- **FR-005**: System MUST determine whether the inbox is currently out of office and make that
  information available to the Scout's response, without delaying or blocking the response on it.
- **FR-006**: System MUST build the Scout's request context from the Scout's persona/system prompt,
  its configured product/knowledge data, and the contact's existing notes/context, and MUST call the
  LLM with that context plus the set of tools enabled for this phase.
- **FR-007**: On a successful LLM response, system MUST increment the Scout's `responses_consumed`
  counter by one.
- **FR-008**: System MUST provide a native tool that creates or updates an Opportunity for the current
  conversation (title, stage, estimated value, custom attributes), reusing the fork's existing
  referral-attribution pipeline for campaign/creative data rather than recomputing it.
- **FR-009**: System MUST provide a native tool that moves an Opportunity's pipeline stage and,
  when the outcome is a loss, records the reason.
- **FR-010**: System MUST provide a native tool that updates the conversation's contact (name, email,
  phone, custom attributes).
- **FR-011**: System MUST provide a native tool that creates an internal (private) note on the
  conversation with content supplied by the Scout.
- **FR-012**: System MUST provide a native tool that hands the conversation to a human (specific
  assignee, team, or the Scout's default handover team) with a reason, without the Scout continuing
  to respond afterward.
- **FR-013**: When a fail-safe condition (FR-003 or FR-003a) triggers, system MUST verify the
  conversation is currently `pending` before acting, then move it out of `pending` and create an
  internal alert note explaining the hand-to-human — without assuming the underlying handoff mechanism
  performs that status check itself.
- **FR-014**: System MUST NOT call the LLM at all when a fail-safe condition (FR-003) is already
  detected for the turn before the call would have started.
- **FR-015**: When `feature_memory` is enabled on a Scout, system MUST generate a summarizing contact
  note at the moment of a successful human handoff (native tool) and at the moment of a fail-safe
  handoff, reusing the fork's existing contact-notes generation mechanism rather than a new
  implementation.
- **FR-016**: System MUST NOT generate a contact note on any turn that is not a handoff (human or
  fail-safe), when `feature_memory` is enabled.
- **FR-017**: When `feature_memory` is disabled on a Scout, system MUST NOT generate any contact note
  at handoff.
- **FR-018**: The Scout data model MUST be extended with whatever configuration fields this phase's
  pipeline depends on but Phase 1 did not yet add — a debounce window duration, a memory-generation
  toggle, and qualified/unqualified stage routing and default handover-team fields — without altering
  any core (non-custom) table.

### Key Entities

- **Scout (extended)**: Gains the configuration fields this phase's pipeline reads at runtime that
  were not required until now — debounce window duration, the `feature_memory` toggle, qualified/
  unqualified stage routing hints, and a default handover team.
- **Opportunity (referral-attributed)**: Created or updated by the `manage_opportunity` tool; its
  campaign/creative attribution is derived from the conversation's first referral-carrying message via
  the existing attribution pipeline, and must remain unchanged by later qualification turns.
- **Contact note (Scout-generated)**: A note summarizing a qualification conversation, generated only
  at handoff (human or fail-safe) when `feature_memory` is enabled, visible to later Scout/Captain
  context building for the same contact.
- **Debounce buffer**: The Redis-backed mechanism that groups messages arriving within a Scout's
  configured window into a single processing turn per conversation, sliding (resetting) that window on
  every new message until the lead goes quiet.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A burst of messages sent within a Scout's debounce window produces exactly one Scout
  reply, regardless of how many individual messages were sent in that burst or how long the lead keeps
  sending messages that keep resetting the window.
- **SC-002**: 100% of Opportunities created by the Scout from a referral-carrying first message carry
  attribution fields identical to what the fork's existing referral-attribution pipeline would produce
  for that same message.
- **SC-003**: 100% of turns where the Scout's quota is exhausted, its API key is invalid, or the LLM
  provider call fails at runtime result in the conversation leaving `pending` status and gaining
  exactly one alert note — never staying stuck in `pending` and never producing more than one alert per
  triggering turn.
- **SC-004**: 100% of `move_opportunity_stage` calls with a loss outcome persist a `lost_reason` on the
  Opportunity.
- **SC-005**: With `feature_memory` enabled, 100% of handoffs (human or fail-safe) produce at least one
  new contact note visible to subsequent context-building for that contact; with `feature_memory`
  disabled, 0% of handoffs produce a note.

## Assumptions

- Phase 1 (`specs/042-scout-core-data-model/`) is complete and its `Scout`/`ScoutInbox`/`ScoutTool`
  models and `ruby_llm` client integration are available as a foundation; this phase only adds the
  configuration fields it specifically needs (FR-018) on top of that model, not a redesign of it.
- This phase is scoped to WhatsApp inboxes, matching the master spec's primary channel; other channel
  types are not explicitly handled or tested here.
- No external REST/webhook tool execution (`call_custom_api`) is part of this phase — only the five
  native Ruby tools listed in FR-008–FR-012. Deferred to a later phase.
- No UI exists yet for configuring Scouts, their tools, or their product/knowledge data — all
  configuration continues to happen via console/seed, as in Phase 1.
- No follow-up/re-engagement job exists yet — a qualifying conversation that goes quiet simply stays
  wherever the last turn left it; re-engagement is a later phase.
- Production availability of `ActiveRecord::Encryption` keys is a dependency of a later phase, not
  built here; this phase can be developed and tested in an environment where encryption is already
  configured (e.g., local dev with keys via `bin/rails db:encryption:init`).
- "The existing referral-attribution pipeline" refers to the fork's already-implemented
  `Custom::ReferralAttributionService` / `Custom::AutomationRules::ActionService` referral extraction —
  this phase calls into it and does not reimplement or fork its logic.
- "The existing contact-notes generation mechanism" refers to the fork's already-implemented
  contact-notes service (currently used by the Captain feature) — this phase reuses it against a
  Scout/conversation pair rather than duplicating its prompt or generation logic.
