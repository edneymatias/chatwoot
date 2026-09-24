# Contract: `POST /api/v1/accounts/:account_id/scout_tools/test`

Existing endpoint (`config/routes.rb:174-176`, `on: :collection` under `resources :scout_tools`).
This feature changes only its credential-reconciliation behavior; the endpoint URL, HTTP method,
auth requirement (`before_action :check_authorization`), and response shape are unchanged.

## Request body (all keys optional except `endpoint_url`, unchanged except for the new `id`)

| Key | Type | Change |
|---|---|---|
| `id` (or `scout_tool[id]`) | integer/string | **New**. When present and it resolves to a real `ScoutTool` belonging to the requesting account, the request is treated as "testing an already-saved tool" (FR-001/FR-004). Absent, non-numeric, mistyped, deleted, or belonging to a different account → treated identically to "no id" (FR-008). |
| `endpoint_url` | string | unchanged |
| `http_method` | string | unchanged, default `'POST'` |
| `auth_type` | string | unchanged, default `'none'` |
| `auth_headers` (or `headers`, or nested under `scout_tool`) | object | **Behavior change only when `id` resolves**: if every secret-bearing field in this object is blank or equal to `ScoutTool::MASKED_SECRET` (`'••••••••'`), the server substitutes the resolved tool's real, saved credential for those fields before calling the external endpoint (FR-002). Any field the operator actually typed a new, non-masked, non-blank value for is used exactly as submitted (FR-003). When `id` does not resolve, this object is used exactly as submitted, unchanged from current behavior (FR-006). |
| `response_template` | string | unchanged |
| `payload` | object | unchanged |

## Response body

Unchanged — same shape as today:

```json
{
  "success": true,
  "status": 200,
  "raw_body": "...",
  "truncated": false,
  "formatted_response": "...",
  "error": null
}
```

**No new field, and no existing field, ever reveals**:
- the real value of a saved credential (FR-007 — reconciliation happens server-side only, before
  the outbound `HttpRequestExecutor` call; the response only reflects the *external API's* reply),
- whether a submitted `id` exists for a *different* account (FR-008 — an unresolved id produces
  exactly the same request/response shape as no id at all; there is no distinct 404/403 branch for
  this action).

## Non-goals (explicitly unchanged by this contract)

- `GET /scout_tools`, `GET /scout_tools/:id` — continue to return only
  `masked_auth_headers` (`{'token' => '••••••••'}` etc.) for any saved tool; this fix adds no new
  read path (FR-007, User Story 3).
- `PATCH /scout_tools/:id` (`update`) — its existing masked/blank reconciliation via
  `apply_credentials_update` is unchanged; the new `ScoutTool#auth_headers_for_test` is an
  additional, non-persisting method, not a replacement.
