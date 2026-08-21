# Feature Specification: Scout System Prompt Guardrails Architecture

**Feature Branch**: `049-scout-system-prompt-guardrails`

**Created**: 2026-08-21

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 10/scout/08-system-prompt-guardrails/spec71.md"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Protected Lead Qualification with Anti-Hallucination & Scope Bounding (Priority: P1)

As an account administrator configuring an autonomous Scout agent, I want the agent to operate within strict, unalterable safety guardrails that bound its domain scope and prevent hallucinations, so that customer inquiries are answered exclusively from authorized catalog data, knowledge base articles, and verified conversation context.

**Why this priority**: Without fixed system guardrails, custom operator instructions can inadvertently permit the agent to speculate on unauthorized topics, invent product features, or draw on unverified general training data, damaging business credibility and trust.

**Independent Test**: Can be tested by configuring an agent with custom prompts and sending inquiries about topics outside the product catalog or knowledge base; the agent must decline to answer out-of-scope questions and rely solely on provided context.

**Acceptance Scenarios**:

1. **Given** an active Scout agent with custom business instructions, **When** a lead asks a question about an unrelated topic or unverified product detail, **Then** the agent declines to answer out-of-scope queries and refuses to fabricate information from general training knowledge.
2. **Given** an active Scout agent, **When** a lead asks about a product or service documented in the knowledge base or catalog, **Then** the agent references only the verified context and responds accurately without adding speculative claims.

---

### User Story 2 - Anti-False-Promise & Structured Human Escalation (Priority: P1)

As a sales manager, I want the autonomous agent to never make unfulfillable commitments (such as promising to follow up later, send emails later, or manually check information after the chat) unless immediately executed through an available tool or escalated to a human agent, so that customer expectations are managed reliably.

**Why this priority**: Unfulfilled conversational promises create high friction and lost sales opportunities when leads wait for follow-ups that the automated system has no scheduled mechanism to deliver.

**Independent Test**: Can be tested by asking the agent complex or unsupported requests that cannot be resolved in-session; the agent must either execute a handover or ask clarifying questions without promising asynchronous future actions.

**Acceptance Scenarios**:

1. **Given** a lead requests an action or information that cannot be provided immediately and cannot be performed via available tools, **When** the agent generates a response, **Then** the agent does not promise future follow-ups and instead initiates a transfer to a human agent or asks for immediate missing details.
2. **Given** a lead explicitly requests to speak with a person or agent, **When** the message is processed, **Then** the agent initiates human handover rather than attempting to handle the request autonomously.

---

### User Story 3 - Structured Output Parsing & Fail-Closed Delivery (Priority: P2)

As a system operator, I want the agent's internal reasoning and output formatting to be strictly validated before any message is dispatched to the customer, so that malformed responses, raw code blocks, or internal reasoning tokens are never exposed to external users and parse failures trigger a safe human handover.

**Why this priority**: LLM formatting errors or raw tokens leaking to end users create an unprofessional user experience and risk exposing internal chain-of-thought reasoning or internal metadata.

**Independent Test**: Can be tested by simulating or triggering invalid structured output from the model; the system must prevent message delivery to the customer, record an internal diagnostic trace, and smoothly transition the conversation to human queue.

**Acceptance Scenarios**:

1. **Given** a valid structured response containing internal reasoning and a customer-facing reply, **When** the response is processed, **Then** only the customer-facing message is dispatched to the lead and the internal reasoning is preserved in diagnostic logs.
2. **Given** a response from the model that fails structured validation (such as malformed syntax or empty response text), **When** the response is intercepted, **Then** the system does not deliver any raw text to the customer and instead triggers a fail-safe handover to human agents with a private explanatory note.

---

### User Story 4 - Subordinated Operator Custom Instructions (Priority: P2)

As an account administrator, I want to provide custom domain instructions and persona details for my Scout agent while ensuring that my custom text cannot override, bypass, or weaken core safety guardrails or output formatting requirements.

**Why this priority**: Ensures business flexibility for branding, sales style, and custom qualification questions without compromising baseline system security, truthfulness, and architectural constraints.

**Independent Test**: Can be tested by inserting conflicting operator instructions (e.g., instructing the agent to ignore safety rules or output non-structured text); the system prompt template enforces that guardrails take precedence over custom instructions.

**Acceptance Scenarios**:

