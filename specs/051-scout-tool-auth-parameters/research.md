# Phase 0 Research: Scout Custom Tool Authentication & Visual Parameter Builder

## Research Overview

This document records the architectural and technical decisions for implementing structured HTTP authentication methods (None, Bearer Token, Basic Auth, API Key) and an intuitive visual parameter builder for Scout custom tools.

---

### Decision 1: Authentication Type Data Model & Credential Packaging

- **Decision**: Add a dedicated `auth_type` string column (default `'none'`) to `ichatr_scout_tools` via an additive database migration. Keep the existing encrypted `auth_headers` text column (managed via ActiveRecord `encrypts :auth_headers`) to store credential payloads in structured JSON format.
  - For `auth_type: 'none'`: `auth_headers` is `{}` or `nil`.
  - For `auth_type: 'bearer'`: `auth_headers` stores `{"token": "<secret_token>"}` (or `{"Authorization": "Bearer <secret_token>"}`).
  - For `auth_type: 'basic'`: `auth_headers` stores `{"username": "<user>", "password": "<pass>"}`.
  - For `auth_type: 'api_key'`: `auth_headers` stores `{"header_name": "X-API-Key", "header_value": "<secret_value>"}`.
- **Rationale**:
  - A dedicated `auth_type` column allows direct querying and explicit UI selection without parsing encrypted payload strings.
  - Encrypting `auth_headers` ensures all sensitive tokens, passwords, and API keys remain encrypted at rest.
  - Structured storage allows the backend `HttpRequestExecutor` to deterministically construct exact standard HTTP headers at runtime:
    - Bearer: `Authorization: Bearer <token>`
    - Basic: `Authorization: Basic <base64(username:password)>`
    - API Key: `<header_name>: <header_value>`
- **Alternatives Considered**:
  - *Storing auth_type inside the encrypted auth_headers JSON*: Rejected because determining the authentication method would require decrypting the payload every time tools are listed.
  - *Creating separate tables for credentials*: Rejected as over-engineering for single tool configurations; `auth_headers` encryption already satisfies security requirements.

---

### Decision 2: Secret Masking & Safe Update Strategy

- **Decision**:
  - When returning `ScoutTool` records in API responses (`GET /api/v1/accounts/:account_id/scout_tools`), mask sensitive credential fields (e.g. `{"token": "••••••••"}`, `{"username": "admin", "password": "••••••••"}`, `{"header_name": "X-API-Key", "header_value": "••••••••"}`).
  - When processing `update` requests in `ScoutToolsController` and `ScoutTool`, if the submitted credential value equals `"••••••••"` or is empty while `auth_type` remains unchanged, preserve the existing encrypted credential from the database.
- **Rationale**:
  - Prevents exposing raw API tokens or passwords in browser developer tools or frontend JSON responses.
  - Allows users to edit non-auth tool fields (such as descriptions or parameter definitions) without having to re-type existing API keys or passwords.
- **Alternatives Considered**:
  - *Returning plain text tokens to the frontend*: Rejected due to security risks in multi-agent and shared screen environments.
  - *Requiring re-entry of secrets on every edit*: Rejected as poor user experience for routine maintenance.

---

### Decision 3: Visual Parameter Builder & JSON Schema Bidirectional Mapping

- **Decision**: Represent tool parameters in the UI as a list of structured objects (`[{ name, type, description, required }]`), compiling to standard JSON Schema on save/test, and parsing back from JSON Schema when editing existing tools.
  - **Compilation to JSON Schema**:
    ```json
    {
      "type": "object",
      "properties": {
        "order_id": {
          "type": "string",
          "description": "The unique order identifier"
        },
        "item_count": {
          "type": "integer",
          "description": "Number of items to fetch"
        }
      },
      "required": ["order_id"]
    }
    ```
  - **Decompilation from JSON Schema**:
    When opening an existing tool, iterate over `parameter_schema.properties` keys, extracting `type`, `description`, and matching key existence in the `parameter_schema.required` array.
- **Rationale**:
  - Removes the requirement for users to know or write JSON Schema syntax.
  - Maintains 100% compatibility with LLM tool calling engines (OpenAI function calling, Anthropic tool calling, Gemini tool declarations) which consume standard JSON Schema `properties` and `required` arrays.
  - Supports types: `String`, `Number`, `Integer`, `Boolean`, `Array`, `Object`.
- **Alternatives Considered**:
  - *Keeping a raw JSON toggle*: Rejected per clarification — replacing raw JSON with the visual builder provides a consistent and foolproof UX.

---

### Decision 4: Parameter Name Validation & Identifier Safety

- **Decision**: Strictly validate parameter names against the identifier regex `/^[a-zA-Z_][a-zA-Z0-9_]*$/`. Enforce non-empty and unique parameter names. If a user enters invalid characters (such as spaces or hyphens), display an inline validation message and prevent saving.
- **Rationale**:
  - AI function calling schemas require parameter keys to be valid JSON / programming language identifier names.
  - Strict validation gives immediate feedback to the operator and avoids subtle bugs when the AI generates function call arguments.
- **Alternatives Considered**:
  - *Auto-converting on input (snake_casing)*: Evaluated and rejected in clarification session in favor of explicit user feedback (Option B).

---

### Decision 5: HttpRequestExecutor Integration for All Auth Types

- **Decision**: Update `Custom::Scout::Tools::HttpRequestExecutor` to accept `auth_type` alongside `auth_headers`. Implement standard header builders:
  - `build_bearer_header(token)` -> `{'Authorization' => "Bearer #{token}"}`
  - `build_basic_header(user, pass)` -> `{'Authorization' => "Basic #{Base64.strict_encode64("#{user}:#{pass}")}"}`
  - `build_api_key_header(name, val)` -> `{name => val}`
- **Rationale**:
  - Centralizes header formatting in the shared executor used by both live AI executions (`CallCustomApi`) and modal test requests (`ScoutToolsController#test`).
  - Base64 encoding for Basic Auth uses `Base64.strict_encode64` to prevent newline injection.
- **Alternatives Considered**:
  - *Formatting headers in the frontend*: Rejected because sensitive credentials must not be assembled client-side, and backend live tool calls need to generate headers independently from saved models.
