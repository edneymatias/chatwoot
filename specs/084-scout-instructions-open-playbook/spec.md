# Feature Specification: Scout V2 Typed Instructions, Playbook Index, and Mid-Turn Playbook Activation

**Feature Branch**: `084-scout-instructions-open-playbook`

**Created**: 2026-09-25

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 13/scoutv2/briefs/04-instructions-indice-open-playbook.md" — Fase 04 of the ScoutV2 epic, building on the turn engine delivered in Brief 03. Today the always-on part of the assistant's system prompt is a single block of 11 mixed bullets (~6,076 characters) where non-negotiable safety rules, communication style, and situational guidance for specific customer intents all compete for the model's attention in the same prose. At least five of those eleven bullets are inherently situational — they only apply when a specific customer intent is present — yet they are sent on every single turn regardless of relevance. Separately, roughly half of the situations the assistant needs to react to (a customer asking to reschedule, an existing customer complaining, a pricing question, a request to talk to a human) have no reliable signature in conversation state, so a routing mechanism that only activates playbooks from state data can cover at most half of the target scenarios. This feature replaces the mixed prose block with typed, always-on instruction sections; adds an always-on one-line-per-playbook index so the model has a signal to select from; and introduces a model-invoked capability that opens a playbook mid-turn by name when no playbook was already forced by conversation state, injecting that playbook's full body, tools, capabilities, and exits into the same turn without waiting for the next message.

## Clarifications

### Session 2026-09-25

