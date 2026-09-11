# API Contract: Scout Tools Management & Test Endpoint

This document specifies the REST API contracts for creating, updating, listing, and testing Scout Custom Tools with authentication modes and parameter schemas.

---

## 1. List Scout Tools

**Endpoint**: `GET /api/v1/accounts/:account_id/scout_tools`  
**Authentication**: Required (Admin or Agent)

### Response (200 OK)
```json
[
  {
    "id": 1,
    "account_id": 1,
    "name": "Order Lookup",
    "description": "Looks up order details by order ID",
    "endpoint_url": "https://api.example.com/orders/{{ order_id }}",
    "http_method": "GET",
    "auth_type": "bearer",
    "auth_headers": {
      "token": "••••••••"
    },
    "parameter_schema": {
      "type": "object",
      "properties": {
        "order_id": {
          "type": "string",
          "description": "The customer order number from invoice"
        }
      },
      "required": ["order_id"]
    },
    "response_template": "Order {{ order_id }} status: {{ status }}",
    "enabled": true,
    "created_at": "2026-08-26T12:00:00.000Z",
    "updated_at": "2026-08-26T12:00:00.000Z"
  }
]
```

---

## 2. Create Scout Tool

**Endpoint**: `POST /api/v1/accounts/:account_id/scout_tools`  
**Authentication**: Required (Admin or Agent)

### Request Payload
```json
{
  "scout_tool": {
    "name": "Order Lookup",
    "description": "Looks up order details by order ID",
    "endpoint_url": "https://api.example.com/orders/{{ order_id }}",
    "http_method": "GET",
    "auth_type": "bearer",
    "auth_headers": {
      "token": "secret_live_token_abc123"
    },
    "parameter_schema": {
      "type": "object",
      "properties": {
        "order_id": {
          "type": "string",
          "description": "The customer order number from invoice"
        }
      },
      "required": ["order_id"]
    },
    "response_template": "Order {{ order_id }} status: {{ status }}",
    "enabled": true
  }
}
```

### Response (201 Created)
Returns the created `ScoutTool` JSON object with masked secret values.

---

## 3. Update Scout Tool

**Endpoint**: `PATCH /api/v1/accounts/:account_id/scout_tools/:id`  
**Authentication**: Required (Admin or Agent)

### Request Payload (Preserving Unchanged Credentials)
```json
{
  "scout_tool": {
    "name": "Order Lookup (Updated)",
    "description": "Looks up order details by order ID or tracking code",
    "endpoint_url": "https://api.example.com/orders/{{ order_id }}",
    "http_method": "GET",
    "auth_type": "bearer",
    "auth_headers": {
      "token": "••••••••"
    },
    "parameter_schema": {
      "type": "object",
      "properties": {
        "order_id": {
          "type": "string",
          "description": "The customer order number"
        },
        "tracking_code": {
          "type": "string",
          "description": "Shipping carrier tracking code"
        }
      },
      "required": ["order_id"]
    }
  }
}
```

*Note*: If `token` is `"••••••••"`, the backend keeps the previously stored encrypted token intact.

### Response (200 OK)
Returns the updated `ScoutTool` JSON object.

---

## 4. Test Tool Connection (Non-persisting)

**Endpoint**: `POST /api/v1/accounts/:account_id/scout_tools/test`  
**Authentication**: Required (Admin or Agent)

### Request Payload
```json
{
  "endpoint_url": "https://api.example.com/orders/{{ order_id }}",
  "http_method": "GET",
  "auth_type": "api_key",
  "auth_headers": {
    "header_name": "X-API-Key",
    "header_value": "sec_123456"
  },
  "response_template": "Order status is {{ response.status }}",
  "payload": {
    "order_id": "ORD-999"
  }
}
```

### Response (200 OK - Successful Connection)
```json
{
  "success": true,
  "status": 200,
  "raw_body": "{\"status\":\"delivered\",\"items\":2}",
  "truncated": false,
  "formatted_response": "Order status is delivered",
  "error": null
}
```

### Response (200 OK - Remote Error)
```json
{
  "success": false,
  "status": 401,
  "raw_body": "{\"error\":\"Invalid API key\"}",
  "truncated": false,
  "formatted_response": null,
  "error": "External system returned error status: 401 Unauthorized"
}
```
