# Phase 1 Data Model: Scout Custom Tool Authentication & Visual Parameter Builder

## Entity Relationship & Schema

### 1. `ScoutTool` (`ichatr_scout_tools`)

The primary database entity representing a callable external tool configured for an account.

```mermaid
erDiagram
    Account ||--o{ ScoutTool : owns

    ScoutTool {
        bigint id PK
        bigint account_id FK
        string name
        text description
        text endpoint_url
        string http_method
        string auth_type "none | bearer | basic | api_key (NEW)"
        text auth_headers "encrypted JSON with credentials"
        jsonb parameter_schema "compiled JSON Schema"
        text response_template "optional Liquid template"
        boolean enabled
        datetime created_at
        datetime updated_at
    }
```

### Column Specifications

| Column | Type | Nullable | Default | Description |
| :--- | :--- | :---: | :---: | :--- |
| `id` | `bigint` | No | Auto | Primary key |
| `account_id` | `bigint` | No | — | Foreign key to `accounts.id` |
| `name` | `string` | No | — | Human-readable tool name |
| `description` | `text` | No | — | Description for the LLM to know when to use the tool |
| `endpoint_url` | `text` | No | — | Target REST endpoint with optional `{{ var }}` variables |
| `http_method` | `string` | No | `'POST'` | HTTP method (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`) |
| `auth_type` | `string` | No | `'none'` | **NEW**: Authentication mode (`none`, `bearer`, `basic`, `api_key`) |
| `auth_headers` | `text` | Yes | `nil` | Encrypted JSON credentials payload (ActiveRecord encrypted) |
| `parameter_schema` | `jsonb` | Yes | `{}` | Compiled JSON Schema (`type: 'object'`, `properties`, `required`) |
| `response_template` | `text` | Yes | `nil` | Optional Liquid template for output formatting |
| `enabled` | `boolean` | No | `true` | Enable/disable toggle for tool execution |

---

## Credential Structures in `auth_headers`

Depending on `auth_type`, `auth_headers` stores the following encrypted JSON representations:

### 1. `auth_type: "none"`
```json
{}
```

### 2. `auth_type: "bearer"`
```json
{
  "token": "sk_live_123456789abcdef"
}
```
*At execution time, translated to `Authorization: Bearer sk_live_123456789abcdef`.*

### 3. `auth_type: "basic"`
```json
{
  "username": "api_user",
  "password": "secret_password_123"
}
```
*At execution time, translated to `Authorization: Basic <Base64(username:password)>`.*

### 4. `auth_type: "api_key"`
```json
{
  "header_name": "X-API-Key",
  "header_value": "sec_key_987654321"
}
```
*At execution time, translated to `X-API-Key: sec_key_987654321`.*

---

## Visual Parameter Object vs JSON Schema Mapping

### Visual Builder Model (Frontend State)
```typescript
interface VisualParameter {
  id: string | number;
  name: string;        // e.g. "order_id" (valid identifier regex: /^[a-zA-Z_][a-zA-Z0-9_]*$/)
  type: 'string' | 'number' | 'integer' | 'boolean' | 'array' | 'object';
  description: string; // e.g. "The customer order number from invoice"
  required: boolean;   // e.g. true
}
```

Parameters are held as an ordered array in component state (`VisualParameter[]`); no separate `order`/`position` field is needed. Reordering (move up/down or drag handle) simply mutates the array's element order. On compile, array order becomes the insertion order of keys in the compiled `properties` object below — both JS object key order and `JSON.stringify` preserve string-key insertion order, so the persisted `parameter_schema` reflects the user's chosen order without any extra schema field.

### Backend Safeguard Validation

As a safeguard behind the frontend's regex/duplicate checks (per FR-012), `ScoutTool` also validates `parameter_schema` server-side before save: every property name MUST match `/^[a-zA-Z_][a-zA-Z0-9_]*$/`, and no two properties in the same schema may share a name. This mirrors the client-side rule so a malformed schema can never reach the AI agent even if it bypasses the UI (e.g. a direct API call).

### Compiled JSON Schema (`parameter_schema`)
```json
{
  "type": "object",
  "properties": {
    "order_id": {
      "type": "string",
      "description": "The customer order number from invoice"
    },
    "max_results": {
      "type": "integer",
      "description": "Maximum number of items to return"
    }
  },
  "required": [
    "order_id"
  ]
}
```

---

## Execution Sequence: Modal Save & Test Connection

```mermaid
sequenceDiagram
    autonumber
    actor User as Operator / Admin
    participant Modal as ScoutToolModal.vue
    participant API as ScoutToolsController
    participant Model as ScoutTool (DB)
    participant Exec as HttpRequestExecutor
    participant Ext as External REST API

    User->>Modal: Configures Auth Type (e.g. Bearer) & Visual Parameters
    Modal->>Modal: Compiles visual parameters into JSON Schema
    
    alt User clicks "Test Connection"
        Modal->>API: POST /scout_tools/test (endpoint_url, http_method, auth_type, auth_headers, response_template, payload)
        API->>Exec: execute(auth_type, auth_headers, payload...)
        Exec->>Ext: SafeFetch HTTP request with formatted Authorization header
        Ext-->>Exec: Raw HTTP Response (e.g. 200 OK)
        Exec->>Exec: Render response_template (if present)
        Exec-->>API: Result(status: 200, raw_body, formatted_response)
        API-->>Modal: JSON preview (status, raw, shaped)
        Modal-->>User: Displays status badge & rendered previews
    else User clicks "Save / Create"
        Modal->>API: POST /scout_tools (or PUT) with name, endpoint_url, auth_type, auth_headers, parameter_schema...
        API->>Model: save (validates identifiers, encrypts auth_headers, stores auth_type)
        Model-->>API: Record saved
        API-->>Modal: Returns tool object with masked credentials
        Modal-->>User: Closes modal and refreshes tools list
    end
```
