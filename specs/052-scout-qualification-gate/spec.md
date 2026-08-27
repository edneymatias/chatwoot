# Feature Specification: Scout Funnel Stage Qualification Gate

**Feature Branch**: `052-scout-qualification-gate`

**Created**: 2026-08-27

**Status**: Draft

## Clarifications

### Session 2026-08-27

- Q: Should the automatic handoff fire every time a stage-move call successfully targets the qualified stage, or only the first time the opportunity actually transitions into it? → A: Only when the opportunity's stage actually changes into the qualified stage (no-op if it was already there) — a one-time "on enter" event, not something that re-fires on every redundant call.
- Q: Should the free-text descriptions already configurable on funnel stages and on custom attribute definitions be included in what's exposed to the Scout agent? → A: Yes — both the stage's own purpose description and each required attribute's semantic description should be surfaced alongside the name/type information already planned, whenever the operator has filled them in.

**Input**: User description: "Fase 9 — Inteligência de Funil: Estágios & Campos de Qualificação. O Scout (agente SDR) hoje não recebe nenhuma informação sobre os estágios do funil da conta nem sobre os campos obrigatórios de qualificação, então move oportunidades para estágios arbitrários ou nunca as move. Além disso, quando uma movimentação de estágio viola os campos obrigatórios já validados no model, a exceção estoura e a conversa cai num fail-safe genérico em vez do agente receber um retorno acionável. Os campos globais de qualificação do Scout também não têm nenhum efeito hoje. É preciso: (1) informar o agente sobre o catálogo de estágios, papéis semânticos (padrão/qualificado/desqualificado) e campos obrigatórios via prompt; (2) impedir a movimentação para o estágio qualificado sem os campos globais de qualificação preenchidos, devolvendo mensagem descritiva; (3) tratar de forma descritiva (sem estourar exceção) qualquer movimentação para frente que viole campos obrigatórios do estágio, tanto via move_opportunity_stage quanto via manage_opportunity; (4) disparar automaticamente o handoff para o time humano ao qualificar, sem exigir uma chamada separada; (5) tratar desqualificação como fila de revisão humana (o Scout nunca marca a oportunidade como perdida/ganha — isso é sempre uma ação humana feita depois via Kanban)."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Scout Agent Understands the Funnel It's Operating In (Priority: P1)

While qualifying a prospect in an active conversation, the Scout agent needs to know which funnel stages exist for the account, which one represents "qualified", which one represents "needs human review" (unqualified), and what information must be collected before an opportunity can enter each of those stages. Today the agent has none of this — it either never advances the opportunity or advances it to stage identifiers that don't correspond to any real, meaningful stage.

**Why this priority**: Without this information, none of the qualification/handoff automation in later stories can work — the agent has no basis for choosing a correct stage or knowing what data it still needs to collect. This is the foundation the rest of the feature depends on.

**Independent Test**: Can be tested by starting a Scout conversation for an account with configured funnel stages and required attributes, and confirming the agent references the correct stage names/purposes and asks for the correct qualification data during the conversation instead of guessing or staying silent about stage progression.

**Acceptance Scenarios**:

1. **Given** an account with configured funnel stages, **When** a Scout conversation begins, **Then** the agent has access to every stage's name and, where applicable, whether it is the default, qualified, or unqualified stage.
2. **Given** a funnel stage that has a purpose description configured by the operator, **When** the agent's operating context is built, **Then** the agent has access to that description alongside the stage's name, so it understands what the stage is for, not just its label.
3. **Given** a funnel stage with attributes required to enter it, **When** the agent is deciding what to ask the prospect, **Then** the agent has access to the display name, type, allowed values (when applicable), and semantic description (when configured) of each required attribute for that stage.
4. **Given** the account's global qualification requirements (attributes required specifically to reach the qualified stage), **When** the agent is close to qualifying a prospect, **Then** the agent has access to those requirements — including their semantic descriptions when configured — clearly distinguished from any single stage's own requirements.
5. **Given** an account that has not configured a qualified stage, an unqualified stage, stage-specific requirements, or descriptions for a stage/attribute, **When** the agent's operating context is built, **Then** the corresponding guidance is simply absent rather than shown as broken or empty.

