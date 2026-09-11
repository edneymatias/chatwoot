# Feature Specification: Scout External REST/Webhook Tool

**Feature Branch**: `045-scout-external-webhook-tool`

**Created**: 2026-08-19

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 9/scout/04-external-rest-webhook-tool/spec65.md — let a Scout call arbitrary externally-configured REST APIs/webhooks (ERP stock lookups, custom integrations) as an LLM tool, without any code change per integration, via a call_custom_api(tool_id, payload) native tool that resolves a ScoutTool, validates the payload, executes the call, and returns a structured result or structured error to the LLM."

## Clarifications

### Session 2026-08-19

- Q: What should the maximum wait time (timeout) for an external call be, and how should very large response bodies be handled? → A: Reuse the same limits Copilot's existing custom HTTP tool already uses in production (`enterprise/lib/captain/tools/http_tool.rb`, routed through `SafeFetch`): 2-second connection timeout, 20-second read timeout, and a 1 MB response size cap.
- Q: Should failed/succeeded external tool calls be logged for operator troubleshooting? → A: Log failures via the standard application logger only, matching the pattern Copilot's existing custom HTTP tool already uses (`Rails.logger.error` on failure) — no new persisted record or UI.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Scout answers a customer using a live external system (Priority: P1)

A business configures an external REST API (e.g. an ERP stock lookup or a custom webhook) as a callable tool for their Scout, without anyone writing code. During a live conversation, the Scout recognizes it needs that external data (e.g. "is this product in stock?"), calls the configured tool with the right parameters, and uses the returned data to answer the customer in the same turn.

**Why this priority**: This is the entire value proposition of the feature — a Scout that can only talk about what's in its prompt is far less useful than one that can pull live business data. Without this, the feature doesn't exist.

**Independent Test**: Can be fully tested by configuring one external tool (pointing at a test endpoint), starting a conversation that requires that data, and confirming the Scout's reply reflects the live response instead of a static/hallucinated answer.

**Acceptance Scenarios**:

1. **Given** a business has configured an enabled external tool with a valid endpoint, method, auth headers, and parameter schema, **When** the Scout determines mid-conversation that it needs that tool, **Then** it calls the external endpoint with a payload matching the schema and receives the response back as part of the same conversation turn.
2. **Given** the external call succeeds, **When** the Scout receives the response, **Then** it incorporates that data into its reply to the customer without requiring any additional code changes or redeploys for that specific integration.
3. **Given** two different accounts each have a Scout with a similarly-named external tool, **When** one account's Scout calls a tool, **Then** it can only reach tools configured for its own account, never another account's tool.

---

### User Story 2 - Scout recovers gracefully when the external system misbehaves (Priority: P1)

An external system a Scout depends on can be slow, down, or receive a request that doesn't match what it expects. When that happens, the Scout must recognize the failure and keep the conversation going — telling the customer something went wrong or trying again — rather than the conversation silently dying.

**Why this priority**: External systems configured by end users are inherently unreliable (any URL, any uptime). Without graceful failure handling, one bad integration or one slow API would break every conversation that touches it, undermining trust in the whole Scout feature.

**Independent Test**: Can be fully tested by configuring a tool whose parameter schema the Scout's payload fails to satisfy, and separately a tool pointed at an endpoint that never responds, then confirming in both cases the conversation continues and the Scout can report the failure or try again instead of the turn crashing.

**Acceptance Scenarios**:

1. **Given** an external tool has a defined parameter schema, **When** the Scout calls it with a payload that doesn't satisfy that schema, **Then** the external endpoint is never contacted and the Scout receives a clear failure result it can act on (e.g. inform the customer, or retry with corrected parameters).
2. **Given** an external tool's endpoint does not respond within the allowed waiting time, **When** the Scout calls it, **Then** the Scout receives a clear failure result instead of the conversation turn erroring out.
3. **Given** either failure above occurs, **When** the conversation continues, **Then** the customer receives some response from the Scout (an apology, a request to try again, or a handover) rather than no response at all.

---

### User Story 3 - Disabled integrations are never reachable (Priority: P2)

A business can turn an external tool off (e.g. because the underlying vendor system is under maintenance, or the integration was misconfigured) without deleting its configuration. Once turned off, the Scout must behave as if that tool doesn't exist.

**Why this priority**: Businesses need a safe, reversible kill switch for integrations that misbehave in production, without losing the configuration (endpoint, headers, schema) they already set up.

**Independent Test**: Can be fully tested by disabling a previously-working external tool, starting a new conversation that would previously have triggered it, and confirming the Scout never attempts to call it (and cannot be tricked into calling it) while it stays disabled.

**Acceptance Scenarios**:

1. **Given** an external tool is disabled, **When** a Scout that could otherwise use it is having a conversation, **Then** that tool is not among the tools the Scout is aware it can call.
2. **Given** an external tool is disabled, **When** a Scout attempts to call it anyway (e.g. from stale context), **Then** the call is refused with a clear failure result rather than executed.
3. **Given** a disabled tool is re-enabled, **When** the next conversation turn evaluates available tools, **Then** it becomes callable again with its original configuration intact.

---

### Edge Cases

