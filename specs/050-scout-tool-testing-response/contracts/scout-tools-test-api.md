# API Contract: Scout Tools Test Endpoint

## Endpoint

`POST /api/v1/accounts/:account_id/scout_tools/test`

## Description

Executes an ad-hoc test request against a candidate external API endpoint using draft tool configuration parameters without saving or persisting the tool to the database. Schema validation is bypassed to allow exploratory testing.

## Headers

| Header | Type | Value / Description |
| :--- | :--- | :--- |
| `api_access_token` | `String` | User authentication token (or cookie session) |
| `Content-Type` | `String` | `application/json` |

## Request Body

```json
{
  "endpoint_url": "https://api.example.com/orders/{{order_id}}/status",
  "http_method": "GET",
  "auth_headers": {
    "Authorization": "Bearer secret_token_xyz"
  },
  "response_template": "Order {{ r.id }} is currently {{ r.status }}.",
  "payload": {
    "order_id": "1001",
    "verbose": "true"
  }
}
```

### Request Parameters

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `endpoint_url` | `String` | Yes | Target endpoint URL, supporting dynamic Liquid path placeholders (e.g. `{{order_id}}`). |
| `http_method` | `String` | Yes | HTTP method (`GET`, `POST`, `PUT`, `PATCH`, `DELETE`). |
| `auth_headers` | `Object` \| `String` | No | Custom authentication headers (as JSON object, raw string, or JSON-stringified). |
| `response_template` | `String` | No | Liquid template to format and shape the output. |
| `payload` | `Object` \| `String` | No | Sample test payload providing variables for path placeholders, query parameters, or request body. |

---

## Response

The endpoint returns HTTP status `200 OK` for all completed test executions (including remote 4xx/5xx and network failures) with structured result metadata.

### Success Response (`200 OK`)

```json
{
  "success": true,
  "status": 200,
  "raw_body": "{\"id\": 1001, \"status\": \"shipped\", \"carrier\": \"FedEx\"}",
  "formatted_response": "Order 1001 is currently shipped.",
  "error": null
}
```

### Remote API Error Response (`200 OK`)

```json
{
  "success": false,
  "status": 404,
  "raw_body": "{\"error\": \"Order not found\"}",
  "formatted_response": null,
  "error": "External system returned error status: 404 Not Found"
}
```

### Template Resolution / Missing Variable Error (`200 OK`)

```json
{
  "success": false,
  "status": null,
  "raw_body": null,
  "formatted_response": null,
  "error": "Template rendering failed: undefined variable 'order_id'"
}
```

### Network Timeout / DNS Resolution Error (`200 OK`)

```json
{
  "success": false,
  "status": null,
  "raw_body": null,
  "formatted_response": null,
  "error": "Request failed or timed out while contacting the external system: execution expired"
}
```

### Response Attributes

| Field | Type | Description |
| :--- | :--- | :--- |
| `success` | `Boolean` | `true` if request completed with 2xx HTTP status and response template rendered cleanly; `false` otherwise. |
| `status` | `Integer` \| `null` | HTTP status code returned by remote server, or `null` if the request did not reach the remote server. |
| `raw_body` | `String` \| `null` | Raw response body returned by the remote server, truncated to a maximum of 500 characters. |
| `formatted_response` | `String` \| `Object` \| `null` | Rendered output from `response_template`, or parsed JSON / raw body when no template is configured. |
| `error` | `String` \| `null` | Descriptive error message if any step failed. |