---

### User Story 2 - Qualification Cannot Happen Without Required Data (Priority: P1)

An account requires certain data (e.g. budget, company size, timeline) before a lead is considered "qualified" and handed to a human. The Scout agent must not be able to move a prospect's opportunity into the qualified stage while that data is still missing — doing so would send an incomplete lead to the sales team.

**Why this priority**: This is the actual business guarantee behind "qualification" — if it can be bypassed, the feature provides no real value and the sales team loses trust in what "qualified" means.

**Independent Test**: Can be tested by attempting to move an opportunity into the qualified stage while a required global qualification attribute is missing, and confirming the move is rejected with a clear explanation instead of silently succeeding or crashing.

**Acceptance Scenarios**:

1. **Given** an opportunity missing one or more of the account's global qualification requirements, **When** the Scout agent attempts to move it to the qualified stage, **Then** the move is rejected, the opportunity's stage does not change, no handoff occurs, and the agent receives a message naming the specific missing attributes.
2. **Given** an opportunity that satisfies all global qualification requirements and any requirements specific to the qualified stage, **When** the Scout agent moves it to the qualified stage, **Then** the move succeeds.
3. **Given** the agent just received a "missing attributes" message, **When** the conversation continues, **Then** the agent can keep collecting the missing data and retry the move later in the same conversation.

---

### User Story 3 - Qualified Leads Are Handed Off Automatically (Priority: P2)

Once an opportunity successfully reaches the qualified stage, the assigned sales team should receive it immediately — assigned, notified, and with context — without the Scout agent needing to remember or perform a second, separate action.

**Why this priority**: A qualified lead that sits unassigned because the agent "forgot" the extra step defeats the purpose of automating qualification. This closes the loop between "qualified" and "in a human's hands."

**Independent Test**: Can be tested by successfully moving an opportunity into the qualified stage and confirming the sales team is assigned and notified, and relevant context is preserved, without any additional action from the agent.

**Acceptance Scenarios**:

1. **Given** an opportunity that just successfully moved into the qualified stage, **When** the move completes, **Then** the account's designated sales team is automatically assigned to the conversation and the conversation is handed off to human ownership.
2. **Given** the automatic handoff has just occurred, **When** the agent's next turn happens, **Then** the agent does not need to (and should not) separately request a handoff for this same qualification event.
3. **Given** an opportunity that is already sitting in the qualified stage, **When** the agent issues another (redundant) stage-move call targeting that same qualified stage, **Then** no additional handoff is triggered — the handoff is a one-time event tied to the opportunity actually entering the qualified stage.

---

### User Story 4 - Forward Stage-Move Violations Give the Agent Something to Act On (Priority: P2)

If the Scout agent tries to move an opportunity forward into a stage whose own required attributes aren't satisfied yet, the conversation should continue normally with the agent told what's missing — not fail outright and hand the prospect a generic "something went wrong" message.

**Why this priority**: Today this failure mode ends the agent's ability to reason about the conversation (it falls back to a generic safety handoff), which is a worse outcome for the prospect than simply asking for more information. Fixing this materially improves conversation reliability.

