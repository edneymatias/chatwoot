# Feature Specification: Scout V2 Turn Runner and Qualification Playbook (Playground)

**Feature Branch**: `083-scout-turn-runner-playground`

**Created**: 2026-09-24

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 13/scoutv2/briefs/03-turn-runner-playground.md" — Fase 03 of the ScoutV2 epic, closing out Phase 0 by proving Briefs 01 (playbook catalog) and 02 (router + conversation routing state) end to end in a real playground turn. Today the only execution path for the Scout assistant assembles one static prompt and one fixed tool catalog before a single top-level model call, then pays a minimum of 3 calls to a language model per turn (up to 8 in the worst case) to an always-on audit/classification/repair loop — and there is no alternative execution path where a playbook can be exercised without touching that existing service, which is off-limits by design while the new engine is built. This feature introduces a new turn execution that assembles its prompt and tool catalog fresh every turn from whichever playbook the router has selected, answers in a single top-level model call, persists the resulting routing state, and is observable from its first turn — gated behind a new account-level engine setting so playground and inbox can be proven on a development account before anything touches production. It ships with exactly one playbook (qualification of an open opportunity's pending required fields) and explicitly excludes the playbook index, intent-based playbook opening, declared outcomes/endings, escalation, and retiring the existing engine, all of which belong to later phases of the same epic.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A v2 turn executes end-to-end in the playground (Priority: P1)

Given a scout and a playground conversation on an account with the new engine selected, the system builds the turn's prompt and tool catalog fresh from whatever playbook is currently active, answers with a single top-level call to the language model — no separate audit call, no classifier call, no repair call — and persists the resulting active playbook and activation reason before the reply is sent. An account without the new engine selected keeps behaving exactly as it does today, in both playground and inbox; an account with it selected gets the new behavior in both, and turning it off again restores the old behavior on the very next message with no deployment.

**Why this priority**: This is the foundational capability — it is what proves the whole Phase 0 stack (catalog + router) actually produces a usable turn, and nothing else in this feature is observable or testable without it existing first.

**Independent Test**: Can be fully tested by fixing one playbook as active and doubling the language-model client, then confirming the assembled prompt, the assembled tool catalog, and the persisted routing state — without needing a real conversational reply or a live model call.

**Acceptance Scenarios**:

1. **Given** a scout and a playground conversation, **When** a turn is executed, **Then** it makes exactly one top-level call to the language model — no separate audit call, no classifier call, and no repair call.
2. **Given** a playbook is currently active for the conversation, **When** the turn's prompt is assembled, **Then** it contains that playbook's full step-by-step body and does not contain the existing engine's fixed always-on behavioral guideline block.
3. **Given** a playbook is active, **When** the model's tool catalog is assembled for the turn, **Then** it contains only the tools that playbook declares plus one read-only knowledge-lookup tool — a stage-transition tool, a human-handover tool, and a custom-API-call tool are never offered.
4. **Given** a turn completes, **When** its outcome is inspected, **Then** the conversation's active playbook and the reason it was activated are persisted exactly as the turn's routing decision determined.
5. **Given** an account without the new engine selected, **When** a playground or inbox message is processed, **Then** it is handled by the existing execution path with behavior identical to today.
6. **Given** an account with the new engine selected, **When** a playground or inbox message is processed, **Then** both are handled by the new execution path; **When** the setting is turned off again, **Then** the very next message on either surface returns to the existing behavior with no deployment.

---

### User Story 2 - Every v2 turn is observable from day one (Priority: P2)

Each turn produces one instrumented session carrying exactly one top-level language-model generation — never the several nested generations the existing audited path produces — and that session's data includes which playbook was active and why it was activated. Every tool the model executes during the turn shows up as its own instrumented record.

**Why this priority**: This depends on User Story 1 actually producing a turn to observe, and it is what makes the rest of the epic's behavior work debuggable from the start instead of retrofitted later — the epic's own stated observability requirement.

**Independent Test**: Can be fully tested by executing one turn with a doubled tracing backend and confirming a single session with a single top-level generation carrying the right attributes, plus one instrumented record per tool call — no live conversation or real model call required.

**Acceptance Scenarios**:

1. **Given** a v2 turn runs, **When** its trace is inspected, **Then** it is one instrumented session containing one top-level language-model generation, not the several nested generations the existing audited path produces.
2. **Given** a v2 turn runs, **When** its trace is inspected, **Then** the session's data includes the active playbook's name and the reason it was activated.
3. **Given** the turn's active playbook causes a tool to run, **When** the trace is inspected, **Then** that tool execution appears as its own instrumented record.

---

### User Story 3 - The qualification playbook actually qualifies a lead in the playground (Priority: P3)

