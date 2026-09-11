# Feature Specification: Scout External Tool Testing & Response Shaping

**Feature Branch**: `050-scout-tool-testing-response`

**Created**: 2026-08-21

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 10/scout/13-tool-testing-and-response-shaping/spec73.md — enable draft testing of external tools directly from the management modal with sample payloads, dynamic URL path parameters with strict validation, automatic query parameter handling for GET requests, and configurable response templates to shape and filter external tool outputs before returning them to the agent."

## Clarifications

### Session 2026-08-21

- Q: How should array or object values in unconsumed GET payload parameters be serialized into the query string? → A: JSON-stringify the value (e.g. `?filters=%7B%22a%22%3A1%7D`)
- Q: What character limit should the raw response body preview be truncated to (both in the test-endpoint payload and the UI display)? → A: 500 characters

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Test External Tool Configurations on Drafts Directly in UI (Priority: P1)

An operator configuring an external tool (REST API or webhook) needs to verify whether the target URL, HTTP method, authentication headers, and response structure function as intended before saving and deploying the tool to live AI agent conversations. The operator inputs a sample test payload in the configuration modal, triggers a test call, and immediately views the resulting HTTP status, raw response preview, and shaped response preview.

**Why this priority**: Without real-time draft testing, operators can only discover integration errors (such as invalid credentials, broken endpoints, or bad payload structures) during live customer conversations, degrading customer experience and creating high operational friction.

**Independent Test**: Can be fully tested by opening the external tool configuration modal, entering unsaved endpoint details with a sample payload, clicking "Test", and verifying that the live API response status, raw body, and shaped preview are accurately displayed in the modal without requiring the tool to be saved first.

**Acceptance Scenarios**:

1. **Given** an operator is creating or editing an external tool in the configuration modal, **When** they provide endpoint parameters and a sample JSON payload and click the test action, **Then** the system sends a live request using the draft configuration without persisting the tool.
2. **Given** a draft test request completes successfully, **When** the response is received, **Then** the modal displays the HTTP status code, the raw response body (truncated to 500 characters if large), and the transformed response preview.
3. **Given** a draft test request fails (due to network timeout, DNS resolution failure, or remote 4xx/5xx HTTP status), **When** the result is returned, **Then** the modal displays the failure status and error details cleanly without crashing the interface or throwing unhandled errors.
4. **Given** an operator tests a draft tool with an incomplete or exploratory payload that does not conform to the defined parameter schema, **When** the test is executed, **Then** the test executes against the remote endpoint without blocking on schema validation, allowing exploratory testing.

---

### User Story 2 - Dynamic URL Path Parameters and Query String Handling (Priority: P1)

An operator configures an external API endpoint that requires dynamic URL path parameters (e.g., `https://api.example.com/orders/{{order_id}}/status`) or URL query string parameters for `GET` requests. When the AI agent or operator executes the tool with a parameter payload, the system dynamically populates the path placeholders and attaches any remaining parameters as query string parameters for `GET` calls.

**Why this priority**: Many modern REST APIs require path parameters or query parameters (especially search and retrieval endpoints). Previously, path variables were not supported, and `GET` requests discarded payload parameters entirely.

**Independent Test**: Can be fully tested by configuring a `GET` tool with both path placeholders and additional payload parameters, triggering the call, and confirming that the target endpoint receives the substituted URL path along with the remaining parameters appended as a standard query string.

**Acceptance Scenarios**:

1. **Given** an endpoint URL contains dynamic path parameter placeholders (e.g., `{{item_id}}`), **When** the tool is executed with a payload containing matching keys, **Then** the placeholders are replaced with the corresponding values before the HTTP request is dispatched.
2. **Given** an endpoint URL contains dynamic path parameter placeholders, **When** the tool is executed with a payload missing any of the required path variables, **Then** the request is halted before dispatch and a strict template resolution error is returned.
3. **Given** a `GET` request contains payload parameters that are not consumed by the URL path template, **When** the request is dispatched, **Then** the unconsumed parameters are automatically serialized and appended to the URL as query string parameters (`?key=value`).
4. **Given** a non-`GET` request (e.g., `POST`, `PUT`, `PATCH`), **When** the request is dispatched, **Then** the parameters not consumed by the URL path template are serialized as the JSON request body.

