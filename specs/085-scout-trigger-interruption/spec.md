# Feature Specification: Scout V2 Trigger-Based Playbook Interruption over an Active Procedure

**Feature Branch**: `085-scout-trigger-interruption`

**Created**: 2026-09-25

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 13/scoutv2/briefs/11-interrupcao-por-trigger.md" — Fase 11 of the ScoutV2 epic, executed after Brief 04 (typed instructions, playbook index, mid-turn `open_playbook`) and before Brief 05 (exit handling). Today the assistant can only open a playbook mid-turn on its own initiative when conversation state hasn't already pinned the conversation to a procedure. But most of a conversation's lifetime *does* have a procedure pinned by state (identification, qualification, scheduling), so the handful of situational playbooks that only ever activate by the assistant's own initiative — a customer stepping outside the sales scope, a pricing question mid-procedure, a request to pause — are effectively unreachable for as long as any procedure is in progress. Separately, once the assistant opens any playbook mid-turn, that opening is remembered forever: the conversation stays pinned to it on every later turn, with no way back, including when the assistant opened the wrong one or a customer talked it into opening one by name.

**Terminology**: "Trigger" in the title means opening a playbook because its `trigger:` description matches the conversation — the assistant's own choice, as opposed to a `when_state` match. It is not the stored `activation_reason: trigger`, which an interruption never writes (FR-011). "An interruption" is any opening of a situational playbook, whether or not a procedure is pinned at that moment; "an interruption over a pinned procedure" is used where the pinned procedure's guidance matters (FR-006, SC-004). "A procedure is pinned" means any pin (Key Entity "Pinned Procedure"); "by state" is reserved for a playbook's state activation condition and for `activation_reason: state`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The assistant can reach a situational playbook even while a procedure is in progress (Priority: P1)

While a procedure (identification, qualification, scheduling, or any future state-pinned procedure) is active, the assistant is offered the action to open a playbook by name, but only for the subset of the catalog that never activates by conversation state — the same handful of playbooks (a customer stepping outside the sales scope, a pricing question, a pause request) that today are unreachable for the entire time a procedure is in progress. The list the assistant sees names exactly that reachable subset, nothing more. When nothing is pinning the conversation to a procedure, the assistant can still reach and open any playbook in the catalog, exactly as before.

**Why this priority**: Without this, the situations this feature exists to fix have no path to happen at all — the assistant simply cannot react to them while any procedure is running, which is most of a conversation's lifetime.

**Independent Test**: Can be fully tested by starting a turn with a procedure already pinned, confirming the assistant is offered the open-playbook action and shown a list containing only the playbooks that never activate by state, confirming an attempt to open a procedure playbook (one that does activate by state) is rejected with an error while the turn continues, and confirming that with no procedure pinned the assistant can still see and open the full catalog.

**Acceptance Scenarios**:

1. **Given** a procedure is pinned to the conversation, **When** the turn's available actions are assembled, **Then** the action to open a playbook by name is offered and the list shown to the assistant contains only playbooks that never activate by state.
2. **Given** no procedure is pinned to the conversation, **When** the turn's available actions are assembled, **Then** the list shown to the assistant contains every playbook in the catalog and any of them can be opened.
3. **Given** a procedure is pinned, **When** the assistant attempts to open a playbook that does activate by state, **Then** that action returns an error and the turn continues normally.
4. **Given** a procedure is pinned and the catalog contains no playbook that never activates by state, **When** the turn's available actions are assembled, **Then** the action to open a playbook by name is not offered at all.

---

### User Story 2 - An opened interruption takes over the rest of the turn (Priority: P2)

The moment the assistant opens one of these situational playbooks while a procedure was in progress, that procedure's guidance and the tools it had made available drop out of the assistant's working context for the rest of that turn — replaced by the always-available baseline plus whatever the newly opened playbook itself declares. The interrupted procedure's guidance does not leak in alongside the interruption, and the interruption's own content and abilities do not get diluted by the procedure it interrupted. If the assistant opens a second situational playbook later in the same turn, that one takes over in exactly the same way, fully replacing the first.

**Why this priority**: This is what makes the interruption safe to allow at all — without it, opening a situational playbook mid-procedure would mix guidance and abilities that don't belong together (e.g. a pricing question would still carry the qualification procedure's tools), reintroducing exactly the confusion this feature is meant to remove. It depends on User Story 1 making the interruption reachable in the first place.

**Independent Test**: Can be fully tested by pinning a procedure by state, having the assistant open a reachable situational playbook mid-turn, and confirming that from that point in the same turn onward the procedure's guidance and tools are gone, only the always-available baseline plus the newly opened playbook's own declarations remain, and the opened playbook's content came back as the direct result of opening it.