With an open opportunity and pending required fields, the router activates the qualification playbook by conversation state, and the assistant follows that playbook's steps to collect the missing information, recording what it collects through the opportunity-management tool. As long as the same state keeps holding, the conversation keeps following the same playbook without being re-routed on every incoming message. The observed qualification behavior matches what the existing engine already does for the same scenario, even though the new prompt carries no global funnel guidelines.

**Why this priority**: This is the actual behavioral proof the phase exists to deliver — it depends on User Story 1 producing a working turn and User Story 2 making it observable, which is why it is third rather than first.

**Independent Test**: Can be fully tested by running a full playground dialogue against a conversation with an open opportunity and pending required fields, confirming the fields the customer supplies end up recorded through the opportunity-management tool and that the conversation is not re-routed away from the qualification playbook while collection is still in progress.

**Acceptance Scenarios**:

1. **Given** a conversation with an open opportunity and pending required fields, **When** a turn runs, **Then** the router activates the qualification playbook with activation reason "state," and the reply follows that playbook's collection steps.
2. **Given** the customer supplies a requested field, **When** the assistant acts on it, **Then** the information is recorded through the opportunity-management tool.
3. **Given** the qualification playbook remains active across an ongoing exchange, **When** further customer messages arrive while the same conditions still hold, **Then** the conversation is not re-routed to a different playbook on every message.
4. **Given** the same qualification scenario the existing engine already handles, **When** the two are compared, **Then** the observed qualification behavior is equivalent, even though the new prompt contains no global funnel guidelines.

---

### Edge Cases

- No playbook's activation condition is satisfied for the conversation (for example, no opportunity exists yet) — the turn still executes with a single top-level model call, using a minimal baseline prompt and offering only the read-only knowledge-lookup tool; no playbook body and no mutation tool are offered. Selecting a playbook by conversational intent when nothing matches by state is a later phase's mechanism.
- The active playbook's declared tool is invoked more than once within the same turn — each invocation still appears as its own instrumented tool record.
- The new-engine setting is toggled between two turns of the same conversation — the next turn processed follows whichever engine the setting currently selects; nothing about the conversation's history pins it to one engine.
- A playground turn and an inbox turn happen on the same account with the setting enabled — both are handled by the same new execution path; there is no per-conversation or per-channel override.
- The active playbook has no declared outcome to exit through in this phase — the turn simply answers and waits for the next customer message instead of exiting through a declared ending.
- The account's response quota is exhausted or it has no configured API key when a v2 turn would run — the turn makes zero language-model calls and falls back to the same quota/API-key gate and handoff behavior the existing execution path already uses for this condition, reused unchanged.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide an account-level setting, independent of the existing Scout on/off setting, that selects which assistant execution path handles that account's Scout conversations.
- **FR-002**: The engine selection MUST apply identically to both the account's playground and its live inbox conversations — an account MUST NOT have one on the new execution path while the other stays on the existing one.
- **FR-003**: For an account where the setting selects the existing execution path, playground and inbox behavior MUST satisfy FR-020's guarantee with these specific, testable invariants: no change to the number of model calls, the prompt content, or the tool catalog.
- **FR-004**: For an account where the setting selects the new execution path, both playground and inbox messages MUST be handled by the new turn execution instead of the existing one.
- **FR-005**: Turning the setting off for an account MUST cause the very next message on either surface to be handled by the existing execution path, with no deployment or restart required.
- **FR-006**: Each new-execution-path turn MUST assemble its prompt fresh from the current conversation context every time it runs, rather than reusing a prompt built once ahead of time.
- **FR-007**: When a playbook is active for the conversation, the turn's prompt MUST include that playbook's full step-by-step body.
- **FR-008**: The turn's prompt MUST NOT include the existing execution path's fixed always-on behavioral guideline block.
- **FR-009**: The set of tools offered to the model in a turn MUST consist of exactly the tools the active playbook declares, plus one read-only knowledge-lookup tool, regardless of any other configuration.
- **FR-010**: A stage-transition tool, a human-handover tool, and a custom-API-call tool MUST NOT be offered to the model by the new turn execution, regardless of which playbook is active.
- **FR-011**: The new turn execution MUST reach its reply with exactly one top-level call to the language model per turn attempt, and MUST NOT perform any separate classification call, audit call, or repair call.
- **FR-012**: At the end of a turn, the system MUST persist the conversation's active playbook and the reason it was activated, using the routing decision produced for that same turn.
- **FR-013**: Each new-execution-path turn MUST produce one instrumented session containing exactly one top-level language-model generation.
- **FR-014**: The instrumented session for a turn MUST carry the active playbook's name and its activation reason as inspectable data.
- **FR-015**: Every tool the model executes during a turn MUST appear as its own instrumented record.
- **FR-016**: This feature MUST ship exactly one playbook: a qualification procedure that activates by conversation state (an open opportunity with pending required fields) and declares exactly one tool, used to record collected data on the opportunity.
- **FR-017**: The qualification playbook's body MUST NOT reference, and the playbook MUST NOT declare, any outcome/ending; a turn running it concludes by replying to the customer and waiting for the next message.
- **FR-018**: While the qualification playbook remains the active one across an ongoing exchange, the conversation MUST NOT be re-routed to a different playbook on every incoming message solely because the same state still holds.
- **FR-019**: When no playbook's activation condition is satisfied for a conversation, the turn MUST still execute with a single top-level model call, offering only the read-only knowledge-lookup tool and no playbook body.
- **FR-020**: This feature MUST NOT change the behavior, prompt assembly, or tool selection of the existing execution path in any way observable to an account that has not selected the new one.