1. **Given** an account administrator enters custom qualification questions in the agent settings, **When** the system constructs the prompt, **Then** the custom instructions are included within an explicit additive section subordinate to the core guardrails.
2. **Given** custom instructions that attempt to instruct the agent to disregard boundary rules, **When** interacting with the agent, **Then** the agent adheres to the system guardrails and formatting constraints over the contradictory custom instructions.

---

### Edge Cases

- **Malformed Structured Output**: When the model returns invalid formatting (e.g., truncated text, missing required response fields, or non-parseable syntax), the system fails closed, prevents any customer-facing message, logs the incident, and executes a fail-safe human handoff.
- **Empty Custom Instructions**: When an operator provides no custom business prompt, the system constructs a complete, valid prompt containing the core guardrails, catalog instructions, knowledge base context, and contact data.
- **Direct Prompt Injection / Jailbreak Attempts by Leads**: When a lead attempts to command the agent to ignore previous instructions or adopt an unrestricted persona, the system guardrails instruct the model to maintain its bounded domain and decline compliance.
- **Out of Office Status**: When an inbox is outside business hours, out-of-office notices are integrated alongside guardrails without interfering with response structure or safety boundaries.
- **Tool Execution with Handoff**: When a tool triggers an immediate conversation handover, the system halts outgoing bot replies immediately to avoid sending extraneous automated text after transfer.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST wrap all operator-configured agent instructions within a centralized, non-editable system prompt template containing safety, scope, and formatting guardrails.
- **FR-002**: System MUST enforce domain and identity bounds within the prompt template, explicitly restricting the agent to discussing only authorized product catalog, knowledge base materials, and contact context, and requiring refusal of out-of-scope topics.
- **FR-003**: System MUST enforce anti-hallucination guardrails that mandate answers be derived strictly from provided context or tool responses, explicitly forbidding generation from unsupported general training assumptions.
- **FR-004**: System MUST prohibit the agent from promising asynchronous or future follow-up actions (such as checking later, calling back, or sending follow-up emails) unless executed immediately through an available tool or escalated to a human.
- **FR-005**: System MUST require the agent to initiate a human handover whenever it lacks sufficient context to answer or when the customer requests human assistance.
- **FR-006**: System MUST instruct the AI model to return responses in a structured schema containing an internal reasoning trace and a customer-facing message.
- **FR-007**: System MUST inject operator custom instructions into an isolated section designated as subordinate and additive to the system guardrails.
- **FR-008**: System MUST parse the structured response, extracting the customer-facing message for delivery while capturing internal reasoning strictly in operational logs.
- **FR-009**: System MUST fail closed upon encountering any unparseable, malformed, or incomplete structured response, ensuring zero raw model artifacts reach the customer and automatically initiating a fail-safe human handoff with an internal note.
- **FR-010**: System MUST channel all final message creation, handoff evaluation, and customer dispatch through a single centralized interception pipeline.

### Key Entities

- **Scout Agent Configuration**: The persistent settings representing an autonomous agent, including its custom business instructions, model parameters, and linked communication inboxes.
- **System Prompt Guardrail Template**: The composite instruction structure assembling system-level identity, anti-hallucination rules, tool instructions, contact context, and subordinated operator instructions.
- **Structured Agent Response**: The intermediate response object produced by the model containing an internal reasoning component and a clean customer-facing message component.
- **Fail-Safe Handoff**: The protective fallback mechanism that flags the conversation for human intervention, halts automated bot responses, and posts a private diagnostic note to the inbox timeline.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of autonomous agent interactions execute within the protective guardrail template, completely eliminating unwrapped raw operator prompts.
- **SC-002**: 0% leakage of raw JSON, markdown formatting fences, internal reasoning traces, or unparsed syntax to customer-facing channels.
- **SC-003**: 100% of unparseable or malformed model responses result in automated fail-closed human handoff within the standard response execution cycle.
- **SC-004**: 100% of out-of-scope or unverified inquiries are either declined or escalated to human operators without fabricating unverified claims.
- **SC-005**: All final automated message creation and delivery flows are routed through a single centralized interception point across all conversational scenarios.

## Assumptions

- Autonomous agent tool-calling capabilities (including knowledge base retrieval, opportunity updates, and human handoff) remain active and available during prompt evaluation.
- Internal reasoning traces are captured in application diagnostic logs and do not require new database schema persistence in this phase.
- Existing fail-safe handoff mechanisms (private note creation and conversation status transition) are leveraged directly when structured response parsing fails.