- Q: What exact named options should the Tone and Response-length enums offer on a scout? → A: Tone enum (5, non-null, default `friendly`): `friendly`, `neutral`, `matter_of_fact`, `professional`, `humorous`. Response length enum (3, non-null, default `concise`): `concise`, `standard`, `thorough`. Both are new Rails-enum columns on `ichatr_scouts` that reject any out-of-set value. Each enum value maps to one fixed directive sentence authored in code in the Communication builder — the raw enum key is never shown to the model as prose, and there is no admin path to supply custom wording (the reference panel's free-text "Custom" tone is deliberately excluded, since FR-003 forbids free text).
- Q: Does the always-on prompt's "exactly four sections and nothing else" rule (FR-001, US1 Acceptance Scenario 1) still hold once the playbook index is added, or is the index a separate block appended alongside the four sections? → A: The turn's prompt is composed of ordered blocks: (1) the Instructions block — exactly Identity, Communication, Memory, Safety, nothing else, no v1 bullet, no situational guidance, no rule about when to consult the knowledge base; (2) the playbook index block — always present, empty when no playbook is enabled; (3) the body of the playbook forced by state, with pending fields, only when the router picked one. "Always-on" means the Instructions block plus the index block. The v2 `FALLBACK_INSTRUCTIONS` placeholder in `TurnRunner` (which tells the assistant to consult the knowledge base "when useful", violating FR-006) is removed — the index and `open_playbook` supersede it. Composition tests assert each block independently and never assert that the whole prompt equals the four Instructions sections.
- Q: Does FR-005's "respond only in the configured language" mean a new fixed per-scout language setting, replacing v1's dynamic detect-and-mirror behavior? → A: No. The Safety section keeps v1's behavior exactly: detect the language the customer is writing in and always reply in that same language. The scout gets no language column/setting. Playbook bodies and the prompt itself being authored in Portuguese does not change the reply language — a customer writing in Spanish still gets Spanish replies, as today. "The configured language" is corrected to "the customer's detected language" throughout.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The Instructions block is built from typed sections, not a mixed prose block (Priority: P1)

The turn's prompt is composed of ordered blocks: the Instructions block, the playbook index, and — only when conversation state has forced a playbook — that playbook's body. The Instructions block, sent on every turn regardless of context, is composed from four distinct, purpose-built sections — Identity (the assistant's role and the scope of what it's allowed to talk about), Communication (a small set of named style choices plus a greeting), Memory (what the assistant may retain and for how long), and Safety (the non-negotiable rules: don't invent facts, don't promise anything the business can't deliver, stick to the customer's detected language, stay inside the commercial scope) — and nothing else. Changing a scout's configured communication style changes what gets sent on the very next turn without anyone editing prose text. None of the guidance that only applies to a specific customer situation is part of the Instructions block anymore.

**Why this priority**: Every other piece of this feature (the index, the mid-turn activation) is additional content injected alongside this Instructions block. Until the Instructions block itself is typed and free of situational content, there is nothing well-defined to add the index or the activation mechanism to.

**Independent Test**: Can be fully tested by configuring a scout's communication style and greeting, composing the Instructions block in isolation, and confirming it contains exactly the four typed sections with the configured values reflected, and none of the situational guidance that used to live in the old mixed block.

**Acceptance Scenarios**:

1. **Given** a scout with a configured communication style and greeting, **When** the turn's prompt is composed, **Then** the Instructions block within it contains exactly four sections — Identity, Communication, Memory, and Safety — and nothing else.
2. **Given** a scout's configured tone or response length is changed, **When** the next turn's prompt is composed, **Then** the composed prompt reflects the new value without any prose text being edited.
3. **Given** the Instructions block is composed, **When** its content is inspected, **Then** none of the situational guidance that used to live in the old mixed guideline block is present.
4. **Given** the Instructions block's Safety section is inspected, **Then** it states that a knowledge base exists but does not instruct the assistant on when to consult it.

---

### User Story 2 - Every enabled playbook is always visible to the assistant as a one-line index entry (Priority: P2)

Alongside the typed instructions, the always-on prompt lists every currently enabled playbook as a single line naming the playbook and describing the situation in which it applies. This index is the only signal the assistant has for choosing to open a playbook on its own initiative. Adding a new playbook to the catalog makes it show up in the index automatically, without anyone writing code to register it.

**Why this priority**: The index is what makes mid-turn activation (User Story 3) possible — it depends on User Story 1's Instructions block existing as a defined container to be added alongside, and it must exist before there is anything for the model to select from.

**Independent Test**: Can be fully tested by enabling a set of playbooks, composing the always-on prompt, and confirming it lists exactly one line per enabled playbook with that playbook's name and trigger description, then adding one more playbook to the catalog and confirming the index picks it up without further changes.

**Acceptance Scenarios**:

1. **Given** a set of enabled playbooks, **When** the always-on prompt is composed, **Then** it lists every one of them, exactly one line each, containing that playbook's name and the situation it applies to.
2. **Given** a new playbook is added to the loaded catalog, **When** the always-on prompt is next composed, **Then** the index includes the new playbook's line without any code change.

---

### User Story 3 - The assistant can open a playbook mid-turn by name when nothing forced one by state (Priority: P3)

When conversation state hasn't already pinned the conversation to a specific playbook, the assistant can choose an entry from the index and open it. The moment it does, the playbook's full body comes back as the direct outcome of that action — and by the very next step within that same turn, the tools that playbook declares are available to the assistant, with no need to wait for the customer to send another message. Opening a playbook this way is recorded as a "trigger"-based activation, distinct from a state-based one. When conversation state has already forced a playbook, this activation option is not offered at all. Trying to open a playbook name that doesn't exist returns an error for that specific action, and the turn keeps going.

**Why this priority**: This is the actual mechanism that closes the coverage gap described in the problem statement — the situations with no state signature. It depends on User Story 1 (a defined always-on foundation) and User Story 2 (an index to choose from) both already existing.

**Independent Test**: Can be fully tested by running a turn with no state-forced playbook, having the assistant open a playbook by name from the index, and confirming the playbook's body came back as that action's result, that the playbook's tools are present in what's offered to the assistant on the next step of the same turn, that the activation reason was recorded as trigger-based, and that opening an unknown name produces an error without ending the turn.

**Acceptance Scenarios**:

1. **Given** no playbook is already forced by conversation state, **When** the turn's available actions are assembled, **Then** the action to open a playbook by name is offered to the assistant.
2. **Given** a playbook is already forced by conversation state, **When** the turn's available actions are assembled, **Then** the action to open a playbook by name is not offered.
3. **Given** the assistant opens a valid playbook name, **When** that action completes, **Then** the playbook's full body is returned as the direct outcome of that action, within the same top-level turn.
4. **Given** a playbook was just opened, **When** the assistant reaches the next step within that same turn, **Then** the tools declared by that playbook are available to it — without a new message from the customer and without ending the turn.
5. **Given** a playbook is opened by name, **When** the conversation's state is inspected afterward, **Then** its activation reason is recorded as trigger-based, distinct from a state-based activation.
6. **Given** the assistant attempts to open a playbook name that does not exist in the catalog, **When** that action completes, **Then** it returns an error for that specific action and the turn continues without failing.

---

### Edge Cases

- A scout has zero enabled playbooks: the index is empty and, since there is nothing to open, opening a playbook is a no-op path only reachable through Scenario 6 (unknown name → error), never through a valid selection.
- Two enabled playbooks describe overlapping situations in their trigger text: the system does not detect or prevent this automatically — which one applies in an ambiguous case is determined entirely by how the trigger text is worded, and that wording is expected to be reviewed by a person, not validated by the system at load time.
- A playbook opened mid-turn declares no exit conditions at all: the turn simply has nothing added to it from that source; injecting an empty exit set is not an error.
- The assistant opens the same playbook a second time later in the same turn (e.g., after being interrupted by another action): the playbook's tools are already available from the first opening; nothing about this feature requires guarding against a redundant re-open.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The turn's prompt MUST be assembled from ordered blocks; the Instructions block within it MUST contain exactly four sections — Identity, Communication, Memory, and Safety — and no other content.
- **FR-002**: The Identity section MUST state the assistant's role and the scope of topics it is allowed to address.
- **FR-003**: The Communication section's tone MUST be a per-scout setting with exactly five named values — `friendly` (default), `neutral`, `matter_of_fact`, `professional`, `humorous` — and its response length MUST be a per-scout setting with exactly three named values — `concise` (default), `standard`, `thorough`; both settings MUST be non-null and MUST reject any value outside their set. Each named value MUST map to one fixed directive sentence authored in code in the Communication section (never the raw value name or admin-supplied free text); the section MUST also include the scout's configured greeting.
- **FR-004**: The Memory section MUST state the assistant's data-retention policy.
- **FR-005**: The Safety section MUST state the non-negotiable rules — do not fabricate information, do not promise outcomes the business cannot guarantee, detect the language the customer is writing in and respond only in that language, and stay within commercial scope.
- **FR-006**: The Safety section MUST state that a knowledge base exists, and MUST NOT instruct the assistant on when to consult it.
- **FR-007**: Changing a scout's configured tone, response length, or greeting MUST change the content of the next composed prompt without any free-text/prose editing.
- **FR-008**: The always-on prompt MUST NOT contain any of the situational guidance that, in the prior always-on block, only applied to a specific customer intent.
- **FR-009**: The always-on prompt MUST include an index listing every currently enabled playbook, exactly one line per playbook, each line containing that playbook's name and the situation in which it applies.
- **FR-010**: The index MUST be derived from the currently loaded playbook catalog at composition time, such that adding an enabled playbook to the catalog causes it to appear in the index without additional code changes.
- **FR-011**: When no playbook is currently forced by conversation state, the assistant MUST be offered an action that opens a playbook from the index by name.
- **FR-012**: When a playbook is currently forced by conversation state, the action to open a playbook by name MUST NOT be offered.
- **FR-013**: Opening a valid playbook name MUST return that playbook's full body as the direct outcome of that action, within the same top-level turn — not deferred to a subsequent turn.
- **FR-014**: Immediately after a playbook is opened, the tools declared by that playbook MUST become available to the assistant for the remainder of that same turn. The playbook's declared capabilities (`requires`) and exit conditions remain reachable as data only, exactly as they already are for a state-activated playbook — this feature MUST NOT introduce a new capability-resolution or exit-tool mechanism (see Assumptions).
- **FR-015**: Opening a playbook via this mechanism MUST record the conversation's activation reason as trigger-based, distinguishable from a state-based activation.
- **FR-016**: Attempting to open a playbook name absent from the catalog MUST return an error outcome for that specific action, and the turn MUST continue rather than fail.
- **FR-017**: This feature MUST NOT change the prompt assembly, tool selection, or behavior of the existing (v1) execution path in any way.
- **FR-018**: The turn's prompt MUST be assembled, in order, from the Instructions block, the playbook index block, and — only when conversation state has forced a playbook — that playbook's body with its pending fields; the playbook index block MUST always be present, even when it lists zero playbooks.
- **FR-019**: The v2 execution path's placeholder instructions used when no playbook is forced by state, which today direct the assistant to consult the knowledge base "when useful" (violating FR-006), MUST be removed; the always-present playbook index and the open-playbook action supersede this placeholder.

### Key Entities

- **Instructions Block**: The four typed sections (Identity, Communication, Memory, Safety), the first of the turn's ordered prompt blocks, sent on every turn regardless of which playbook, if any, is active; replaces the prior mixed prose guideline block for the new execution path.
- **Communication Style Configuration**: Per-scout settings — `tone` (non-null, `friendly` default / `neutral` / `matter_of_fact` / `professional` / `humorous`) and `response_length` (non-null, `concise` default / `standard` / `thorough`), each rejecting any out-of-set value — plus a free-form greeting; each named value maps to one fixed directive sentence authored in code, never surfaced to the model as its raw name, with no admin path for custom wording.
- **Playbook Index**: The always-on list, one line per enabled playbook, giving the assistant its only always-visible signal (name plus trigger situation) for choosing to open a playbook on its own initiative.
- **Mid-Turn Playbook Activation**: The action available to the assistant, only when no playbook is already forced by state, that opens a named playbook from the index, returns its body as that action's result, and makes its declared tools available for the rest of the same turn. Its `requires`/`exits` remain reachable as data only, per Assumptions.
- **Activation Reason**: The per-conversation record of why the currently active playbook became active — state-based (conversation data matched a condition) or trigger-based (the assistant opened it by name mid-turn).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of composed turn prompts' Instructions blocks contain exactly the four typed sections (Identity, Communication, Memory, Safety) and zero instances of the situational guidance that used to be mixed into the prior block.
- **SC-002**: Changing a scout's tone, response length, or greeting configuration is reflected in the very next turn's composed prompt, with zero prose edits required.
- **SC-003**: 100% of enabled playbooks appear in the index as exactly one line each, and adding a new enabled playbook requires zero additional code changes for it to appear.
- **SC-004**: 100% of turns where no playbook is forced by state and the assistant opens a valid playbook end with that playbook's tools available by the very next step of the same turn — zero turns lost waiting for another customer message.
- **SC-005**: 100% of turns where a playbook is already forced by state show the open-playbook action absent from what's offered to the assistant.
- **SC-006**: 100% of attempts to open a non-existent playbook name complete with an error for that action and zero turn failures.
- **SC-007**: 100% of composed turn prompts include the playbook index block — present even when it lists zero playbooks — and zero instances of the removed placeholder guidance that previously told the assistant when to consult the knowledge base.

## Assumptions

- This feature builds directly on the turn engine, playbook catalog, and conversation-state routing delivered by the two prior phases of this epic; it reuses them as-is and does not redesign how a playbook is loaded, validated, or matched by state.
- Preventing two enabled playbooks from both claiming the same ambiguous situation is handled entirely through how their trigger descriptions are worded and reviewed by a person before being enabled — this feature does not add automatic detection or validation for overlapping triggers.
- What happens when the assistant reaches a playbook's declared exit condition (the handoff/ending mechanism itself) is a later phase's responsibility. This feature does not build a capability-tool adapter or an exit-tool mechanism: a playbook's declared `requires` (capabilities) and `exits` remain reachable as data on the playbook object once opened — exactly as they already are for a state-activated playbook today — not as new tools or actions injected into the turn. Only the playbook's declared `tools:` list is injected as new callable tools by this feature.
- Beyond the one playbook already delivered by the prior phase, no additional playbooks are introduced by this feature; validating the index and mid-turn activation end-to-end only requires that one playbook plus whatever additional catalog entries are used for index-listing verification.
- A model-driven mechanism that chooses a playbook to open purely from conversational intent, rather than the assistant explicitly naming one from the index, is intentionally deferred to a later phase; today's mechanism only opens a playbook the assistant itself selects by name.
- Translating playbook body content for other languages is a separate, later initiative and out of scope here.
- No changes are made to the existing (v1) execution path's prompt assembly; it continues to behave exactly as it does today.
- The Safety section's language rule reuses v1's dynamic detect-and-mirror behavior as-is (detect the customer's language per message, reply in it); this feature adds no language column or setting to `Scout`, and playbook bodies being authored in Portuguese does not change the reply language.
- A playbook opened by the assistant stays active until a `when_state` playbook with strictly higher priority interrupts it. `open_playbook` is offered only when the router returns no playbook at all — no `when_state` match and no active playbook, however that playbook was activated (design §4.4 rule 4: "nenhuma casa e sem ativa → só índice; o modelo abre por trigger") — so FR-012 stands as written and no code guards against a wrong or customer-steered opening. This is a known, accepted limit of this phase: Brief 05 removes it with exits, where a terminal exit clears the active playbook. It is safe because the `scout_v2` account flag is on only for development accounts, and no production account gets it before Brief 10's preflight, which comes after Brief 05 — already decided in Brief 03 decision 1 and design §4.11 and §6 (Fase 5); this feature adds nothing new about it.