**Acceptance Scenarios**:

1. **Given** a procedure is pinned, **When** the assistant opens a reachable situational playbook mid-turn, **Then** from the next step of that same turn onward the guidance and tools belonging to the interrupted procedure are no longer present.
2. **Given** the same situation, **When** the working context for that next step is inspected, **Then** it contains only the always-available baseline plus whatever the opened playbook itself declares, and nothing from the interrupted procedure.
3. **Given** the assistant opens a reachable situational playbook, **When** that action completes, **Then** its full content comes back as the direct result of that action.
4. **Given** the assistant has already opened one situational playbook this turn, **When** it opens a second one later in the same turn, **Then** the second one fully replaces the first by the same takeover, rather than adding to it.

---

### User Story 3 - Opening an interruption leaves no trace on the conversation, and the interrupted procedure resumes next turn (Priority: P3)

Opening one of these situational playbooks is a within-turn detour, not a new destination: it never gets written down as the conversation's ongoing procedure. On the very next turn, the conversation is routed exactly as if the interruption had never happened — whatever procedure was in progress before (with all of its accumulated progress intact) simply continues, or, if nothing was in progress, the conversation goes back to having nothing pinned. The fact that an interruption happened is still recorded for after-the-fact review of that turn, just not as part of what determines future turns.

**Why this priority**: This is what keeps the interruption safe to open freely — without it, a single wrong or customer-steered opening would permanently redirect the conversation with no way back, which is the second failure this feature exists to close. It only matters once User Stories 1 and 2 make interruptions reachable and effective in the first place.

**Independent Test**: Can be fully tested by pinning a procedure by state, having the assistant open a situational playbook mid-turn, confirming the conversation's stored ongoing-procedure data is untouched immediately afterward, then running a second turn and confirming the conversation is routed to the same procedure it had before the interruption with its progress preserved, while a review record of the turn shows the interruption happened.

**Acceptance Scenarios**:

1. **Given** the assistant opens a situational playbook mid-turn while a procedure is pinned, **When** the conversation's stored ongoing-procedure data is inspected immediately afterward, **Then** it is completely unchanged from before the interruption.
2. **Given** the same situation, **When** the next turn begins, **Then** the conversation is routed to the same procedure that was pinned before the interruption, with its progress preserved.
3. **Given** the assistant opens a situational playbook mid-turn while no procedure was pinned, **When** the next turn begins, **Then** the conversation still has no procedure pinned.
4. **Given** an interruption was opened during a turn, **When** that turn's review record is inspected, **Then** it shows which situational playbook was opened and that the assistant opened it on its own initiative (not that routing pinned it).
5. **Given** the assistant opens, mid-turn with nothing pinned, a playbook that *does* activate by state (not a situational one), **When** the next turn begins, **Then** that playbook remains pinned to the conversation — this case is unchanged by this feature.

---

### Edge Cases

