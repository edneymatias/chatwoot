# API Contract: Integration Hooks Lifecycle

**Endpoints**:
- `POST /api/v1/accounts/{account_id}/integrations/hooks`
- `DELETE /api/v1/accounts/{account_id}/integrations/hooks/{id}`

**Controller**: `Api::V1::Accounts::Integrations::HooksController`
**Access**: Account Administrator (`Current.account_user.administrator?`)

---

## 1. Create ERP Hook

Creates a new account-level integration hook for the specified ERP provider. Credential validation runs synchronously before the record is persisted.

### 1.1 Endpoint
`POST /api/v1/accounts/{account_id}/integrations/hooks`

### 1.2 Request Headers
| Header | Value | Description |
|---|---|---|
| `api_access_token` / Cookie | `string` | Authenticated administrator session or token. |
| `Content-Type` | `application/json` | Request format. |

### 1.3 Request Body
```json
{
  "app_id": "younus",
  "settings": {
    "token": "d748fbb2-9a67-4e6f-8321-729ef58b3c10",
    "id_empresa": "104"
  }
}
```

#### Field Specifications
| Field | Type | Required | Constraints | Description |
|---|---|---|---|---|
| `app_id` | `string` | Yes | Must be `"younus"` | Identifier of the application. |
| `settings.token` | `string` | Yes | Non-empty | API token for Younus authentication. Automatically stripped of whitespace. |
| `settings.id_empresa` | `string` | Yes | Non-empty | Company identifier on the Younus platform. Automatically stripped of whitespace. |

---

### 1.4 Responses

#### 200 OK — Successful Synchronous Validation & Creation
The credentials were validated against the remote ERP service, the record was saved with `status: "enabled"`, and the response returns the serialized hook with the API token masked.

```json
{
  "id": 42,
  "app_id": "younus",
  "status": true,
  "inbox": null,
  "account_id": 1,
  "hook_type": "account",
  "settings": {
    "id_empresa": "104",
    "token": "••••••••"
  },
  "reference_id": null
}
```

#### 422 Unprocessable Entity — Authentication Rejection (HTTP 401/403)
The remote service rejected the API token. The hook is not created.

```json
{
  "message": "Invalid credentials",
  "attributes": ["base"]
}
```
*(In Portuguese locale: `{"message": "Credenciais inválidas", "attributes": ["base"]}`)*

#### 422 Unprocessable Entity — Remote Service Down or Timeout (> 5s)
The remote service returned HTTP 503, connection timed out, or network failure occurred. The hook is not created.

```json
{
  "message": "Could not connect to ERP",
  "attributes": ["base"]
}
```
*(In Portuguese locale: `{"message": "Não foi possível conectar ao ERP", "attributes": ["base"]}`)*

#### 422 Unprocessable Entity — Schema Validation Error (Missing Fields)
Either `token` or `id_empresa` was missing from the payload.

```json
{
  "message": "Settings : Invalid settings data",
  "attributes": ["settings"]
}
```

#### 422 Unprocessable Entity — Feature Flag Disabled
The account attempting to create the hook does not have `erp_integration` enabled.

```json
{
  "message": "Feature flag Feature not enabled",
  "attributes": ["feature_flag"]
}
```

#### 422 Unprocessable Entity — Duplicate Hook
An active hook for `younus` already exists on this account (`allow_multiple_hooks: false`).

```json
{
  "message": "App has already been taken",
  "attributes": ["app_id"]
}
```

---

## 2. Disconnect / Delete ERP Hook

Deletes an existing ERP integration hook, disconnecting the account from the ERP provider.

### 2.1 Endpoint
`DELETE /api/v1/accounts/{account_id}/integrations/hooks/{id}`

### 2.2 Request Headers
| Header | Value | Description |
|---|---|---|
| `api_access_token` / Cookie | `string` | Authenticated administrator session or token. |

### 2.3 Responses

#### 200 OK — Successfully Deleted
Hook removed from the database.

```json
{}
```

#### 404 Not Found — Hook Does Not Exist
Specified hook does not exist or does not belong to the authenticated account.

```json
{
  "error": "Resource not found"
}
```
