# Data Model: ERP Integration Foundation & Younus Setup

**Feature**: 074-erp-integration-foundation
**Date**: 2026-09-17
**Status**: Completed

## 1. Entity Overview

```
+-------------------------------------------------------+
|                       Account                         |
|-------------------------------------------------------|
| id: integer                                           |
| feature_flags: integer / bitmask                      |
| -> feature_enabled?('erp_integration')                |
+---------------------------+---------------------------+
                            | 1
                            |
                            | has_many
                            v *
+-------------------------------------------------------+
|                  Integrations::Hook                   |
|-------------------------------------------------------|
| id: bigint (PK)                                       |
| account_id: integer (FK)                              |
| app_id: string ('younus')                             |
| hook_type: enum (account: 0, inbox: 1)                |
| status: enum (disabled: 0, enabled: 1)                |
| settings: jsonb { token: string, id_empresa: string } |
| access_token: string                                  |
| created_at: datetime                                  |
| updated_at: datetime                                  |
+---------------------------+---------------------------+
                            | resolves via
                            v Erp::AdapterFactory
+-------------------------------------------------------+
|                    Erp::BaseAdapter                   |
|                      (Abstract)                       |
|-------------------------------------------------------|
| + test_connection -> boolean                          |
| + self.erp_name -> string                             |
+---------------------------+---------------------------+
                            |
                            | inherits
                            v
+-------------------------------------------------------+
|                  Erp::Younus::Adapter                 |
|-------------------------------------------------------|
| - hook: Integrations::Hook                            |
| - client: Erp::Younus::Client                         |
|-------------------------------------------------------|
| + test_connection -> boolean                          |
| + self.erp_name -> 'Younus'                           |
+---------------------------+---------------------------+
                            | uses
                            v
+-------------------------------------------------------+
|                  Erp::Younus::Client                  |
|-------------------------------------------------------|
| - base_uri: 'https://wfh.ichatr.com.br'               |
| - token: string                                       |
| - id_empresa: string                                  |
| - timeout: 5 seconds                                  |
|-------------------------------------------------------|
| + search_by_phone(phone: string) -> Hash / nil        |
+-------------------------------------------------------+
```

---

## 2. Model Definitions & Attributes

### 2.1 Integrations::Hook (`integrations_hooks`)
Existing Chatwoot ActiveRecord model extended via `Custom::Integrations::Hook`.

| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | `bigint` | Primary Key, Not Null | Unique identifier for the hook record. |
| `account_id` | `integer` | Foreign Key (`accounts.id`), Not Null | Scopes the integration to a specific account. |
| `app_id` | `string` | Not Null, indexed | Identifier of the integration app (`'younus'`). Uniqueness scoped to `[:account_id]`. |
| `hook_type` | `integer` | Default `0` (`account`) | Level of the hook (`account` vs `inbox`). For ERP, always `account`. |
| `status` | `integer` | Default `1` (`enabled`) | Lifecycle state (`disabled: 0`, `enabled: 1`). |
| `settings` | `jsonb` | Nullable | Stores provider-specific parameters: `token` and `id_empresa`. |
| `access_token` | `string` | Indexed, unique token | Secure webhook/access token generated per hook. |
| `created_at` | `datetime` | Not Null | Timestamp of creation. |
| `updated_at` | `datetime` | Not Null | Timestamp of last modification. |

#### Settings Payload Schema (JSONB)
For `app_id: 'younus'`:
```json
{
  "type": "object",
  "properties": {
    "token": {
      "type": "string",
      "description": "Static API token provided via request headers"
    },
    "id_empresa": {
      "type": "string",
      "description": "Company identifier on the Younus platform"
    }
  },
  "required": ["token", "id_empresa"],
  "additionalProperties": false
}
```

---

### 2.2 Integrations::App
Virtual model loaded from `config/integration/apps.yml` representing integration definitions.

| Attribute | Type | Example Value | Description |
|---|---|---|---|
| `id` | `string` | `'younus'` | Unique app key. |
| `category` | `string` | `'erp'` | Categorization field. Groups ERP apps into the unified ERP gallery. |
| `feature_flag` | `string` | `'erp_integration'` | Account feature flag required to enable and view this app. |
| `logo` | `string` | `'younus.png'` | Image filename in `/public/dashboard/images/integrations/`. |
| `i18n_key` | `string` | `'younus'` | Key prefix in `integration_apps.<key>`. |
| `hook_type` | `string` | `'account'` | Scope of the integration hook. |
| `allow_multiple_hooks`| `boolean`| `false` | Restricts accounts to at most one hook for this app. |
| `visible_properties` | `string[]` | `['id_empresa', 'token']` | Fields permitted to be serialized back to administrators in API responses. |
| `settings_json_schema`| `Hash` | JSON Schema | Schema used by JSONSchemer for backend validation. |
| `settings_form_schema`| `Array` | FormKit Schema | Schema used by `NewHook.vue` to render dynamic form inputs. |

---

## 3. Service Objects & Adapter Architecture

### 3.1 `Erp::BaseAdapter` (`custom/app/services/erp/base_adapter.rb`)
Abstract base class defining the provider interface.

