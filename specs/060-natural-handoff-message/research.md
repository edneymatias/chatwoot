# Research: Natural Handoff Message

No `NEEDS CLARIFICATION` markers remained in the plan's Technical Context — the source design
document (`docs/kanban/ciclo 10/scout/20-automatic-handoff-reevaluation/spec80.md`) had already
made every implementation-relevant decision, including explicitly closing the one open question
carried over from its preceding preview doc. This file records those decisions in the
decision/rationale/alternatives format for traceability, rather than resolving new unknowns.

## Decision 1: Which mechanism decides a handoff is needed

**Decision**: Keep both existing triggers as-is — the assistant's own `handover_to_human` tool
call, and the mechanical trigger fired by `OpportunityStageTransitionService` when an opportunity
reaches the qualified pipeline stage. Neither is removed or replaced.

**Rationale**: The mechanical trigger is deterministic and tied to the pipeline-stage event itself,
not to LLM judgment that can silently fail — it was built specifically because Scout previously
confirmed scheduling without ever alerting a human (documented production incident, Phase 18
conversations 20/22). Removing it in favor of trusting the LLM 100% would reintroduce that
documented risk for no benefit, since the actual customer complaint (generic message tone) has
nothing to do with which mechanism decides the handoff.

**Alternatives considered**:
- *Delayed safety-net re-evaluation* (re-check after N turns instead of firing immediately) —
  rejected in the preceding preview doc; abandoned in favor of fixing message quality directly.
- *Eliminate the mechanical trigger entirely, rely only on the model* — rejected; reopens the
  documented "no human ever notified" failure mode.

## Decision 2: How to source the customer-facing handoff message

**Decision**: Use the model's own parsed `response` text for the current turn as the handoff
message on both trigger paths, falling back to the existing fixed `I18n.t('conversations.scout.handoff')`
string only when that text is unparseable or blank.

**Rationale**: The flat, repeated fixed sentence is the actual complaint — not the trigger
mechanism. The model already produces a natural-language closing turn in both cases; the current
code discards it in one path (`handover_to_human` returns before parsing even happens) and ignores
it on purpose in the other (mechanical trigger, originally discarded to defend against a "question
then transfer" bug). Sourcing the message from the model preserves conversational tone while a new
prompt guardrail (Decision 3) replaces the discard-based defense with an explicit instruction.

**Alternatives considered**:
- *Keep discarding the model's text, only reword the fixed sentence* — rejected; a single fixed
  sentence, however reworded, can never reflect what specifically happened in a given conversation.
- *Sanitize/validate the model's text before use (e.g., reject if it ends in "?")* — explicitly
  rejected in the source design as brittle pattern-matching over natural language, which conflicts
  with an established project principle; the prompt guardrail is the only control.

## Decision 3: How to prevent the "asks a question and transfers anyway" regression

**Decision**: Extend the existing "Fallback para humano" guardrail bullet in
`SystemPromptsService#guardrails_section` with an explicit instruction: whenever a turn will end in
handoff (via tool call or automatic qualification), the model's final response must be a natural
closing statement confirming what was registered and explaining a human will continue — never a
question, since the customer cannot answer it before the transfer completes.

**Rationale**: This was the root cause of the original bug that motivated discarding model text in
the first place. Since Decision 2 now surfaces that text to the customer, the defense must move
from "discard it" to "instruct the model not to write it that way" — consistent with the project's
existing principle of using prompt guidance over hardcoded text validation.

**Alternatives considered**: See Decision 2's rejected sanitization alternative — same reasoning
applies here (no regex/pattern-matching gate on the model's output).

## Decision 4: Scope boundary — which handoff paths are NOT affected

**Decision**: Two existing paths keep using the fixed `I18n` sentence unchanged:
1. `AgentRunner#perform_fail_safe_handoff` (system failures: quota exhaustion, unhandled errors,
   response-parsing failure) — no reliable model text exists in these cases.
2. `Custom::Scout::ResponseAuditor#execute_handoff` (the `ActionClassifierService`-driven handoff
   from Phase 12) — this handoff is decided by a classifier reading the whole conversation history,
   independent of the current turn's drafted text, so there is no turn-specific message to
   attribute it to.

**Rationale**: Both are correctness-preserving exclusions, not oversights — using model text in
either case would either be impossible (no text exists) or misleading (the model may not know this
handoff path is about to happen). Documented explicitly to prevent scope creep during
implementation.

**Alternatives considered**: None — both exclusions were explicit, reasoned decisions in the source
design document, not left ambiguous.