- What happens when a Scout calls an external tool id that doesn't exist at all (never configured, or belongs to a different account)? System must return a clear failure result to the LLM, not raise an unhandled error.
- What happens when the external endpoint returns a non-success HTTP status (4xx/5xx) but responds within the timeout? The response (including the failure status) must be surfaced to the Scout as a result it can reason about, not silently discarded.
- What happens when the external endpoint returns a response body that isn't valid JSON, or is unexpectedly large? The Scout must still receive a usable result rather than the turn crashing; a response exceeding the 1 MB size cap is treated the same as any other call failure (structured failure result, not a crash).
- What happens if the same external tool is called multiple times in one conversation turn? Each call is independent and must succeed or fail on its own.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a native LLM-callable tool that, given a tool identifier and a payload, resolves the matching external tool configuration and executes the corresponding external HTTP call.
- **FR-002**: System MUST only resolve external tool configurations that belong to the same account as the calling Scout — a Scout MUST NOT be able to reach another account's external tool configuration under any circumstance.
- **FR-003**: System MUST build the outgoing request using the resolved configuration's endpoint, HTTP method, and stored authentication headers (decrypted at call time).
- **FR-004**: System MUST validate the LLM-supplied payload against the resolved configuration's parameter schema before contacting the external endpoint.
- **FR-005**: System MUST NOT contact the external endpoint if payload validation fails, and MUST instead return a structured failure result to the LLM describing that the payload was invalid.
- **FR-006**: System MUST enforce a maximum wait time on every external call — a 2-second connection timeout and a 20-second read timeout, matching Copilot's existing custom HTTP tool — and MUST return a structured failure result to the LLM if that time is exceeded, without raising an error that interrupts the conversation turn.
- **FR-006a**: System MUST cap the accepted external response body at 1 MB, matching Copilot's existing custom HTTP tool, and MUST treat a response exceeding that cap as a call failure with a structured failure result rather than crashing or truncating silently.
- **FR-007**: System MUST return the external endpoint's response back to the LLM as the tool's output within the same conversation turn on success.
- **FR-008**: System MUST exclude disabled external tool configurations from the set of tools offered to the LLM for a given Scout — i.e. from whatever catalog of callable `tool_id`s the LLM is given (name, id, expected payload shape) to decide which one to invoke, not merely from execution.
- **FR-009**: System MUST refuse to execute a call against a disabled or nonexistent external tool configuration even if requested, returning a structured failure result instead of executing the call.
- **FR-010**: System MUST NOT crash or abort the current conversation turn as a result of any external call failure (validation failure, timeout, network error, non-success HTTP status, or malformed response).
- **FR-011**: System MUST log external call failures via the application's standard logger (matching Copilot's existing custom HTTP tool pattern), so an operator can diagnose a misconfigured integration from server logs without needing a dedicated UI or persisted record.

### Key Entities *(include if feature involves data)*

- **External Tool Configuration** (existing `ScoutTool` entity): represents one externally-configured REST API/webhook a Scout can call — carries the endpoint, HTTP method, authentication headers, an expected parameter shape, and an enabled/disabled state. Already modeled; this feature is the execution path that uses it, not new data.
- **Tool Call Result**: the structured outcome of one invocation attempt — either the external response data (on success) or a structured failure description (on invalid payload, timeout, or other error) — handed back to the LLM within the conversation turn.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A business can make a new external system callable by their Scout entirely through configuration, with zero code changes or deployments per integration.
- **SC-002**: 100% of external calls that fail (invalid payload, timeout, error response, malformed response) result in the conversation turn continuing normally rather than crashing or hanging.
- **SC-003**: A disabled external tool is never executed during a live conversation, verified across repeated attempts.
- **SC-004**: When an external system is slow or unresponsive, the Scout still responds to the customer within a bounded, predictable wait time (at most a 2-second connect attempt plus a 20-second read wait per call) rather than the conversation stalling indefinitely.

## Assumptions

- The external tool configuration entity, its encrypted authentication headers, and the underlying Scout tool-calling loop already exist (delivered in prior phases of this initiative) — this feature adds the execution path, not the data model or the loop itself.
- The catalog of callable `tool_id`s (name, id, expected payload shape) that the LLM sees is generated by this feature itself, at call time, from the calling account's enabled external tool configurations — there is no separate, pre-existing discovery mechanism to reuse.
- Timeout and response-size limits reuse Copilot's existing custom HTTP tool config (`SafeFetch` defaults: 2s connect / 20s read / 1 MB response cap) rather than introducing new values, for consistency across the codebase's external-call tooling; these can be tuned later without changing this spec's intent.
- Retrying a failed external call is a decision the Scout/LLM makes conversationally (e.g. correcting parameters and calling again) — this feature does not add automatic background retries, queues, or circuit breakers.
- Webhook signature verification and other endpoint-side authentication schemes beyond static auth headers are out of scope unless a concrete integration proves it necessary (per source doc scope).
- No dedicated UI for creating/editing external tool configurations is in scope for this feature — configuration management is a separate, later phase.
- Operator visibility into failed calls is limited to standard application logs; a queryable/persisted call-history record or dedicated troubleshooting UI is out of scope for this phase.
