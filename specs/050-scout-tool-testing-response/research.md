# Phase 0 Research: Scout External Tool Testing & Response Shaping

## Research Overview

This document analyzes technical decisions, integration patterns, and architectural choices for implementing draft testing of external tools, dynamic URL path parameters with strict Liquid evaluation, automatic query parameter handling for `GET` requests, and configurable response templates for response shaping.

---

### Decision 1: URL Path Template Resolution & Variable Extraction

- **Decision**: Use `Liquid::Template` with `error_mode: :strict` and `render(payload, strict_variables: true, strict_filters: true)` for URL template resolution. Extract referenced path placeholder keys via regex matching (`/\{\{\s*([a-zA-Z0-9_]+)/`) so that consumed keys are systematically excluded from the remaining payload.
- **Rationale**:
  - Liquid is already an established repo dependency and matches the strict templating pattern used in enterprise tool components.
  - Strict mode ensures that any missing path parameter immediately raises `Liquid::UndefinedVariable` (or `Liquid::SyntaxError`), halting the request before network dispatch and returning a clear template error rather than sending broken URLs with empty segments (e.g. `/orders//status`).
  - Extracting root variable keys via `/\{\{\s*([a-zA-Z0-9_]+)/` identifies which payload attributes were consumed by the URL path, allowing the remaining parameters to be passed to query strings (for `GET`) or request bodies (for non-`GET`).
- **Alternatives Considered**:
  - *Custom regex replacement (e.g. `gsub(/\{\{(.+?)\}\}/)`)*: Rejected because it does not support standard Liquid filters or strict variable evaluation semantics, leading to inconsistent error handling.
  - *Extracting AST nodes from `liquid_template.root.nodelist`*: Liquid's internal AST node structures vary between Liquid versions, whereas scanning root identifiers in URL placeholders with regex is fast, robust, and deterministic.

---

### Decision 2: Query String Parameter Serialization for GET Requests

- **Decision**: For `GET` requests, serialize unconsumed payload keys into URL query parameters. If a parameter value is a Hash or an Array, serialize it as JSON before URL-encoding (e.g. `?filters=%7B%22a%22%3A1%7D`). Scalar values (string, integer, float, boolean) are converted to strings and URL-encoded.
- **Rationale**:
  - Resolves the existing bug where `GET` request payloads were completely discarded.
  - Query strings natively carry scalar values. Arrays and nested objects from LLM tool calls must be JSON-stringified before URL-encoding to preserve structure for external REST APIs without causing ambiguous query format issues.
  - Handles URLs that already contain query strings by checking for existing `?` and appending with `&`.
- **Alternatives Considered**:
  - *Rack `build_nested_query` (PHP/Rails style `filters[a]=1`)*: Rejected because external APIs commonly expect JSON-encoded query parameter strings for complex objects, as specified in the clarification session.
  - *Disallowing objects/arrays in GET payloads*: Rejected because LLMs may supply search filters or query objects that external REST APIs accept as encoded JSON strings.

---

### Decision 3: Shared `HttpRequestExecutor` Service

- **Decision**: Extract all HTTP request assembly, URL templating, query serialization, header construction, SafeFetch dispatch, and response formatting into a plain service class: `Custom::Scout::Tools::HttpRequestExecutor`. Both `Custom::Scout::Tools::CallCustomApi` (agent execution) and `Api::V1::Accounts::ScoutToolsController#test` (interactive test endpoint) will invoke this shared executor.
- **Rationale**:
  - Eliminates code duplication between live agent execution and manual modal testing.
  - Decouples HTTP dispatch logic from `RubyLLM::Tool` and conversation context.
  - Enables schema validation to remain strictly enforced during agent execution (`CallCustomApi`) while allowing exploratory, partial payloads during draft modal testing (`ScoutToolsController#test`).
- **Alternatives Considered**:
  - *Calling `CallCustomApi` directly in test endpoint*: Rejected because `CallCustomApi` requires an instantiated `Scout` agent and `Conversation`, and enforces strict JSON schema validation that prevents draft exploratory testing.
  - *Separate HTTP execution logic in controller and tool*: Rejected because behavior between testing and live execution would diverge, creating hard-to-debug discrepancies.

