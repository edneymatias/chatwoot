# Feature Specification: Scout Deterministic Router and Conversation Routing State

**Feature Branch**: `082-scout-router-conversation-state`

**Created**: 2026-09-24

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 13/scoutv2/briefs/02-roteador-e-estado-de-conversa.md" — Fase 02 of the ScoutV2 epic, and the epic's stated cut-line: if this phase doesn't pass its no-LLM, no-network specs, the rest isn't worth building. Today every Scout turn builds the same prompt and the same 7-tool catalog regardless of conversation state, which forces a costly, error-prone double-classification loop just to decide what the assistant is even doing (measured: a turn costs 3 calls to a language model at best and up to 8 at worst, and the classifier used to confirm a handoff has been observed misreading a customer picking one of several offered options as "accepted a human handoff" 5 times out of 5). This feature introduces a deterministic router that decides which behavior procedure ("playbook") is active for a conversation by reading state that is already reliably known (opportunity stage, pending required fields, the currently active playbook, transitions already made this turn) instead of asking a model to reclassify it, and persists every activation decision per conversation so it is possible to answer, after the fact, why the assistant did what it did.

## Clarifications

### Session 2026-09-24

- Q: When the router interrupts the active playbook because a higher-priority playbook now matches, is that interruption recorded with activation reason "transition," or with reason "state" like any other state-based activation? → A: Reason "state." Interruption is not an exit and not the same mechanism as a playbook's own declared "transition" ending — it is the router doing what it always does, deciding from state, before the turn's model call even happens. The router runs at most once per turn attempt, so an interruption can never by itself accumulate toward the per-turn transition cap; only a playbook's own declared "transition" ending does that.
- Q: When the two-hand-off-per-turn cap is reached and a third is refused, does that fact need its own distinct persisted marker, or is it inferable from the fields already defined (active playbook + historical transition count)? → A: It needs its own marker. A nullable timestamp field on the conversation's routing state is written only when a third hand-off is refused within the same turn attempt, is overwritten (never reset or accumulated) if the limit is reached again on a later turn, is read by nothing else in this feature, and is unaffected by a retry's fresh turn-scoped count.
- Q: When a playbook that previously ended terminally (with a last exit recorded) is reactivated later in the same conversation, is the recorded last exit cleared, or does it stay until the next terminal ending? → A: It stays. The last exit is a per-conversation historical record of "the last real ending this conversation had," not a live flag; only a subsequent terminal ending replaces it. No activation of any kind — state-based or transition — touches it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Turn-scoped routing context (Priority: P1)

Once per turn, the system assembles a single snapshot of everything routing needs to know: the conversation, contact, inbox, the Scout configuration, the opportunity (including which role its current stage plays — initial, qualified, unqualified, or none of those), which required fields are still pending, which playbook is currently active, how many playbook transitions have already happened this turn, and which capabilities are currently satisfied. Every check the router performs reads only from this one snapshot — nothing re-queries the database or any other source mid-decision.

**Why this priority**: This is the foundational capability — without one trustworthy snapshot to read from, there is nothing for a deterministic decision rule to decide against, and no way to test routing without a database and a live conversation. It is also what makes the rest of this feature testable at all.

**Independent Test**: Can be fully tested by constructing one snapshot directly in memory with fixed values (no database, no conversation, no language model) and confirming every one of its fields reads back exactly as given.

**Acceptance Scenarios**:

1. **Given** a conversation with a contact, an inbox, a Scout configuration, and an opportunity sitting in a known pipeline stage, **When** the system assembles the turn's routing snapshot, **Then** the snapshot exposes the conversation, contact, inbox, Scout, opportunity (with its stage's role — initial, qualified, unqualified, or none of those), the list of pending required fields, the currently active playbook (or none), the count of transitions already made this turn, and the set of currently satisfied capabilities, all on one object.
2. **Given** the turn's routing snapshot has been assembled, **When** any routing check evaluates a playbook's activation condition, **Then** it reads exclusively from that snapshot and performs no database query or external call of its own.
3. **Given** a test needs to exercise routing behavior, **When** the snapshot is constructed directly in memory with chosen values, **Then** the router can be exercised end-to-end with no database connection and no language model call.

---

### User Story 2 - Deterministic playbook selection (Priority: P2)