- No procedure is pinned and the catalog itself is empty: the list shown to the assistant names no playbook and says that no playbook is available to open in this turn, and the open-playbook action is not offered at all, since there is nothing it could open.
- A procedure is pinned and the catalog contains playbooks, but none of them is a situational (never-state-activated) one: the open-playbook action is not offered, even though it would be offered with nothing pinned. The list shown to the assistant says that no playbook is available to open in this turn; it does not say or imply that no procedure is active, since the pinned procedure's guidance is in the same instructions.
- The assistant re-opens the very same situational playbook a second time later in the same turn: this is treated the same as opening a different one — the takeover happens again with the same playbook's own content and abilities, not skipped as redundant.
- A situational playbook opened mid-turn declares no additional abilities of its own: the working context for the rest of that turn contains only the always-available baseline, and that is not an error.
- In a single step, the assistant asks for several actions at once, and one of them opens a situational playbook: the actions are handled in the order the assistant listed them, and those after the opening are checked against the tools available after the takeover (FR-016).
- Nothing is pinned at the start of the turn, and within that turn the assistant opens both a procedure playbook (one that does activate by state) and a situational one, in either order (FR-017).
- After an interruption has taken over the turn, the assistant tries to open the interrupted procedure again by name: it is outside the turn's openable set, so that action returns an error and the turn continues (FR-002, FR-005). The procedure resumes on the next turn (FR-012).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A playbook that never activates by conversation state MUST be treated as a "situational" (interruption) playbook, usable only through the assistant opening it mid-turn by name; this categorization MUST be derived from the playbook's existing activation condition, not from a new declared attribute.
- **FR-002**: The set of playbooks the assistant may open by name during a turn ("openable set") MUST be: the entire catalog (every playbook currently loaded) when no procedure is pinned; only the situational playbooks when a procedure is pinned. The set is determined once, at the start of the turn, and does not change within that turn.
- **FR-003**: The list shown to the assistant naming playbooks it may open MUST contain exactly the openable set for that turn — no playbook outside the set, no playbook missing from the set. When the openable set is empty, the list MUST say that no playbook is available to open in this turn, and MUST NOT say or imply that no procedure is active.
- **FR-004**: The action to open a playbook by name MUST be offered whenever the openable set for that turn is non-empty, and MUST NOT be offered when the openable set is empty — including when a procedure is pinned but the catalog has no situational playbook, and when no procedure is pinned but the catalog is entirely empty.
- **FR-005**: Attempting to open, by name, a playbook that exists in the catalog but falls outside the current turn's openable set (e.g. a state-activating playbook while a procedure is pinned) MUST return an error for that specific action, and the turn MUST continue rather than fail.
- **FR-006**: When the assistant opens a situational playbook while a procedure is pinned, from that point in the same turn onward the interrupted procedure's guidance — its procedure text and its prompt for pending data — MUST no longer be present in the assistant's working instructions. The tools it had made available are governed by FR-007.
- **FR-007**: Immediately after an interruption is opened, the assistant's available tools for the remainder of that turn MUST consist of exactly the always-available baseline plus whatever the opened playbook itself declares — no tools carried over from the interrupted procedure.
- **FR-008**: Opening a situational playbook MUST return that playbook's full content as the direct outcome of that action, within the same top-level turn — not deferred to a subsequent turn.
- **FR-009**: The always-available baseline (including the action to open another playbook by name) MUST remain available to the assistant after an interruption is opened, so that opening a further situational playbook later in the same turn is possible.
- **FR-010**: If the assistant opens a second situational playbook later in the same turn, that opening MUST fully replace the effect of the first — the same takeover of working instructions and available tools described in FR-006/FR-007, not additive to the first opening's effects.
- **FR-011**: Opening a situational playbook MUST NOT write anything to the conversation's stored ongoing-procedure data (which procedure is pinned, when it was pinned, or why) — regardless of whether a procedure was pinned before the interruption or not.
- **FR-012**: The next turn after an opened interruption MUST start from the same stored ongoing-procedure data the conversation had before the interruption. A procedure pinned before the interruption MUST still be pinned, with its accumulated progress preserved, and a conversation with nothing pinned before it MUST still have nothing pinned. Conversation data that the interruption's own tools deliberately changed (e.g. an opportunity field it recorded) is not reverted, and routing takes those changes into account as it normally would.
- **FR-013**: Opening a playbook that does activate by conversation state (not a situational one), by name, while no procedure is pinned MUST continue to write the conversation's stored ongoing-procedure data exactly as it does today, recording that it was opened by the assistant's own initiative (`activation_reason: trigger`) rather than by a state match — this feature MUST NOT change that existing behavior.
- **FR-014**: Every turn in which an interruption is opened MUST produce a reviewable record of that turn showing which situational playbook was opened and that it was opened by the assistant's own initiative rather than pinned by routing. The per-action record the engine already keeps for every action the assistant takes during a turn satisfies this: an open-playbook entry naming the playbook exists only when the assistant asked for it, never when routing pinned a procedure.
- **FR-015**: This feature MUST NOT change the prompt assembly, tool selection, or behavior of the pre-ScoutV2 (v1) execution path in any way.
- **FR-016**: When one step contains several actions and one of them opens a situational playbook, the actions listed after it MUST be resolved against the post-takeover set of available tools. An action that is no longer available MUST return an error for that action only, and the turn MUST continue. Actions listed before the opening MUST complete normally.
- **FR-017**: With nothing pinned at the start of a turn, when the assistant opens both a procedure playbook and a situational playbook in the same turn: the openable set stays as it was at the start of the turn, and a pin written mid-turn takes effect only from the next turn (FR-002). The procedure playbook MUST become pinned (FR-013) whichever order they are opened in. A situational playbook opened after it MUST replace its tools for the rest of the turn (FR-007) without undoing that pin (FR-011). A procedure playbook opened after a situational one MUST add its tools on top of the takeover's tools, as it does today.

### Key Entities

