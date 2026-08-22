# API Contract: Scout Tools CRUD & Attributes

## Overview

This contract documents the updated attributes and payload specifications for standard Scout Tool management endpoints (`/api/v1/accounts/:account_id/scout_tools`).

---

## Endpoints

- `GET /api/v1/accounts/:account_id/scout_tools` — List tools
- `GET /api/v1/accounts/:account_id/scout_tools/:id` — Show tool
- `POST /api/v1/accounts/:account_id/scout_tools` — Create tool
- `PATCH /api/v1/accounts/:account_id/scout_tools/:id` — Update tool
- `DELETE /api/v1/accounts/:account_id/scout_tools/:id` — Delete tool

---

## Create / Update Request Payload

```json
{
  "name": "check_order_status",
  "description": "Check order shipping status and tracking code by order ID",
  "endpoint_url": "https://api.example.com/orders/{{order_id}}/status",
  "http_method": "GET",
  "auth_headers": "{\"Authorization\": \"Bearer secret_token\"}",
  "parameter_schema": {
    "type": "object",
    "properties": {
      "order_id": { "type": "string", "description": "Order ID" }
    },
    "required": ["order_id"]
  },
  "response_template": "Order {{ r.id }} is {{ r.status }} with tracking {{ r.tracking_code }}.",
  "enabled": true
}
```

### Parameter Specification

| Parameter | Type | Required (Create) | Description |
| :--- | :--- | :--- | :--- |
| `name` | `String` | Yes | Identifier for the tool used in AI agent prompts |
| `description` | `String` | Yes | Description explaining when and how the agent should call this tool |
| `endpoint_url` | `String` | Yes | Target endpoint URL with optional Liquid placeholders (`{{var}}`) |
| `http_method` | `String` | Yes | HTTP verb (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`) |
| `auth_headers` | `String` \| `Object` | No | Custom headers or auth tokens (encrypted at rest; never returned in GET responses) |
| `parameter_schema` | `Object` \| `String` | No | JSON schema defining accepted parameters for agent tool execution |
| `response_template` | `String` | No | Optional Liquid template to format and shape external API output |
| `enabled` | `Boolean` | No | Toggle to enable/disable tool visibility to agents (default `true`) |

---

## Tool Representation in GET Responses

```json
{
  "id": 12,
  "account_id": 1,
  "name": "check_order_status",
  "description": "Check order shipping status and tracking code by order ID",
  "endpoint_url": "https://api.example.com/orders/{{order_id}}/status",
  "http_method": "GET",
  "parameter_schema": {
    "type": "object",
    "properties": {
      "order_id": { "type": "string", "description": "Order ID" }
    },
    "required": ["order_id"]
  },
  "response_template": "Order {{ r.id }} is {{ r.status }} with tracking {{ r.tracking_code }}.",
  "enabled": true,
  "created_at": "2026-08-21T17:00:00.000Z",
  "updated_at": "2026-08-21T17:00:00.000Z"
}
```

> **Note**: `auth_headers` is excluded from all GET responses for security.