Given the turn's routing snapshot and the full set of available playbooks, the system decides which playbook (if any) should be active, using only state — never a language model — whenever state is enough to decide. A playbook whose activation condition is fully satisfied by the snapshot "matches." Among the playbooks that match, the one with the highest ordering priority wins. If the winner is already the active playbook, nothing changes. If there is no active playbook, the winner is activated. If the winner outranks the active playbook by a strictly higher priority, the active playbook is interrupted and replaced — this interruption is itself just another state-based activation, recorded the same way as any other. Otherwise — including when nothing matches at all — the active playbook simply stays active, and when nothing matches and nothing is active either, the router reports that it has no state-based answer, leaving the decision to be made another way in a later phase.

**Why this priority**: This is the actual fix for the measured problem — it is what replaces the stochastic, expensive double-classification loop with a decision that always produces the same answer for the same state, and it is the phase's stated pass/fail line for the wider effort. It depends on User Story 1 (there is nothing to decide against without the snapshot), which is why it is not P1.

**Independent Test**: Can be fully tested with a table of playbook sets and snapshot values mapped to the expected winning playbook, exercised entirely in memory with no database and no language model — covering continuity, interruption, a would-be winner that doesn't outrank the active playbook, and nothing matching at all.

**Acceptance Scenarios**:

1. **Given** two or more playbooks whose activation conditions are all satisfied by the snapshot, **When** the router decides, **Then** the one with the highest ordering priority among them is the winner (playbook priority is already guaranteed unique across the whole set before routing ever runs, so this comparison never has to break a tie).
2. **Given** the winning playbook is already the active one, **When** the router decides, **Then** it remains active and no new activation is recorded.
3. **Given** there is no active playbook and a playbook's activation condition is satisfied, **When** the router decides, **Then** that playbook becomes active, and the activation is recorded with reason "state."
4. **Given** a playbook other than the active one wins and its priority is strictly higher than the active playbook's, **When** the router decides, **Then** the active playbook is interrupted, the winner becomes active, and the activation is recorded with reason "state" — the same reason as any other state-based activation, not the distinct "transition" reason reserved for a playbook's own declared hand-off (see User Story 3) — and this interruption never counts toward the per-turn transition-hand-off cap.
5. **Given** a playbook other than the active one wins but its priority is not strictly higher than the active playbook's, **When** the router decides, **Then** the active playbook remains active and nothing is recorded.
6. **Given** no playbook's activation condition is satisfied by the snapshot and a playbook is currently active, **When** the router decides, **Then** the active playbook remains active unchanged — a fresh match is not required every turn to keep a playbook running.
7. **Given** no playbook's activation condition is satisfied by the snapshot and no playbook is currently active, **When** the router decides, **Then** it reports that it has no state-based answer, and does not itself pick a playbook by intent/text (that half of activation is exercised starting in a later phase).
8. **Given** a playbook declares no activation condition at all (an intent-only, trigger-based playbook), **When** the router evaluates state-based activation, **Then** that playbook is never selected by this decision rule, regardless of how high its priority is.

---

### User Story 3 - Persisted per-conversation routing state (Priority: P3)

Every activation decision the router makes for a conversation is written down: which playbook is active, when it was activated, and why (state today; an intent-based trigger in a later phase). Separately from the router, a playbook can itself reach one of its own declared endings mid-turn, and the kind of ending decides what happens: a "transition" ending hands off to a named target playbook — recorded as an activation with reason "transition," and counted, up to a hard cap of two, within the current turn attempt; a "terminal" ending clears the conversation's recorded active playbook entirely and records that ending as the conversation's last exit. Within a single turn attempt, at most two transition hand-offs are allowed; a third does not happen — the turn ends instead, and a dedicated, durable marker records that the limit was reached, distinguishable from a turn that simply made one or two hand-offs and stopped there on its own. If a turn attempt is retried (for example after a background job failure), the retry's own hand-off count starts at zero — it does not inherit however many hand-offs the failed attempt already made, nor is it affected by a previous turn's limit-reached marker — while the historical, cumulative hand-off count kept for observability is never rolled back. Reactivating a playbook, whether by state or by a transition hand-off, never touches the conversation's recorded last exit; only a later terminal ending replaces it.

**Why this priority**: This is what turns "the router decided X" into something a person can audit afterward — today there is no way to know why the assistant behaved the way it did except by re-reading the whole transcript. It depends on User Story 2 actually producing activation decisions to persist, and is a safety limit on top of that decision rule, which is why it is third.

