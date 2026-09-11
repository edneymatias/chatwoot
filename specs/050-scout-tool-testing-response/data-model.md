# Data Model: Scout External Tool Testing & Response Shaping

## Entities and Schemas

### 1. ScoutTool (`ScoutTool`, table: `ichatr_scout_tools`)

Persistent model representing an external REST API or webhook tool configured for an account.

| Column | Type | Nullable | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `id` | `bigint` | No | Auto | Primary key |
| `account_id` | `bigint` | No | - | Foreign key referencing `accounts.id` (ON DELETE CASCADE) |
| `name` | `string` | No | - | Machine-readable identifier for LLM invocation |
| `description` | `text` | No | - | Plain-text explanation of tool purpose and usage for the agent |
| `endpoint_url` | `text` | No | - | Target URL, optionally containing dynamic Liquid path templates (e.g. `https://api.example.com/orders/{{id}}`) |
| `http_method` | `string` | No | `'POST'` | HTTP verb (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`) |
| `auth_headers` | `text` | Yes | `nil` | Encrypted authentication headers (JSON, YAML, or raw Authorization string) |
| `parameter_schema` | `jsonb` | Yes | `{}` | JSON Schema defining the expected parameter types and required fields for LLM execution |
| `enabled` | `boolean` | No | `true` | Active toggle controlling whether the tool is exposed in the agent catalog |
| `response_template` | `text` | Yes | `nil` | **[NEW]** Liquid template for response shaping and filtering before passing output to LLM |
| `created_at` | `datetime` | No | Auto | Record creation timestamp |
| `updated_at` | `datetime` | No | Auto | Record last updated timestamp |

#### Indexes & Constraints
- Index: `index_ichatr_scout_tools_on_account_id` on `(account_id)`
- Foreign Key: `fk_rails_...` referencing `accounts(id)` ON DELETE CASCADE
- Active Record Encryption: `encrypts :auth_headers`

#### Validations
- `validates :account_id, :name, :description, :endpoint_url, :http_method, presence: true`

---

### 2. ToolTestRequest (Transient Data Structure)

In-memory data representation used by the `POST /api/v1/accounts/:account_id/scout_tools/test` controller action.

| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `endpoint_url` | `String` | Yes | Candidate URL with optional Liquid placeholders |
| `http_method` | `String` | Yes | HTTP method (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`) |
| `auth_headers` | `String` / `Hash` | No | Candidate authentication headers |
| `response_template` | `String` | No | Candidate Liquid response shaping template |
| `payload` | `Hash` / `String` | No | Candidate sample JSON payload |

---

### 3. ToolExecutionResult (Transient Service Output)

Returned by `Custom::Scout::Tools::HttpRequestExecutor.execute`.

| Attribute | Type | Description |
| :--- | :--- | :--- |
| `success` | `Boolean` | `true` if HTTP status is 2xx and template rendered without error; `false` otherwise |
| `status` | `Integer` / `nil` | Remote HTTP status code (e.g. `200`, `404`, `500`), or `nil` on DNS/network timeout |
| `raw_body` | `String` | Unmodified response body returned by the remote endpoint (truncated to 500 chars in test previews) |
| `formatted_response` | `String` / `Object` / `nil` | Shaped output rendered via `response_template`, or parsed JSON / raw body when template is absent |
| `error` | `String` / `nil` | Error diagnostic if network, HTTP, or template rendering failed |

---

## State Transitions and Execution Flows

### Execution Flow: Live Agent Call (`CallCustomApi`)

```mermaid
sequenceDiagram
    participant LLM as AI Agent / Runner
    participant Tool as CallCustomApi
    participant Exec as HttpRequestExecutor
    participant Ext as Remote API

    LLM->>Tool: execute(tool_id, payload)
    Tool->>Tool: Resolve enabled ScoutTool
    Tool->>Tool: validate_payload_schema (JSON Schema)
    alt Schema Validation Fails
        Tool-->>LLM: "Invalid payload parameters: ..."
    else Schema Valid
        Tool->>Exec: execute(tool_config, payload)
        Exec->>Exec: Strict Liquid URL Resolution
        alt Missing URL Path Variable
            Exec-->>Tool: Template Rendering Error
            Tool-->>LLM: "Error: Template rendering failed: ..."
        else URL Resolved
            Exec->>Ext: SafeFetch HTTP Request (GET query / POST body)
            Ext-->>Exec: Response (HTTP Status + Body)
            Exec->>Exec: Format Response (Liquid response_template or JSON.parse)
            Exec-->>Tool: Formatted Output
            Tool-->>LLM: Deliver Output
        end
    end
```

### Execution Flow: Modal Test Playground (`ScoutToolsController#test`)

```mermaid
sequenceDiagram
    participant UI as ScoutToolModal (Vue)
    participant Ctrl as ScoutToolsController#test
    participant Exec as HttpRequestExecutor
    participant Ext as Remote API

    UI->>Ctrl: POST /scout_tools/test { endpoint_url, http_method, auth_headers, response_template, payload }
    Ctrl->>Exec: execute(draft_config, payload) (NO schema validation)
    Exec->>Exec: Strict Liquid URL Resolution
    alt Missing URL Path Variable
        Exec-->>Ctrl: Execution Failure { success: false, error: "..." }
    else URL Resolved
        Exec->>Ext: SafeFetch HTTP Request
        alt Remote Error or Network Timeout
            Ext-->>Exec: Network Timeout / 4xx / 5xx
            Exec-->>Ctrl: Execution Failure { success: false, status: 404, raw_body: "...", error: "..." }
        else Remote Success
            Ext-->>Exec: 200 OK + Body
            Exec->>Exec: Render response_template if present
            Exec-->>Ctrl: Execution Success { success: true, status: 200, raw_body: "...", formatted_response: "..." }
        end
    end
    Ctrl-->>UI: 200 OK with JSON result payload
    UI->>UI: Render status badge, 500-char truncated raw preview, and shaped preview
```
