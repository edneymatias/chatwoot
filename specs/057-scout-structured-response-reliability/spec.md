# Feature Specification: Scout Structured Response Reliability

**Feature Branch**: `057-scout-structured-response-reliability`

**Created**: 2026-08-28

**Status**: Draft

**Input**: User description: "Em testes reais, 3 de 3 conversas iniciadas com Scout terminaram em erro de interpretação da resposta estruturada do modelo (fail-safe handoff), mesmo com o guardrail de prompt (Fase 08) instruindo o formato JSON. Se toda conversa cai em erro de parsing, o agente nunca chega a atuar — sempre entrega pro humano. Precisa garantir que a resposta do modelo seja confiável em formato estruturado, investigando o suporte a saída estruturada por schema já disponível na gem `ruby_llm` (`with_schema`) em vez de depender só de instrução via prompt, sem enfraquecer a garantia existente de nunca expor conteúdo bruto/malformado ao cliente quando uma falha realmente ocorrer."

## Clarifications

### Session 2026-08-28

- Q: Qual deve ser a meta numérica para a taxa de falha de parsing, substituindo o "pequena minoria" vago em SC-001? → A: Menos de 5% dos turnos.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Scout completes AI-driven conversations instead of defaulting to a human handoff (Priority: P1)

A customer is chatting with Scout. Today, in real usage, essentially every conversation ends with
Scout failing to produce a response in the expected structured format and handing the conversation
off to a human — even when the model correctly understood the customer and correctly called the
right tools. This means the core value of Scout (AI-driven qualification without human
intervention) is not being delivered in practice; the assistant behaves as if it is permanently
broken. This story ensures Scout reliably produces a response the system can use, so conversations
routinely complete without an unnecessary handoff.

**Why this priority**: This is the entire reason Scout exists. If nearly every turn fails to
produce a usable response, none of Scout's other capabilities (qualification, tool use,
opportunity tracking) matter — the product is non-functional in its primary job.

**Independent Test**: Can be fully tested by running multiple real qualification conversations
with Scout (including ones that involve at least one tool call before the model's final reply) and
confirming that fewer than 5% of turns trigger the "failed to interpret structured response"
fail-safe path, with the rest completing normally with the customer receiving the model's actual
response.

**Acceptance Scenarios**:

1. **Given** a customer conversation where the model correctly understands the customer's message
   and (optionally) calls one or more tools, **When** the model produces its final turn response,
   **Then** the customer receives that response and the conversation continues normally, without a
   fail-safe handoff caused by a response-format failure.
2. **Given** a series of real conversations run back-to-back, **When** each completes at least one
   full turn, **Then** fewer than 5% of turns fail specifically due to response-format/parsing
   errors — not the default outcome, as observed before this feature.

---

### User Story 2 - The existing safety guarantee still holds on genuine failures (Priority: P2)

On the rare occasion a usable, valid response still cannot be obtained from the model, Scout must
continue to behave exactly as the existing safety design requires: it must never show the customer
raw, malformed, or partially-formed model output (which could leak internal reasoning or broken
text), and it must still hand off to a human cleanly, the same way it does today.

**Why this priority**: This preserves a safety guarantee the product already established
deliberately (fail closed, never leak raw model output) — improving reliability must not come at
the cost of that guarantee, so it's verified explicitly, but it is not the primary problem being
solved here.

**Independent Test**: Can be tested by forcing a genuine response failure (e.g. simulating a
provider/model that cannot produce a valid response) and confirming the customer never sees raw or
malformed content, and the conversation is still hung off to a human, exactly as before.

**Acceptance Scenarios**:

1. **Given** a conversation where the model still fails to produce a usable response despite the
   reliability improvements, **When** that failure occurs, **Then** the customer is handed off to a
   human exactly as today (public transfer notice, private note, no raw content shown), with no
   change in that failure-handling behavior.

---

### Edge Cases

- What happens if the account's configured LLM provider/model does not support enforced structured
  output? Scout must continue operating (falling back to today's prompt-only approach for that
  provider) rather than refusing to respond or crashing.
- What happens when the model needs to call one or more tools before producing its final answer in
  the same turn? Enforcing a reliable response structure must not prevent or break tool calls
  within that turn.
- What happens to the internal `reasoning` field (today logged only, never shown to the customer)
  once responses are obtained more reliably? It must remain internal-only, exactly as established
  previously — this feature does not change what happens with `reasoning`.
- What happens if a response is obtained reliably but is otherwise empty or nonsensical (not a
  parsing failure, just a bad answer)? Out of scope here — this feature addresses format
  reliability, not response quality/content auditing (a separate, already-tracked future concern).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When Scout's configured LLM provider/model supports enforcing a response structure at
  the API level, System MUST use that enforcement, rather than relying solely on instructing the
  format through the prompt text as it does today.
- **FR-002**: The message delivered to the customer MUST come only from a validated, structured
  response field — never from unvalidated raw model output, in either the reliable or fallback
  path.
- **FR-003**: When a usable structured response still cannot be obtained, System MUST continue to
  fail closed exactly as it does today: no raw/malformed content shown to the customer, existing
  private note created, existing fail-safe handoff triggered.
- **FR-004**: System MUST continue to support the model calling one or more tools within the same
  turn as producing its final response; structured-response reliability MUST NOT break or bypass
  tool-calling.
- **FR-005**: When the configured provider/model does not support enforced structured output,
  System MUST continue operating using today's prompt-instructed format approach for that
  provider/model, rather than failing to respond at all.
- **FR-006**: The internal `reasoning` field's handling (logged only, never surfaced to the
  customer) MUST remain unchanged by this feature.

### Key Entities

- **Structured Turn Response**: The model's per-turn output, expected to contain an internal
  `reasoning` value and a customer-facing `response` value; the entity whose reliability this
  feature improves.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Across real conversations handled by Scout, the share of turns that fail specifically
  due to response-format/parsing errors drops from the near-100% observed before this feature to
  under 5% of turns.
- **SC-002**: Customers can complete multi-turn qualification conversations that involve at least
  one tool call and receive the model's actual reply, without being routed to a human solely
  because of a response-format failure.
- **SC-003**: When a response-format failure does still occur, 100% of those cases continue to
  result in the existing safe fail-closed behavior (no raw content ever shown to the customer) —
  zero regressions on that existing guarantee.

## Assumptions

- The exact mechanism used to enforce structured output (for example, the `ruby_llm` gem's
  `with_schema` capability, or an equivalent provider-native structured-output feature) is a
  technical decision for the planning phase, not fixed by this specification — this spec only
  requires that the response be reliably structured, not how that reliability is achieved.
- Not all LLM providers/models necessarily support schema-enforced structured output identically;
  provider-specific behavior and any related configuration is a planning-phase concern.
- This feature is distinct from, and does not replace, the previously scoped (currently preview,
  not yet committed) Response Auditor concept — that concept audits the *content* of an
  already-successfully-parsed response (e.g. missed handoffs, unfulfilled promises); this feature
  addresses reliably *obtaining* a parseable response in the first place, which is a prerequisite
  problem that occurs earlier in the pipeline.
- The "fail closed" safety behavior on genuine failures (established previously) is a constraint
  this feature must preserve, not a behavior this feature is meant to change.