**Independent Test**: Can be fully tested against the persisted conversation routing state directly — recording a state-based activation and a state-based interruption, recording a transition hand-off and a terminal ending, driving a conversation to its second transition hand-off within one turn attempt and confirming a third is refused with the limit-reached marker recorded, confirming a fresh attempt after a retry starts its own hand-off count at zero, and confirming a reactivated playbook leaves a previously recorded last exit untouched — all without a database seeded through a live conversation or any language model call.

**Acceptance Scenarios**:

1. **Given** any state-based activation (a fresh activation or a priority-based interruption), **When** it happens, **Then** the active playbook, the activation time, and the reason "state" are all persisted for that conversation, and the conversation's last exit is left untouched.
2. **Given** a playbook reaches a declared "transition" ending that hands off to a named target playbook, **When** this happens, **Then** the target becomes the active playbook, the activation is recorded with reason "transition," the turn's hand-off count increases, and the conversation's last exit is left untouched.
3. **Given** a playbook reaches a declared "terminal" ending, **When** this happens, **Then** the conversation's active playbook is cleared and the ending is recorded as the conversation's last exit, replacing whatever was recorded there before.
4. **Given** a conversation has already recorded two transition hand-offs within the current turn attempt, **When** a third would otherwise happen, **Then** it does not happen, the turn ends instead, and the dedicated limit-reached marker is recorded for that turn.
5. **Given** a turn attempt made exactly two transition hand-offs and no more were attempted, **When** the turn ends, **Then** the limit-reached marker is not recorded — it stays distinguishable from the case where a third hand-off was actually refused.
6. **Given** a turn attempt failed and is retried, **When** the retry begins, **Then** its own hand-off count starts at zero regardless of how many hand-offs the failed attempt already made or whether it had already hit the limit, while the conversation's cumulative historical hand-off count keeps whatever it already accumulated and any previously recorded limit-reached marker is left as it was.
7. **Given** a playbook that was previously exited terminally (with a last exit recorded) is reactivated later in the same conversation, by state or by a transition hand-off, **When** it becomes active again, **Then** the conversation's previously recorded last exit is left exactly as it was.

---

### Edge Cases