- **Pinned Procedure**: The procedure routing assigns to a turn before the assistant runs — either one whose state condition matches now, or the one carried over from the conversation's stored ongoing-procedure data, whether it was stored by a state match or by an earlier assistant-initiated opening. "A procedure is pinned" throughout this spec means this, however the pin was stored. It is fixed at the start of the turn and never changes within it.
- **Situational (Interruption) Playbook**: A playbook with no conversation-state activation condition; reachable only through the assistant opening it by name mid-turn, whether or not another procedure is currently pinned. Not a new kind of catalog entry — an existing playbook is categorized this way purely by the absence of a state condition.
- **Procedure Playbook**: A playbook with a conversation-state activation condition; can be pinned to a conversation by routing, or opened by name mid-turn when nothing is pinned (in which case it becomes pinned, per existing behavior).
- **Openable Set**: The subset of the catalog the assistant may name in a given turn's open-playbook action — the full catalog with nothing pinned, or only situational playbooks with a procedure pinned — determined once at the start of the turn. The single definition used both for the list shown to the assistant and for what the open-playbook action will accept.
- **Interruption Takeover**: The within-turn effect of opening a situational playbook, whether or not a procedure is pinned: for the rest of that turn the assistant's working instructions become the always-available baseline (dropping a pinned procedure's guidance, if one is pinned), and its tools become the always-available baseline plus the opened playbook's own declarations (dropping any tools a pinned procedure or an earlier opening in the same turn had added). With nothing pinned, only the tools change, since the working instructions already equal the baseline.
- **Turn Review Record**: The per-turn record kept for later inspection. Each action the assistant takes during the turn gets an entry naming the action and its arguments, so an opened playbook appears as an open-playbook entry naming it, which by construction means the assistant opened it on its own initiative. The turn-level summary of the pinned procedure and why it was pinned stays as it is. This record is distinct from the conversation's stored ongoing-procedure data, which only reflects what carries across turns.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of turns where a procedure is pinned and the catalog contains at least one situational playbook offer the assistant the open-playbook action; 0% of turns where a procedure is pinned and the catalog contains no situational playbook offer it (with nothing pinned, availability follows FR-004: offered whenever the catalog is non-empty).
- **SC-002**: 100% of the lists shown to the assistant during a pinned procedure contain only situational playbooks; 100% of the lists shown with nothing pinned contain the full catalog.
- **SC-003**: 100% of attempts to open, by name, a playbook outside the current turn's openable set complete with an error for that action and zero turn failures.
- **SC-004**: In 100% of turns where an interruption is opened over a pinned procedure, the remaining steps of that turn carry none of the interrupted procedure's guidance in the assistant's working instructions, and the offered tools are exactly the always-available baseline plus the tools the opened playbook itself declares — no tool is offered because the interrupted procedure declared it (a tool the opened playbook also declares is offered as its own). The conversation transcript, including any actions the procedure had already completed earlier in the turn, stays as it is.
- **SC-005**: 100% of turns following an opened interruption start from the same stored ongoing-procedure data (pinned or not, same progress) as before the interruption. Zero conversations are left pinned to a situational playbook.
- **SC-006**: 100% of opened interruptions leave the conversation's stored ongoing-procedure data byte-for-byte unchanged, while 100% of them still appear in that turn's reviewable record.

## Assumptions

- This feature builds directly on the typed instructions, playbook catalog, index, and mid-turn open-playbook action delivered by Brief 04; it reuses the existing playbook catalog and its state-activation condition as the sole signal for classifying a playbook as situational, without adding a new declared field to distinguish them.
- What happens when the assistant reaches a procedure's own conclusion condition (the exit/handoff mechanism) is a later phase's responsibility (Brief 05) and out of scope here; this feature only defines the always-available baseline that later phase adds its own action to.
- The three specific situational playbooks referenced in the problem statement (out-of-scope requests, pricing questions, pause requests) are delivered by a later phase (Brief 06); this feature's own verification uses a fixture catalog of situational and procedure playbooks, not those specific three.
- No limit is placed on how many interruptions may be opened within a single turn; there is no evidence today of a loop risk that would justify one, and none is added speculatively.
- A model-driven mechanism that infers when to open a situational playbook from conversational intent alone, without the assistant explicitly naming one from the list it was shown, remains a later, deferred initiative and is not part of this feature.
- No changes are made to the pre-ScoutV2 (v1) execution path; it continues to behave exactly as it does today.
- Brief 04's prior specification of the open-playbook action's availability — offered whenever nothing is pinned, regardless of catalog contents — is superseded by FR-004 of this feature, which additionally withholds the action when the openable set is empty in either state (nothing pinned but empty catalog; procedure pinned but no situational playbook in the catalog).
- The three user stories are independently testable, but they are released together. User Story 1 without User Stories 2 and 3 would make interruptions reachable while they still write the pin (overwriting the procedure in progress) and still mix the procedure's tools with the interruption's — exactly the failures this feature exists to close.
- Brief 04 is not part of any release, so no production conversation has stored ongoing-procedure data naming a situational playbook (Brief 04's code records every opened playbook, situational ones included). SC-005 therefore needs no data cleanup; development databases holding such rows are out of scope.
