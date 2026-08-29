# Feature Specification: Scout Observability & Handoff Notice

**Feature Branch**: `056-scout-observability-handoff-notice`

**Created**: 2026-08-28

**Status**: Draft

**Input**: User description: "Fase 17 — Observabilidade do Scout e Aviso de Handoff ao Cliente. Dar visibilidade real sobre o que acontece dentro de uma execução do Scout (chamadas de LLM, chamadas de tool, erros) via a plataforma de observabilidade já usada pelo Captain, e garantir que o cliente nunca fique sem nenhuma mensagem quando o Scout sai da conversa, em qualquer um dos dois caminhos de handoff (fail-safe e handoff explícito)."

## Clarifications

### Session 2026-08-28

- Q: Should the customer-facing transfer message use the exact same fixed wording every time, or should it vary depending on which handoff path (or specific reason) triggered it? → A: One single fixed message, reused for every handoff regardless of path or reason.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Customer is told the conversation is being transferred (Priority: P1)

A customer is chatting with Scout, the fork's own AI assistant. At some point Scout can no
longer continue — either because it hit an unrecoverable error/quota limit (fail-safe path) or
because it decided the conversation needs a human (explicit handoff path). Today, in both cases,
the customer sees nothing: the conversation just goes quiet and later a human picks it up with no
explanation. This story ensures the customer always gets a visible message telling them the
conversation is being handed to a person, regardless of which path triggered the handoff.

**Why this priority**: This is the direct customer-experience gap — a customer left with silence
looks like a broken product and erodes trust, and it's the more severe of the two problems since
it affects every customer, every time a handoff happens.

**Independent Test**: Can be fully tested by driving a conversation with Scout into each of the two
handoff paths (triggering an unrecoverable error, and triggering an explicit handoff) and
confirming the customer's conversation thread shows a transfer message in both cases, independent
of whether any observability tooling is configured.

**Acceptance Scenarios**:

1. **Given** a customer conversation being handled by Scout, **When** Scout hits an unrecoverable
   error or exhausts its usage quota (fail-safe path), **Then** the customer sees a public message
   informing them the conversation is being transferred to a human, before the conversation is
   reopened for the human queue.
2. **Given** a customer conversation being handled by Scout, **When** Scout decides to explicitly
   hand the conversation to a human, **Then** the customer sees a public message informing them of
   the transfer, before the conversation is reopened for the human queue.
3. **Given** either handoff path has occurred, **When** support staff later review the
   conversation, **Then** the existing internal (private) handoff note is still present, unchanged
   and in addition to the new customer-facing message.

---

### User Story 2 - Support staff can see what happened during an automated conversation (Priority: P2)

A Scout conversation fails or behaves unexpectedly (for example, it falls back to a human hand-off
with only a generic reason). Today, staff investigating have no way to see what Scout actually
asked the model, what the model replied, which tools it called, or why a tool call failed — only a
generic note. This story gives staff a way to inspect that execution history using the same
trace/observability tooling already used elsewhere in the product, when that tooling is configured
for the installation.

**Why this priority**: Important for diagnosing and resolving real incidents (this is what
originally surfaced the problem), but it's an internal support/operations capability rather than
something every customer interaction depends on, so it follows the customer-facing fix.

**Independent Test**: Can be fully tested by configuring the installation's trace/observability
integration, running a Scout conversation that calls at least one tool (including one that fails,
e.g. due to a network error reaching an external system), and confirming the resulting trace shows
the model request/response and each tool call with its arguments and outcome — independent of any
changes to the handoff messaging.

**Acceptance Scenarios**:

1. **Given** the installation has the trace/observability integration configured, **When** a
   customer has a conversation handled by Scout, **Then** a trace is produced covering the main
   model request/response and every tool call made during that conversation, including each
   tool's name, arguments, and result.
2. **Given** the installation has the trace/observability integration configured, **When** a tool
   call fails (for example, an external system call fails due to a network error), **Then** the
   trace captures that failure with enough detail to diagnose it without reproducing the
   conversation.
3. **Given** the installation does **not** have the trace/observability integration configured,
   **When** a customer has a conversation handled by Scout, **Then** the conversation behaves
   exactly as it does today, with no added latency, cost, or side effects.