- Two playbooks tying for the highest priority among the ones that match — cannot happen, because playbook priority is already required to be unique across the whole set before this feature's routing ever runs.
- The currently active playbook is itself among the matching playbooks and happens to be the highest-priority match — it simply stays active; this is not treated as a fresh activation.
- A playbook with the highest priority in the whole set has no activation condition at all (trigger-only) — it never wins the state-based comparison, because playbooks without an activation condition never "match" in the first place, no matter how high their priority is.
- A conversation has no persisted routing state yet (its very first turn) — treated exactly like "no playbook is currently active."
- A router-driven interruption and a playbook's own declared transition ending are different mechanisms that happen to share the word "transition" in casual description but not in the persisted reason: only the playbook-declared ending is recorded as reason "transition" and counts toward the two-per-turn cap; the router interrupting by priority is recorded as reason "state" and — since the router runs at most once per turn attempt — can never by itself reach that cap.
- The per-turn transition-hand-off cap is reached on two different turn attempts of the same conversation, on two different occasions — the limit-reached marker simply reflects the most recent occurrence; it is not a running count and does not accumulate across turns.
- A retried turn attempt whose failed predecessor already made one or two hand-offs, or had already hit the limit — the retry's own hand-off count starts at zero; the turn-scoped count, the cumulative historical count, and the limit-reached marker are all tracked separately, and only the cumulative count keeps the failed attempt's contribution.
- A terminal exit happens on a conversation that has no active playbook to begin with — the exit is still recorded as the conversation's last exit; there is simply nothing to clear.
- A playbook that previously ended terminally is reactivated later (by state or by a transition hand-off) — the conversation's last exit stays exactly as it was; only a new terminal ending replaces it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST assemble one routing snapshot per turn containing the conversation, contact, inbox, Scout, the opportunity (including a derived role for its current pipeline stage — initial/default, qualified, unqualified, or none of those), the list of currently pending required fields, the currently active playbook (if any), the count of transition hand-offs already made in the current turn attempt, and the set of currently satisfied capabilities.
- **FR-002**: Every activation-condition check the router evaluates MUST read exclusively from the routing snapshot it is given and MUST NOT independently query the database or any other external source.
- **FR-003**: The routing snapshot MUST be constructible directly in memory with fixed values, so routing can be exercised in a test with no database connection and no language model call.
- **FR-004**: The system MUST expose a single decision operation that takes the routing snapshot and the full set of available playbooks and returns either the selected playbook (with an indication of how confidently it was selected) or an explicit "no playbook selected by state" result.
- **FR-005**: The decision operation MUST evaluate every playbook's activation condition against the snapshot and consider a playbook "matching" only when its condition is fully satisfied.
- **FR-006**: Among matching playbooks, the decision operation MUST select the one with the highest ordering priority; because priority is already unique across the whole playbook set before routing runs, this selection never needs its own tie-break.
- **FR-007**: When the selected playbook is already the active one, the decision operation MUST leave it active and MUST NOT record a new activation.
- **FR-008**: When there is no active playbook and a playbook matches, the decision operation MUST activate the matching playbook and record the activation with reason "state."
- **FR-009**: When a matching playbook other than the active one has a strictly higher priority than the active playbook, the decision operation MUST interrupt the active playbook and activate the matching one, recording the activation with reason "state" — the same reason as any other router-driven activation, never the distinct "transition" reason defined in FR-015 — and this interruption MUST NOT be counted by the turn-scoped hand-off count in FR-016.
- **FR-010**: When a matching playbook other than the active one does not have a strictly higher priority than the active playbook, the decision operation MUST leave the active playbook unchanged and MUST NOT record anything.
- **FR-011**: When no playbook matches and a playbook is currently active, the decision operation MUST leave the active playbook active without requiring it to match again.
- **FR-012**: When no playbook matches and no playbook is currently active, the decision operation MUST return "no playbook selected by state" and MUST NOT itself select a playbook based on conversational intent/text.
- **FR-013**: A playbook that declares no activation condition MUST never be selected by the state-based decision rule, regardless of its priority.
- **FR-014**: The system MUST persist, per conversation, the currently active playbook, the time it was activated, and the reason it was activated (state today; trigger in a later phase; transition per FR-015), for every activation.
- **FR-015**: The system MUST support recording that a playbook has handed off to a named target playbook via one of its own declared "transition" endings — a mechanism distinct from a router-driven state interruption (FR-009) — which MUST activate the target playbook and record the activation with reason "transition."
- **FR-016**: The system MUST track a hand-off count scoped to the current turn attempt that counts only transition hand-offs (FR-015), never router-driven state interruptions (FR-009), and MUST reset this count to zero at the start of every turn attempt, including a retry of a previously failed attempt.
- **FR-017**: The system MUST NOT allow a third transition hand-off within the same turn-scoped count; when a decision would produce one, the system MUST refuse it rather than performing it.
- **FR-018**: When the system refuses a third hand-off within a turn attempt, it MUST durably record that the turn-scoped limit was reached, distinguishable from a turn that made only one or two hand-offs and stopped there on its own; this record MUST NOT be cleared or reset by a later turn attempt — a later occurrence overwrites it rather than accumulating alongside it.
- **FR-019**: The system MUST support recording that a playbook has reached a declared "terminal" ending, which MUST clear the conversation's currently active playbook and MUST record that ending as the conversation's last exit, replacing whatever was recorded there previously.
- **FR-020**: Neither a router-driven state interruption (FR-009) nor a transition hand-off (FR-015) MUST modify the conversation's recorded last exit; only a terminal ending (FR-019) replaces it.
- **FR-021**: The system MUST persist a cumulative, historical transition-hand-off count per conversation for observability, and MUST NOT treat that cumulative count as the input to the turn-scoped limit in FR-016/FR-017.

### Key Entities