**Independent Test**: Can be tested by attempting a forward stage move (via either of the two ways the agent can change an opportunity's stage) into a stage with unmet required attributes, and confirming the conversation continues with a specific, actionable message rather than a generic failure.

**Acceptance Scenarios**:

1. **Given** a stage with required attributes not yet satisfied, **When** the agent attempts to move an opportunity forward into it, **Then** the opportunity's stage does not change, and the agent receives a message identifying the specific missing attributes by name.
2. **Given** the same failing scenario, **When** it occurs through either of the two agent capabilities that can change an opportunity's stage, **Then** the outcome and message are consistent — neither capability bypasses the check the other enforces.
3. **Given** a stage move backward or sideways (not forward) in the funnel, **When** the agent performs it, **Then** today's existing behavior is preserved (no new attribute enforcement is introduced for these moves).

---

### User Story 5 - Unqualified Leads Go to Human Review, Not to a Dead End (Priority: P3)

When a prospect doesn't meet the bar to qualify, the Scout agent routes the opportunity to a stage meant for human review rather than closing it out as a lost deal. Closing a deal (won or lost) is a decision reserved for a human, made later through the existing sales tools.

**Why this priority**: This protects deal-outcome data integrity — an automated agent unilaterally declaring a deal "lost" is a bigger risk than a slightly slower disqualification path, and a human may see qualifying context the agent missed.

**Independent Test**: Can be tested by moving an opportunity into the unqualified stage and confirming its open/closed outcome is untouched and no handoff is triggered, alongside confirming the agent's actions never set an opportunity's outcome to lost or won.

**Acceptance Scenarios**:

1. **Given** a prospect who does not qualify, **When** the Scout agent moves the opportunity to the unqualified stage, **Then** only the stage changes — the opportunity remains open, and no handoff is triggered.
2. **Given** any conversation state, **When** the Scout agent takes any action, **Then** the opportunity is never marked as won or lost by that action — closing an opportunity remains an exclusively human action performed outside the agent's capabilities.

---

### Edge Cases

- What happens when the Scout agent references a stage identifier that doesn't exist on the account? The move must be rejected with a descriptive message and no data change, without crashing the conversation.
- What happens when an account has no qualified stage, no unqualified stage, or no stage-specific requirements configured at all? The related guidance is simply omitted from the agent's context, and the corresponding enforcement/automation for the missing piece does not apply.
- How does the system prevent the qualification gate from being bypassed by using a different capability than the "official" stage-move capability to change an opportunity's stage? Both paths must enforce the same checks and produce the same outcome.
- What happens if an opportunity is created directly inside a stage that has required attributes? Initial creation is unaffected by this feature — enforcement only applies to subsequent stage changes.
- What happens to attribute enforcement on backward or lateral stage moves? Unchanged from current behavior — this feature does not extend enforcement to those moves.
- What happens if the Scout agent issues a redundant stage-move call targeting the qualified stage while the opportunity is already there? The stage-move call succeeds as a no-op for the stage itself, but the automatic handoff does not fire again — it only fires on the actual transition into the qualified stage.
- What happens when a stage or a required attribute has no description configured? Only that description is omitted; the stage/attribute is still fully surfaced by its name, type, and other configured details.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST make the account's funnel stage catalog (stage names, each stage's purpose description when the operator has configured one, and, where configured, which one is the default, qualified, and unqualified stage) available to the Scout agent's operating context for every conversation.
- **FR-002**: System MUST make, for each funnel stage that has configured required attributes, those attributes' display names, expected types, allowed values (when applicable), and semantic descriptions (when configured) available to the Scout agent.
- **FR-003**: System MUST make the account's global qualification requirements (attributes required specifically to enter the qualified stage) available to the Scout agent — including each attribute's semantic description when configured — clearly distinguished from any individual stage's own requirements.
- **FR-004**: System MUST instruct the Scout agent that moving an opportunity into the qualified stage automatically triggers handoff to the sales team, and that the agent must not separately request a handoff for that same event.
- **FR-005**: System MUST instruct the Scout agent that moving an opportunity into the unqualified stage is a request for human review, not a deal closure, and that reasoning should be recorded as a note rather than as a lost-deal reason.
- **FR-006**: When the Scout agent attempts to move an opportunity into the qualified stage while any global qualification requirement is unmet, System MUST reject the move, leave the opportunity's stage unchanged, MUST NOT trigger a handoff, and MUST return a message identifying the specific missing attributes.
- **FR-007**: When the Scout agent attempts to move an opportunity forward in the funnel into a stage whose own required attributes are unmet, System MUST reject the move and return a message identifying the specific missing attributes, instead of failing the conversation or falling back to a generic error/handoff.
- **FR-008**: System MUST apply the checks in FR-006 and FR-007 consistently across every agent capability capable of changing an opportunity's stage, so that no capability offers a way to bypass the checks enforced by another.
- **FR-009**: When an opportunity's stage actually changes into the qualified stage (a real transition, not a redundant call while already there), System MUST automatically perform the handoff to the account's designated sales team (team/owner assignment, transition of the conversation to human ownership, and preservation of contact context) without requiring a separate agent action. System MUST NOT repeat this handoff for subsequent calls that target the qualified stage while the opportunity is already in it.
- **FR-010**: When an opportunity moves into the unqualified stage, System MUST change only its stage — it MUST NOT alter the opportunity's open/closed outcome and MUST NOT trigger a handoff.
- **FR-011**: System MUST NOT permit the Scout agent to directly mark an opportunity as won or lost under any circumstance; closing an opportunity remains an action performed only by a human through existing tools outside the agent's capabilities.
- **FR-012**: System MUST preserve existing behavior for backward or lateral stage moves (no new required-attribute enforcement introduced for those moves by this feature).
- **FR-013**: System MUST preserve existing behavior for opportunity creation (initial creation remains unaffected by the required-attribute checks introduced by this feature).
- **FR-014**: If an account has not configured a qualified stage, an unqualified stage, or any stage-specific required attributes, System MUST omit the corresponding guidance and skip the corresponding enforcement/automation, rather than requiring the operator to configure everything upfront. Likewise, if a given stage or required attribute has no description configured, System MUST omit just that description (the stage/attribute itself is still surfaced by its name/type) rather than showing an empty or placeholder description.