### Key Entities

- **New-Execution-Path Account Setting**: An account-level toggle, independent of the existing Scout on/off setting, that determines whether an account's playground and inbox conversations run on the existing execution path or the new one; changing it takes effect on the very next message with no deployment.
- **Turn**: One execution of the assistant in response to a conversation's pending message(s) on the new execution path — assembling context, consulting the routing decision, building a prompt and tool catalog from whatever playbook is active, making exactly one top-level call to the language model, persisting the resulting routing state, and dispatching the reply.
- **Qualification Playbook**: The single playbook shipped in this phase; activates by conversation state when an opportunity is open with required fields still pending, declares one tool for recording collected data, and declares no outcomes/endings.
- **Turn Trace**: The observability record produced per turn — one session containing one top-level generation that carries the active playbook and its activation reason as data, plus one instrumented record per tool call made during the turn.
- **Playground Sandbox Conversation**: A real, persisted, per-scout `Conversation` (with its own `Contact`/`Channel::Api`/`Inbox`/`ContactInbox`) that backs the otherwise-ephemeral playground surface — the only way `ScoutConversationState` and a real `Opportunity` can be exercised from the playground; resolved idempotently (the same conversation is returned on every call for the same scout) and never receives a real `Message` row.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A turn on the new execution path never makes more than one top-level call to the language model, compared to a minimum of 3 (and up to 8) on the existing execution path's audited turns — confirmable from each new-execution-path turn's trace.
- **SC-002**: For 100% of new-execution-path turns, the reason the assistant behaved the way it did (which playbook was active, why it activated) is answerable from that turn's trace alone, with zero turns left unexplained.
- **SC-003**: Toggling the new-execution-path setting for an account changes both its playground and inbox behavior together, with zero code deployment, taking effect on the very next message.
- **SC-004**: An account that has not selected the new execution path observes zero behavioral difference in playground or inbox conversations before and after this feature ships.
- **SC-005**: In a scripted qualification dialogue against a conversation with an open opportunity and pending required fields, 100% of the required fields the customer supplies end up recorded on the opportunity, and the conversation is never re-routed away from the qualification playbook while those conditions still hold.

## Assumptions

- The account-level setting introduced by this feature is a new, separate toggle from the existing Scout on/off setting: the existing setting keeps deciding whether Scout is enabled for the account at all, and this new setting only decides which execution path handles it once enabled.
- This feature reuses the playbook catalog, the routing decision, and the per-conversation routing-state persistence delivered by the two prior phases exactly as they are; it neither changes how a playbook is loaded/validated nor how the routing decision is made. It is the first place that wires "the router decided X" together with "X gets persisted" and "X's body/tools reach a real model call" into one live execution.
- "One top-level call to the language model" is measured from the turn's own perspective — one reply-generating request initiated per turn attempt — not from a lower-level count of every round-trip a single such request may internally require to process a tool result before returning its final answer. The contrast this feature is built to remove is the existing execution path's separate classification/audit/repair calls, not the mechanics of using a tool within one reply.
- Only one playbook exists in this phase, so an index of playbooks and the model's own ability to open a playbook by naming its intent — both needed once more than one state-independent playbook exists — are out of scope here and belong to a later phase. When no playbook's state condition is satisfied, this phase's turn simply answers with no playbook body and no mutation tool, rather than offering the model any such mechanism.
- Declared playbook outcomes/endings (typed results that end a procedure with a specific effect, such as a hand-off or a scheduled outcome) are a later phase's mechanism; this phase's one playbook declares none, so its turns always conclude by replying and waiting for the next customer message.
- An "unsatisfied flags" observability attribute mentioned for this phase's trace data is derived entirely from data already produced by the two prior phases (which of the active playbook's required capabilities are not currently satisfied, and which required fields are still pending) — this feature does not introduce a new source of that data and does not use it to change turn behavior; it is trace data only.
- The two places this feature changes are the background job that processes an inbox message and the playground message endpoint — every other part of message intake (audience matching, quota, debounce, follow-up scheduling) applies identically to both execution paths and is unchanged by this feature.
- A development account is used to exercise and demonstrate this feature. Promoting a production account to the new execution path, any preflight checks for that promotion, and retiring the existing execution path are all explicitly out of scope for this phase.