- **Routing Snapshot**: The single, turn-scoped read model every routing decision is made from — conversation, contact, inbox, Scout, opportunity (with derived stage role), pending required fields, currently active playbook, this turn's transition-hand-off count so far, and currently satisfied capabilities. Built once per turn attempt; never partially rebuilt mid-decision.
- **Router**: The stateless decision component that takes a Routing Snapshot and the playbook set and returns either the selected playbook with a confidence indication, or "no playbook selected by state." It only ever produces reason "state" activations — including interruptions — and never itself performs a transition hand-off, which is a playbook-ending mechanism, not a router decision. Today only the state-based half of activation is implemented by this feature; the intent/trigger-based half is a separate, substitutable half exercised starting in a later phase.
- **Playbook Ending**: An outcome a playbook's own declared endings can produce mid-turn. A "transition" ending hands off to a named target playbook (recorded as an activation with reason "transition," counted toward the per-turn hand-off cap). A "terminal" ending clears the conversation's active playbook and is recorded as its last exit. What triggers a playbook to reach one of its endings during a live turn belongs to a later phase; this feature defines what the persisted routing state does once an ending is reached.
- **Conversation Routing State**: The persisted, per-conversation record of behavioral routing history — the currently active playbook, when and why it was activated (state, trigger, or transition), the cumulative historical transition-hand-off count, a dedicated marker recording the most recent time the per-turn hand-off limit was reached (nullable; overwritten, never reset, by a later occurrence), and the last terminal exit recorded.
- **Activation Reason**: One of "state," "trigger," or "transition." "State" covers every router-driven activation, including a priority-based interruption — the router runs at most once per turn attempt, so this reason never accumulates toward the transition cap. "Trigger" is reserved for the intent-based half of activation delivered in a later phase. "Transition" is produced only when a playbook hands off to a named target via one of its own declared endings, and is the only reason counted toward the per-turn hand-off cap.
- **Turn-Scoped Transition-Hand-off Counter**: The count of transition hand-offs (never router interruptions) made within the current turn attempt only, capped at two, reset to zero at the start of every attempt (including retries) — distinct from both the persisted cumulative historical count and the limit-reached marker, neither of which is ever used as this counter's starting value.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of the routing decisions exercised by this feature's own test suite are produced with zero calls to a language model and zero network requests.
- **SC-002**: Given a table of playbook sets and snapshot states covering continuity, interruption by strictly-higher priority, a non-strictly-higher would-be winner, and nothing matching, 100% of cases resolve to the documented expected playbook (or "none").
- **SC-003**: For every playbook activation, transition hand-off, and terminal exit recorded during a conversation, the reason the assistant behaved the way it did is answerable from persisted data alone, with zero activations left unexplained and zero ambiguity between a router-driven interruption and a playbook-declared transition hand-off.
- **SC-004**: Across all observed turn attempts, zero conversations ever record more than two transition hand-offs within a single turn attempt, and zero retried attempts are blocked by a prior failed attempt's hand-off count or limit-reached marker.

## Assumptions

- This feature reuses the playbook catalog, activation-condition evaluation, and the registry of named condition checks delivered by the prior phase (Brief 01) exactly as they are; it does not add new condition checks beyond what routing itself needs, and does not re-validate the catalog (boot validation is that phase's responsibility and is assumed to have already run).
- Playbook priority uniqueness across the whole catalog is already enforced when the catalog loads (prior phase), so "the matching playbook with the highest priority" in this feature never needs its own tie-break rule.
- The opportunity's derived pipeline-stage role (initial/default, qualified, unqualified, or none of those) is computed from the Scout's already-configured stage identifiers, following the same categorization the existing prompt-building code already performs for display purposes — this feature exposes that categorization as a reusable value on the routing snapshot rather than introducing a new source of truth for it.
- "Satisfied capabilities" on the routing snapshot reflects which capabilities from the known-capabilities catalog (prior phase) currently apply to the conversation; this feature reads that state without exercising or calling any capability itself.
- The persisted routing-state record includes a field reserved for a later phase's use (unmet qualification flags surfaced in observability tooling); this feature creates that field but does not populate or read it — populating it is out of scope here.
- Intent/trigger-based playbook activation (the model deciding which playbook to open from conversational text) is not implemented by this feature. When nothing matches by state, the router's answer is simply "no playbook selected by state" — a later phase is responsible for what happens next in that case.
- A playbook's own declared endings ("terminal" and "transition") are triggered by whatever executes the playbook mid-turn — a later phase's responsibility (Brief 03). This feature defines only what the persisted conversation routing state does once each kind of ending is reached; it does not implement the mechanism that decides when a playbook has reached one of its endings during a live conversation.
- A declared ending type beyond "terminal" and "transition" (for example an escalation-style ending) is not specifically addressed by this feature's requirements; how such an ending affects the conversation's routing state, if at all, is left to whichever later phase introduces it.
- "A turn attempt" and the counting of transition hand-offs within it are driven by whichever component executes a turn (a later phase's responsibility); this feature defines the counting rule itself — reset per attempt including retries, a hard cap of two, refusing a third, and recording that the limit was reached — without implementing turn orchestration or the act of ending a turn.
