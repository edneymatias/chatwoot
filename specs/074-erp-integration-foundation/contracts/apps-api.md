# API Contract: Integration Apps Catalog

**Endpoint**: `GET /api/v1/accounts/{account_id}/integrations/apps`
**Controller**: `Api::V1::Accounts::Integrations::AppsController#index`
**Access**: Account Administrator (`Current.account_user.administrator?`)

---

## 1. Overview
Returns the list of active integrations for the current account. When the account has the `erp_integration` feature flag enabled, the catalog includes the `younus` app entry with `category: "erp"`. When disabled, the `younus` entry is completely omitted from the response.

---

## 2. Request

### Headers
| Header | Value | Description |
|---|---|---|
| `api_access_token` / Cookie | `string` | Authenticated user session or token. |
| `Content-Type` | `application/json` | Request format. |

### Parameters
| Name | Type | Location | Required | Description |
|---|---|---|---|---|
| `account_id` | `integer` | Path | Yes | Target account identifier. |

---

## 3. Responses

### 3.1 200 OK — Feature Flag Enabled (`erp_integration: true`)

```json
{
  "payload": [
    {
      "id": "younus",
      "name": "Younus ERP",
      "description": "Integrate your Younus ERP system with Chatwoot to access customer and financial data directly in conversation views.",
      "short_description": "Connect Younus ERP to view customer and financial information.",
      "enabled": false,
      "logo": "younus.png",
      "category": "erp",
      "feature_flag": "erp_integration",
      "hook_type": "account",
      "allow_multiple_hooks": false,
      "action": "/younus",
      "button": "/younus",
      "visible_properties": [
        "id_empresa",
        "token"
      ],
      "settings_json_schema": {
        "type": "object",
        "properties": {
          "token": { "type": "string" },
          "id_empresa": { "type": "string" }
        },
        "required": ["token", "id_empresa"],
        "additionalProperties": false
      },
      "settings_form_schema": [
        {
          "label": "API Token",
          "type": "text",
          "name": "token",
          "validation": "required"
        },
        {
          "label": "Company ID",
          "type": "text",
          "name": "id_empresa",
          "validation": "required"
        }
      ],
      "hooks": []
    }
  ]
}
```

#### Connected Hook Present
When an enabled hook exists for `younus`, the `enabled` field is `true` and the `hooks` array contains the serialized hook with masked `token`:

```json
{
  "id": "younus",
  "name": "Younus ERP",
  "enabled": true,
  "hooks": [
    {
      "id": 12,
      "app_id": "younus",
      "status": true,
      "account_id": 1,
      "hook_type": "account",
      "settings": {
        "id_empresa": "104",
        "token": "••••••••"
      },
      "reference_id": null
    }
  ]
}
```

---

### 3.2 200 OK — Feature Flag Disabled (`erp_integration: false`)
The `younus` object is absent from the `payload` array:

```json
{
  "payload": [
    {
      "id": "webhook",
      "name": "Webhooks",
      "enabled": false,
      "hooks": []
    }
  ]
}
```

---

### 3.3 401 Unauthorized
When the user is not authenticated:

```json
{
  "error": "You need to sign in or sign up before continuing."
}
```