### Key Entities

- **Funnel Stage**: A step in an account's sales pipeline; may be flagged as the default entry stage, the qualified stage, or the unqualified stage for a given Scout configuration, may carry an operator-authored purpose description, and may define its own set of required attributes.
- **Stage Required Attribute**: An opportunity attribute (with a display name, type, optional allowed values, and an optional semantic description of what it means) that must be filled in before an opportunity can enter a specific funnel stage.
- **Scout Qualification Requirement**: An opportunity attribute an account has designated as globally required for a prospect to be considered qualified, evaluated in addition to whatever the qualified stage itself requires; carries the same display name/type/description as any other attribute definition.
- **Opportunity**: The deal/lead record being progressed through funnel stages during a Scout conversation; carries an open/closed outcome that is separate from its current stage.
- **Handoff**: The act of transferring conversation ownership and lead context from the Scout agent to a human sales team, including team/owner assignment and preserved context.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of Scout stage-move attempts reference a stage that actually exists and has a defined purpose on the account, eliminating moves to arbitrary or meaningless stages.
- **SC-002**: 100% of opportunities that reach the qualified stage through the Scout agent have every globally required qualification attribute filled in at the moment they reach it.
- **SC-003**: Conversations that hit a forward stage-move validation failure continue normally (the agent can keep collecting information and retry) instead of falling back to a generic failure/handoff — reducing this failure mode's fallback rate to zero.
- **SC-004**: 100% of opportunities that transition into the qualified stage result in exactly one completed handoff (team/owner assigned, conversation transitioned to human ownership) with no manual follow-up step and no duplicate handoffs from redundant stage-move calls.
- **SC-005**: Zero opportunities are marked as won or lost directly by the Scout agent after this feature ships; all such outcomes continue to be set exclusively by a human.

## Assumptions

- The existing configuration surfaces for funnel stages, per-stage required attributes, closing-required attributes, and the Scout funnel settings (default/qualified/unqualified stage selection, global qualification requirements, handoff team) remain unchanged; this feature makes that existing configuration take effect and become visible to the agent, rather than introducing new configuration UI.
- "Qualified" and "unqualified" stage roles, and the global qualification requirements, are configured per Scout account exactly as today's existing settings already allow; accounts that leave them unset simply don't get the corresponding enforcement or automation yet.
- Global qualification requirements are evaluated only at the point of entering the qualified stage, not against every stage in the funnel.
- A "descriptive message" on a rejected move means human-readable text naming the missing attributes by their display name, returned to the agent so it can continue the conversation — not a raw system error.
- Enforcement introduced by this feature applies only to forward stage moves and to entering the qualified stage; backward/lateral moves and opportunity creation keep their current, unchanged behavior.
- Stage purpose descriptions and attribute semantic descriptions are authored by the operator through the existing, already-shipped configuration surfaces (the funnel stage description editor and the custom attribute definition form); this feature only makes already-configurable text reach the agent's context and does not add any new field or editing UI.