- **Initialization**: `initialize(hook)`
  - Accepts an `Integrations::Hook` instance.
  - Stores `@hook = hook`, `@settings = hook.settings || {}`.
- **Class Methods**:
  - `self.erp_name`: Must return human-readable name of the provider (e.g., `'Younus'`). Raises `NotImplementedError` if not overridden.
- **Instance Methods**:
  - `test_connection`: Must execute synchronous connection validation and return `true` on success. Raises `Erp::AuthenticationError` or `Erp::ApiError` on failure. Raises `NotImplementedError` if not overridden.

### 3.2 `Erp::AdapterFactory` (`custom/app/services/erp/adapter_factory.rb`)
Factory service mapping `Integrations::Hook#app_id` to its concrete adapter.

- **Methods**:
  - `self.build(hook)`:
    - `case hook.app_id`
    - `'younus'` → `Erp::Younus::Adapter.new(hook)`
    - `else` → raises `ArgumentError, "Unsupported ERP provider: #{hook.app_id}"`

### 3.3 `Erp::Younus::Adapter` (`custom/app/services/erp/younus/adapter.rb`)
Concrete adapter subclassing `Erp::BaseAdapter`.

- **Implementation**:
  - `self.erp_name`: Returns `'Younus'`.
  - `test_connection`:
    - Reads `token = @settings['token']`, `id_empresa = @settings['id_empresa']`.
    - Instantiates `client = Erp::Younus::Client.new(token: token, id_empresa: id_empresa)`.
    - Invokes `client.search_by_phone('0')`.
    - If no exception is raised, returns `true`.

### 3.4 `Erp::Younus::Client` (`custom/app/services/erp/younus/client.rb`)
HTTParty HTTP client communicating with the Younus API.

- **Configuration**:
  - `base_uri 'https://wfh.ichatr.com.br'`
  - `default_timeout 5`
- **Methods**:
  - `initialize(token:, id_empresa:)`
  - `search_by_phone(phone:)`:
    - Sends `GET /webhook/pessoas` with query params `{ idEmpresa: @id_empresa, nrTelcelpessoa: phone }` and header `{ 'token' => @token }`.
    - Rescues `Net::OpenTimeout`, `Net::ReadTimeout`, `Timeout::Error` → raises `Erp::ApiError, 'Connection timed out'`
    - Rescues `SocketError`, `Errno::ECONNREFUSED` → raises `Erp::ApiError, 'Network error'`
    - Handles status codes:
      - `401`, `403` → raises `Erp::AuthenticationError, 'Invalid credentials'`
      - `500..599` → raises `Erp::ApiError, "ERP service error: #{response.code}"`
      - `200` → parses JSON body:
        - If `body['sucesso'] == true` → returns parsed `body.dig('dados', 0, 'json')`
        - If `body['sucesso'] == false` → returns `nil` (person not found, valid connection)
        - If malformed JSON → raises `Erp::ApiError, 'Malformed response from ERP'`
      - Other codes → raises `Erp::ApiError, "Unexpected response: #{response.code}"`

---

## 4. Validation Rules & Lifecycle Hooks

### 4.1 Sanitization (`before_validation`)
- Invoked on `create` and `update` when `erp_integration?` is true.
- Iterates over `self.settings` and applies `.strip` to all string values (`token`, `id_empresa`) to remove accidental leading or trailing whitespace.

### 4.2 JSON Schema Validation (`validate :validate_settings_json_schema`)
- Standard Chatwoot validation using `JSONSchemer`.
- Ensures `token` and `id_empresa` are present and are strings.

### 4.3 Feature Flag Validation (`validate :ensure_feature_enabled`)
- Standard Chatwoot validation.
- Verifies that `account.feature_enabled?('erp_integration')` is true. If false, adds `:feature_flag, 'Feature not enabled'`.

### 4.4 Synchronous Credential Validation (`validate :validate_erp_credentials`)
- Conditional on `:validate_erp_credentials?`:
  - `erp_integration? && enabled? && (new_record? || will_save_change_to_settings? || will_save_change_to_status?)`
- Resolves adapter via `Erp::AdapterFactory.build(self)`.
- Calls `adapter.test_connection`.
- Exception translation:
  - `Erp::AuthenticationError` → `errors.add(:base, I18n.t('errors.erp.invalid_credentials'))`
  - `Erp::ApiError`, `StandardError` → `errors.add(:base, I18n.t('errors.erp.connection_error'))`

---

## 5. Security & Masking Pipeline

To satisfy FR-011 and prevent secret exposure across the wire:

```
[Database: integrations_hooks.settings]
  token: "secret-token-xyz-123"
  id_empresa: "42"
         |
         v
[Custom::Integrations::Hook#masked_settings]
  token: "••••••••"
  id_empresa: "42"
         |
         v
[app/views/api/v1/models/_hook.json.jbuilder]
  json.settings: { "token": "••••••••", "id_empresa": "42" }
         |
         v
[Browser / Vue Store: integrations.hooks]
  settings: { token: "••••••••", id_empresa: "42" }
         |
         v
[SingleIntegrationHooks.vue & Erp/Index.vue]
  Company ID: "42"
  API Token: "••••••••"
```