---

### Edge Cases

- What happens if the model already generated a natural farewell/explanation as part of the same
  response that triggered an explicit handoff? The fixed transfer message is still sent; the
  system does not attempt to salvage or additionally send that generated text (see Assumptions).
- What happens if the trace/observability integration is configured but becomes unreachable or
  errors while a Scout conversation is in progress? The customer-facing conversation must not be
  affected — Scout continues to respond and hand off normally, as observability is a side channel
  and never a precondition for customer-facing behavior.
- What happens when multiple tool calls occur within a single Scout turn? Each tool call is
  captured individually in the trace, not merged into one entry.
- What happens if a handoff is triggered but the conversation is no longer in a state where a
  handoff applies (e.g. already picked up by a human)? Existing conversation-state safeguards
  continue to apply unchanged; no duplicate transfer message is sent.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST send a customer-visible message informing the customer of the transfer
  whenever Scout hands a conversation off to a human, both via the fail-safe path (unrecoverable
  error / quota exhaustion) and via the explicit handoff path.
- **FR-002**: The customer-visible transfer message MUST be sent before the conversation is marked
  as needing human attention, so the customer never has a gap where the handoff has already
  happened but no explanation has been shown.
- **FR-003**: System MUST continue creating the existing internal (private) handoff note in both
  paths, unchanged — the customer-visible message is additive, not a replacement.
- **FR-004**: The transfer message text MUST be a single fixed, translated string (available in
  the product's supported languages), reused identically for every handoff regardless of path or
  underlying reason, and not configurable per Scout instance in this phase.
- **FR-005**: When the installation has a trace/observability integration configured, System MUST
  produce a trace for each Scout conversation turn, capturing the main model request/response and
  every tool call (name, arguments, and result or error).
- **FR-006**: When a tool call made by Scout fails (including failures calling external systems),
  the trace MUST capture that failure with sufficient detail (what was called, with what
  arguments, and what error occurred) for staff to diagnose it without reproducing the
  conversation.
- **FR-007**: When the installation does not have a trace/observability integration configured,
  System MUST behave identically to its current behavior — no added latency, cost, or side effects
  from the observability capability.
- **FR-008**: Observability data MUST be viewable only through the existing external trace
  platform already used elsewhere in the product — this feature does not introduce any new
  internal debugging UI or inspection endpoint.

### Key Entities

- **Assistant Execution Trace**: Represents one Scout turn within a conversation; correlates the
  model request/response with every tool call made during that turn.
- **Tool Call Record**: A single tool invocation within a trace — which tool, what arguments it
  was called with, and its result or error.
- **Handoff Transfer Message**: The fixed, customer-visible message sent to the customer at the
  moment a conversation is handed from Scout to a human, in either handoff path.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of conversations handed off from Scout to a human, through either handoff path,
  show the customer a visible transfer message before the conversation reaches the human queue.
- **SC-002**: When the trace/observability integration is configured, support staff can determine
  the root cause of a Scout failure (e.g. a failed external tool call or an unexpected model
  response) using only the trace data, without asking the customer to reproduce the conversation.
- **SC-003**: Every tool call made by Scout during a conversation appears as an individually
  identifiable entry in the trace platform when the integration is configured.
- **SC-004**: Conversations handled by Scout show no measurable difference in response time or
  behavior whether or not the trace/observability integration is configured.

## Assumptions

- The trace/observability capability reuses the integration and installation-level configuration
  already in place for Captain, the product's other AI assistant, rather than introducing a
  separate observability mechanism.
- The transfer message text is fixed and static for this phase (not customizable per Scout
  instance), matching how the equivalent scenario is already handled elsewhere in the
  product. It is a single, identical message for every handoff — it does not vary by path or by
  the specific reason for the handoff.
- Diagnosing or fixing the specific root cause of any past parsing/response failure that motivated
  this work is out of scope — only the visibility needed to investigate such issues going forward
  is in scope.
- Aggregate usage/product telemetry (e.g. tokens consumed, messages processed) is a separate,
  already-tracked concern and is not part of this feature.