---

### Decision 4: Response Formatting & Template Shaping

- **Decision**: Add an optional `response_template` text column to `ichatr_scout_tools`. When configured, render the template with `Liquid::Template` in strict mode using context `{ 'response' => parsed_json, 'r' => parsed_json }`. If `response_template` is blank or nil, preserve the default behavior of returning parsed JSON (if valid JSON) or the raw string body.
- **Rationale**:
  - Providing both `response` and `r` aliases gives operators convenience when accessing nested fields (e.g., `{{ r.order.status }}` or `{{ response.tracking_number }}`).
  - Strict mode ensures that missing fields or malformed Liquid syntax fail loudly with a descriptive error message rather than silently emitting blank strings to the LLM agent.
  - If external APIs return non-JSON text or empty responses (204 No Content), the executor handles it gracefully without unhandled exceptions.
- **Alternatives Considered**:
  - *JQ expressions*: Rejected because Liquid is already native to the codebase and familiar to operators.
  - *Non-strict Liquid mode*: Rejected because silently omitting undefined fields causes LLMs to receive empty context without understanding why.

---

### Decision 5: Test Endpoint Architecture & Error Handling

- **Decision**: Add `POST /api/v1/accounts/:account_id/scout_tools/test` handled by `Api::V1::Accounts::ScoutToolsController#test`. The endpoint accepts draft tool attributes (`endpoint_url`, `http_method`, `auth_headers`, `response_template`, and sample `payload`). It captures all network timeouts (`SafeFetch::FetchError`), file size limits (`SafeFetch::FileTooLargeError`), HTTP errors (`SafeFetch::HttpError`), and template errors, returning HTTP 200 with a structured JSON payload:
  ```json
  {
    "success": true,
    "status": 200,
    "raw_body": "{\"order_id\": 123, \"status\": \"shipped\"}",
    "formatted_response": "Order #123 is shipped.",
    "error": null
  }
  ```
  The raw response body is truncated to 500 characters in the test result payload to prevent oversized responses from degrading browser performance.
- **Rationale**:
  - Allows operators to test without saving or persisting the tool first.
  - Returning HTTP 200 with error diagnostics inside the payload allows the frontend to display remote 4xx/5xx statuses or network errors gracefully in the test UI panel without triggering global API error toasts or crashing the modal.
- **Alternatives Considered**:
  - *Persisting before testing*: Rejected because operators frequently need to test incomplete or exploratory configurations before committing them to the database.
  - *Throwing 422 on remote API failures*: Rejected because remote API errors (e.g. 404 from target service) are expected test outcomes that the operator needs to see cleanly displayed in the test panel.

---

### Decision 6: Frontend Form & Test Playground in `ScoutToolModal.vue`

- **Decision**: Update `ScoutToolModal.vue` to fix parameter names (`endpoint_url`, `auth_headers`), add the `response_template` textarea, and incorporate an interactive test playground section.
  - Fix form binding: `url` → `endpoint_url`, `headers` → `auth_headers`.
  - Add `response_template` textarea with monospace font styling.
  - Add test section containing:
    - Sample payload JSON textarea (prefilled with `{}` or empty template).
    - "Test" button (`variant="faded" color="slate" icon="i-lucide-play"` with loading state).
    - Test result display panel showing:
      - HTTP status badge with color coding (green for 2xx, red/amber for 4xx/5xx/network errors).
      - Raw response preview (truncated to 500 characters, with visual indicator if truncated).
      - Shaped response preview (when `response_template` is provided).
      - Template or network error diagnostics banner if execution failed.
  - Add synchronous English (`en.json`) and Portuguese (`pt_BR.json`) localization strings.
- **Rationale**:
  - Resolves the critical field-mapping bug where URLs and headers were lost on save.
  - Enables instant visual feedback during tool creation and editing.
  - Side-by-side or stacked raw and shaped previews enable operators to iterate rapidly on their Liquid response templates.
