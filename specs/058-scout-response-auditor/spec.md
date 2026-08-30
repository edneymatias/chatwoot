# Feature Specification: Scout Response Auditor

**Feature Branch**: `058-scout-response-auditor`

**Created**: 2026-08-28

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 10/scout/12-response-auditor/spec78.md"

## Clarifications

### Session 2026-08-28

- Q: Should the "broken promise" detection apply broadly to any future-action promise Scout makes, or be scoped narrowly to just promises of a human handoff? → A: Broad — any future-work promise without a matching tool call (e.g., "I'll check your account and update you") is detected and corrected/escalated the same way as an unfulfilled handoff promise, matching the reference architecture's original scope.
- Q: When Scout claims an action is already completed and the corresponding tool actually was called but returned an error/failure, does that count as a false completed-action claim? → A: Yes — a tool call that ran but failed did not actually complete the action, so the claim is still treated as false and goes through the same correction/escalation path.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Customer never receives a false claim about a completed action (Priority: P1)

A customer is chatting with Scout about their opportunity (e.g., asking Scout to move the deal to
a new stage, or to record where the lead came from). In real testing, Scout has repeatedly told
the customer something was already done ("I've updated your opportunity", "I've moved it to
Scheduled", "I've recorded the source") when in fact nothing was saved — the underlying update
never happened. The customer believes their request was completed and does not follow up, so the
opportunity silently falls out of the sales process with incorrect or stale data. This story
ensures that when Scout's reply falsely claims a completed action, the system catches it before
the customer sees it and gets a human involved instead of letting the false claim stand.

**Why this priority**: This is the exact failure pattern that ended the passive-monitoring
approach and motivated this feature. A customer acting on a false "already done" claim causes
silent data loss and lost trust — worse than an honest "I couldn't do that."

**Independent Test**: Can be fully tested by running a real qualification conversation where the
customer asks Scout to perform an opportunity/stage update, and where the update tool does not
end up being called for that turn, then confirming the customer never receives a reply claiming
the action was completed — the conversation instead is repaired or handed to a human.

**Acceptance Scenarios**:

1. **Given** an active Scout conversation, **When** Scout's drafted reply claims an
   opportunity/stage/data update was already completed but no corresponding update actually
   happened in that turn, **Then** the system does not deliver that claim to the customer as-is —
   it attempts to produce a corrected reply first.
2. **Given** an active Scout conversation, **When** Scout's drafted reply claims an
   opportunity/stage/data update was already completed and the matching tool was called but the
   call itself failed or returned an error, **Then** the claim is treated as false the same way as
   if the tool had never been called, and the system attempts a corrected reply first.
3. **Given** the system attempted a corrected reply after detecting a false completed-action
   claim, **When** the corrected reply still makes an unsupported completed-action claim, **Then**
   the conversation is handed to a human agent instead of any version of the false claim reaching
   the customer.
4. **Given** this detection capability is turned off for an account, **When** Scout drafts a reply
   with a false completed-action claim, **Then** the reply is delivered exactly as today (no
   change in behavior).

---

### User Story 2 - Promised actions, including human handoff, always actually happen (Priority: P2)

A customer asks for a human, or Scout tells the customer it will do something next — "I'll get a
human agent for you," or "I'll check that and update you" — but in real testing these promises
were sometimes not backed by anything real: no handoff was triggered, no follow-up action was
taken, and the conversation just sat unanswered indefinitely. This story ensures that whenever
Scout's reply promises future work (whether that's bringing in a human or any other action) without
the matching action actually happening, the system catches it — and specifically for a broken
promise of human handoff (or an explicit customer request for a human, even if Scout's reply
doesn't mention it), a real handoff to a human agent actually happens so the conversation never
gets stuck waiting on a promise that was never kept.

**Why this priority**: This is the second confirmed real-world failure pattern. It's ranked below
User Story 1 because a stuck-pending conversation, while bad, is a visible/detectable failure a
team can notice and manually rescue; a false "already done" claim causes silent, hard-to-detect
data corruption that looks like success.

**Independent Test**: Can be fully tested by running a conversation where Scout's drafted reply
promises a human handoff without the corresponding handoff being triggered, a separate conversation
where Scout's drafted reply promises some other future action without any matching tool call, and a
third conversation where the customer explicitly asks for a human agent — confirming the handoff
promise and the explicit request both end up as a real human handoff, and the other broken promise
ends up corrected or escalated, with no conversation left waiting indefinitely.

**Acceptance Scenarios**:

1. **Given** an active Scout conversation, **When** Scout's drafted reply promises to bring in a
   human agent but no handoff was actually triggered in that turn, **Then** the system attempts a
   corrected reply, and if the promise still isn't backed by a real handoff, the conversation is
   handed to a human agent so it never sits unresolved.
2. **Given** an active Scout conversation, **When** Scout's drafted reply promises some other
   future action (not a human handoff) with no matching tool call in that turn, **Then** the system
   attempts a corrected reply, and if the promise still isn't backed by a matching action, the
   conversation is handed to a human agent so it never sits unresolved on a broken promise.
3. **Given** an active Scout conversation, **When** the customer's message is an explicit request
   for human assistance (regardless of what Scout's drafted reply says), **Then** the conversation
   is routed to a human agent through the normal handoff experience (not treated as a system
   failure).
4. **Given** this detection capability is turned off for an account, **When** any scenario above
   occurs, **Then** behavior is unchanged from today (no proactive handoff or correction beyond
   what Scout's own reply and tool use already trigger).

---

### User Story 3 - Operators can enable this safety net per account without any risk to accounts that don't opt in (Priority: P3)

An operator managing a Scout-enabled account wants the confidence that Scout's replies are
double-checked against what actually happened before those replies reach customers. They should be
able to turn this checking on for their account. Accounts that don't turn it on must see zero
behavior change and zero added cost.

**Why this priority**: This is what makes User Stories 1 and 2 safely deployable — a way to enable
the safety net deliberately, per account, and confirm it doesn't regress accounts that stay on the
existing behavior. It's lower priority than 1/2 because the checking behavior itself is the
product value; this is the operational control around it.

**Independent Test**: Can be tested by comparing conversation behavior and token/response
accounting for the same account with the capability off vs. on, confirming no functional or
billing-relevant difference when off, and confirming the User Story 1/2 protections apply only
when on.

**Acceptance Scenarios**:

1. **Given** an account with this capability turned off (the default), **When** any number of
   Scout conversations happen, **Then** there is no extra processing, no extra delay, and no
   behavior difference compared to before this feature existed.
2. **Given** an account with this capability turned on, **When** Scout completes a turn normally
   (no false claims, no missed handoff), **Then** the customer experience is unaffected — the
   extra checking is invisible when nothing is wrong.

---

### Edge Cases

- What happens when the double-checking step itself fails (e.g., an error occurs while verifying
  the reply, or the check produces an unusable result)? The customer must still receive Scout's
  original reply — a broken safety net must never be the reason a working reply doesn't reach the
  customer.
- What happens when the corrected reply Scout produces after a detected problem is itself
  re-checked and takes a very long time or is attempted repeatedly? The system must place a hard
  cap on how many correction attempts happen in a single customer turn, so a customer is never left
  waiting indefinitely for a reply while the system loops on retries.
- What happens when the customer explicitly asks for a human at the same time the reply also
  contains a false completed-action claim? The explicit human request takes priority and is
  resolved through the normal handoff path rather than being treated as an inconsistency needing
  repair.
- What happens to conversations that are no longer active/pending by the time a check would run
  (e.g., a human already took over mid-turn)? The checks do not run against conversations that are
  no longer waiting on Scout — they must not interfere with or override a human agent who has
  already stepped in.
- How is this counted for account usage? Verifying and correcting replies must never count as
  extra delivered responses toward an account's response usage — only the single reply that
  actually reaches the customer counts, exactly as it does today.
- What happens when Scout claims an action is complete and the matching tool was actually called
  but the call itself failed or returned an error? The claim is still treated as false — the
  action did not actually complete — and goes through the same correction/escalation path as if
  the tool had never been called at all.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide a way to detect, before a Scout reply reaches the customer,
  when that reply claims an opportunity/stage/data update was already completed but no matching
  update actually succeeded during that turn — a tool call that ran but returned an error/failure
  does not count as the action having been completed.
- **FR-002**: The system MUST provide a way to detect, before a Scout reply reaches the customer,
  when that reply promises any future action — including but not limited to handing the
  conversation to a human — with no matching action actually occurring during that turn.
- **FR-003**: The system MUST provide a way to detect, independent of what Scout's reply text
  says, when the customer's own message is an explicit, unambiguous request for human assistance.
- **FR-004**: When an explicit human request is detected per FR-003, the system MUST route the
  conversation to a human agent through the same handoff experience already used for other
  handoffs (not treated as, or logged as, a system error).
- **FR-005**: When a false completed-action claim (FR-001) or an unfulfilled action promise
  (FR-002) is detected, the system MUST attempt to produce a corrected reply before giving up on
  delivering a working response to the customer.
- **FR-006**: If, after one correction attempt, the reply still contains a false completed-action
  claim or an unfulfilled action promise, the system MUST hand the conversation to a human agent
  rather than deliver the reply or continue attempting corrections indefinitely.
- **FR-007**: All of the checking behavior described in FR-001 through FR-006 MUST be controllable
  by a single per-account setting, defaulting to off, so that existing accounts see no behavior
  change unless an operator opts in.
- **FR-008**: When the per-account setting is off, the system MUST behave identically to today: no
  additional checking, no additional delay, no additional cost.
- **FR-009**: If any step of the checking or correction process fails unexpectedly (e.g., an
  internal error, or an unusable result from a check), the system MUST deliver Scout's original
  reply to the customer unchanged and record the failure for operators, rather than blocking or
  altering delivery of that reply.
- **FR-010**: The system MUST NOT introduce any new way for a customer-visible message to be
  created outside of the reply-delivery and handoff mechanisms that already exist today.
- **FR-011**: The corrective step described in FR-005 MUST NOT be visible to the customer as a
  separate message — only the final, corrected (or handed-off) outcome is customer-facing.
- **FR-012**: The system MUST count at most one delivered response per customer turn toward the
  account's response usage, regardless of how many internal checking or correction attempts
  occurred during that turn.
- **FR-013**: Checking behavior described in FR-001 through FR-006 MUST only run against
  conversations that are still awaiting a Scout reply; it MUST NOT run against, or affect,
  conversations that a human agent has already taken over during the same turn.

### Key Entities

- **Account auditing setting**: A per-account on/off control that determines whether the
  reply-checking behavior in this feature is active for that account's Scout conversations.
  Defaults to off.
- **Turn's tool activity**: The record of what Scout actually did during the current customer
  turn (which actions/tools ran, if any, and whether each succeeded or failed) — used as the
  ground truth that a drafted reply is checked against, so claims of "already done" can be
  confirmed or refuted; a tool call that ran but failed does not count as the action having
  succeeded.
- **Detected inconsistency**: An outcome of checking a drafted reply against what actually
  happened — either "consistent," "claims future work with no matching action," or "claims a
  completed action with no matching action" — that determines whether the reply is delivered,
  corrected, or escalated to a human.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When this capability is enabled, 100% of customer-visible Scout replies that falsely
  claim an opportunity/stage/data update was already completed are either corrected or replaced
  with a human handoff before reaching the customer — none reach the customer unmodified.
- **SC-002**: When this capability is enabled, 100% of conversations where Scout promises a future
  action (a human handoff or any other action) with no matching action taken end up either
  corrected to not make the unsupported promise or handed to a human agent — none are left
  indefinitely unresolved after such a promise.
- **SC-003**: When this capability is enabled, an explicit customer request for a human agent
  results in a real handoff in the same turn, without depending on Scout's own reply text to
  trigger it.
- **SC-004**: When this capability is disabled (the default), Scout conversation behavior, latency,
  and response usage accounting are indistinguishable from behavior before this feature existed.
- **SC-005**: A failure inside the checking process itself never prevents a customer from receiving
  a reply — the rate of "no reply delivered due to checking failure" is 0%.
- **SC-006**: No customer turn incurs more than one delivered, customer-visible reply and no more
  than one unit of response usage, regardless of how many internal correction attempts occurred.

## Assumptions

- This feature builds on the existing single interception point for Scout's structured reply
  (established in the prior "system prompt guardrails" work) and the existing tool pipeline
  (established in the prior "native tools and pipeline" work); both are assumed to already be in
  place and unchanged in their externally observable behavior.
- The reasons an account might want to auto-escalate to a human (e.g., explicit request, accepted
  offer of a human, repeated frustration, off-topic request) are scoped to Scout's commercial
  qualification use case and are not required to match the breadth of reasons a general-purpose
  support assistant might use.
- "Explicit request for human assistance" means an unambiguous ask (e.g., "let me talk to a
  person", "I want a human"), not a general expression of dissatisfaction that could reasonably be
  resolved by Scout continuing the conversation.
- The corrective attempt described in FR-005/FR-006 is limited to one retry-and-recheck cycle per
  problem type per turn; this is a reasonable bound to guarantee the customer is never kept
  waiting indefinitely, and is not intended to maximize the chance of eventually producing a
  passing reply at the cost of response time.
- Historical results of these checks (which conversations were flagged, corrected, or escalated)
  are recorded for operator troubleshooting (e.g., logs) but do not need a dedicated reporting UI
  in this feature.
- This capability applies to Scout's live, production conversation handling; it does not need to
  run in any offline testing/simulation surface used to preview Scout's behavior before it goes
  live.