---

### User Story 3 - Response Shaping and Filtering for Agent Context (Priority: P2)

External APIs often return verbose JSON objects containing hundreds of irrelevant fields, metadata, or internal identifiers. An operator configures an optional response template for an external tool so that only the essential data fields (e.g., status, tracking code, price) are extracted and formatted before being handed to the AI agent.

**Why this priority**: Filtering and shaping API responses minimizes LLM context window consumption, lowers token costs, prevents hallucinations from extraneous payload noise, and improves response latency.

**Independent Test**: Can be fully tested by configuring an external tool with a response template (e.g., extracting specific fields from a large response), executing the tool with live data, and confirming that the agent receives only the transformed output string rather than the full raw JSON payload.

**Acceptance Scenarios**:

1. **Given** an external tool has a configured response template, **When** the external API returns a JSON response, **Then** the system renders the response template using the parsed response data (accessible via standard response aliases) and delivers the transformed text to the calling agent.
2. **Given** an external tool does not have a response template configured (or the field is empty), **When** the external API returns a response, **Then** the default behavior is preserved (returning parsed JSON or raw response body directly).
3. **Given** a response template references a field that is absent from the API response under strict evaluation, **When** the template fails to render, **Then** a structured formatting error is returned rather than passing broken or silently empty strings.
4. **Given** an operator tests a tool with a response template in the configuration modal, **When** the test finishes, **Then** the operator sees both the raw response and the rendered response preview side-by-side or stacked to facilitate iterative template authoring.

---

### User Story 4 - Consistent Form Field Persistence & UI Refinement (Priority: P2)

An operator creates or modifies an external tool configuration through the settings UI. The endpoint URL and custom authentication headers entered by the operator are accurately mapped and persisted in the database, and the modal provides dedicated inputs for the response template and the test playground.

**Why this priority**: Resolves form payload mapping inconsistencies ensuring configuration inputs are reliably saved, while providing a cohesive, accessible management interface.

**Independent Test**: Can be fully tested by creating and updating an external tool with endpoint URL, custom headers, and response template in the web UI, reloading the settings page, and confirming that all values persist and display correctly.

**Acceptance Scenarios**:

1. **Given** an operator enters an endpoint URL and authentication headers in the tool modal, **When** the operator saves the configuration, **Then** the endpoint URL and headers are saved and persist across subsequent edits.
2. **Given** an operator opens an existing external tool for editing, **When** the modal loads, **Then** the existing endpoint URL, authentication headers, and response template are prefilled in their respective fields.

---

### Edge Cases

- **Missing URL Path Parameters in Payload**: If an endpoint URL contains `{{id}}` and the provided payload does not contain `id`, the HTTP request must never be sent with an empty or literal segment (e.g. `/orders//status` or `/orders/{{id}}/status`). Execution must fail immediately with a descriptive template resolution error.
- **Empty or Non-JSON Response Body from External API**: If an external API returns an empty body (e.g., HTTP 204 No Content) or non-JSON body when a response template is configured, the system must handle the absence of a JSON object gracefully and return an appropriate formatting failure or raw status rather than crashing.
- **Special Characters and Escaping in Query Strings**: Unconsumed payload parameters converted into query string parameters for `GET` requests must be properly URL-encoded (e.g., spaces, punctuation, non-ASCII characters). Array or object values must be JSON-stringified before URL-encoding (e.g., `?filters=%7B%22a%22%3A1%7D`), since query strings only carry scalar text values.
- **Large Test Response Bodies**: The raw response body (in both the test-endpoint result and the UI test panel preview) must be truncated to 500 characters, with a visual indicator in the UI when truncation occurs, to avoid locking or degrading the interface.
- **Network Failures and Timeouts during UI Testing**: If the remote host is unreachable, connection is refused, or read timeout occurs during a manual test in the modal, the test runner must capture the error and display a clear, human-readable error message in the test result panel.
- **Schema Validation Separation**: When an AI agent executes a tool during a live conversation, parameter schema validation must strictly reject invalid payloads before dispatching network requests. When an operator runs an ad-hoc test from the modal, schema validation is bypassed so operators can inspect the remote API's response to custom or partial payloads.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow endpoint URLs to contain dynamic path placeholders (e.g., `{{variable_name}}`) that are populated at execution time from the provided payload.
- **FR-002**: System MUST enforce strict variable evaluation when resolving URL path templates; if any referenced placeholder is missing from the execution payload, the system MUST abort the request before network dispatch and return a structured template error.
- **FR-003**: System MUST identify and remove payload keys consumed by the URL path template from the remaining payload parameters.
- **FR-004**: For `GET` requests, system MUST automatically serialize all remaining (unconsumed) payload parameters into standard URL-encoded query string parameters and append them to the request URL. Scalar values are URL-encoded directly; array or object values are JSON-stringified before URL-encoding.
- **FR-005**: For non-`GET` requests (`POST`, `PUT`, `PATCH`), system MUST serialize all remaining (unconsumed) payload parameters as the JSON request body.
- **FR-006**: System MUST support an optional response template configuration on external tools to format and filter the external API response before delivering it to the AI agent.
- **FR-007**: When a response template is configured, system MUST render the template using the parsed JSON response (providing standard aliases `response` and `r`) under strict variable evaluation.
- **FR-008**: When a response template is empty or not configured, system MUST preserve default response output behavior (returning parsed JSON or raw response body).
- **FR-009**: System MUST provide a dedicated testing endpoint that allows authenticated operators to execute an ad-hoc request against an external endpoint using draft configuration attributes (URL, method, headers, response template, and a sample payload) without requiring the tool to be persisted first.
- **FR-010**: System MUST bypass parameter schema validation for ad-hoc draft test requests while maintaining strict parameter schema validation for live agent tool executions.
- **FR-011**: System MUST capture all network errors, timeouts, and non-2xx HTTP responses during draft testing and return them as structured test results containing the HTTP status and message without throwing unhandled exceptions.
- **FR-012**: The tool management modal in the web interface MUST provide an interactive testing section with a sample JSON payload editor, a trigger action, and a response display showing the HTTP status, raw response preview (truncated to 500 characters), and transformed response preview.
- **FR-013**: The tool management modal MUST accurately map and persist the endpoint URL, authentication headers, parameter schema, and response template across both create and edit operations.

### Key Entities

- **External Tool Configuration (`ScoutTool`)**: Represents the persistent configuration of an external API integration, including tool name, description, endpoint URL (with optional path placeholders), HTTP method, authentication headers, parameter schema, optional response template, and enabled state.
- **Tool Test Request**: A transient data structure representing an operator-initiated draft test containing the candidate endpoint URL, method, headers, response template, and sample payload.
- **Tool Execution Result**: The structured outcome of a tool execution containing HTTP status code, raw response body, transformed response body (if shaped), and any error diagnostics.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can test 100% of external tool configurations (including dynamic URLs, headers, and response templates) directly in the management modal before saving, receiving immediate visual feedback on status and output.
- **SC-002**: 100% of requests with dynamic URL placeholders that lack required variables are prevented from reaching the external network and return immediate template validation errors.
- **SC-003**: 100% of payload parameters provided to `GET` requests that are not consumed by URL path placeholders are transmitted as URL query parameters.
- **SC-004**: External tool responses shaped by a configured response template contain only the fields explicitly referenced in the template, verified by automated specs asserting the rendered output excludes fields present in the raw response but absent from the template.
- **SC-005**: 100% of tool configuration updates (endpoint URL, authentication headers, and response template) persist accurately without data loss.

## Assumptions

- Dynamic URL path and response template rendering uses strict variable evaluation semantics consistent with the platform's templating standards.
- Response templates operate on valid JSON responses; if an external endpoint returns a non-JSON body or binary data, response template rendering returns an informative error.
- Ad-hoc testing is subject to the same standard connection timeouts (2 seconds) and read timeouts (20 seconds) as live agent tool executions to prevent hanging requests.
- Live agent tool execution continues to strictly validate the payload against `parameters_schema` prior to network dispatch.
- Authentication headers in draft test requests are handled securely and not persisted or logged in plain text.
