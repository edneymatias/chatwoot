# API Contract: GET /api/v1/accounts/:account_id/scout_overview_reports

## Overview

Single read-only endpoint that returns all Scout Overview data in one request: summary metric cards, pipeline-stage distribution, and interest-by-stage distribution.

**Controller**: `Api::V1::Accounts::ScoutOverviewReportsController`  
**File**: `custom/app/controllers/api/v1/accounts/scout_overview_reports_controller.rb`  
**Route registration**: `config/routes.rb` — inside the account-scoped block, alongside `opportunity_funnel_reports` and `opportunity_attribute_reports`

---

## Request

```
GET /api/v1/accounts/:account_id/scout_overview_reports
```

### Headers

| Header | Value | Notes |
|---|---|---|
| `api_access_token` | `<user token>` | Standard Chatwoot auth |
| `account_id` | (URL segment) | |

### Query Parameters

| Param | Type | Required | Allowed Values | Description |
|---|---|---|---|---|
| `scout_id` | integer | **yes** | any valid Scout id in the account | Scout to aggregate |
| `range` | string | **yes** | `'7'`, `'30'`, `'this_month'`, `'last_month'` | Period window for summary cards |
| `timezone_offset` | numeric string | no | e.g. `'-3'`, `'5.5'` | Viewer UTC offset in hours for calendar-anchored ranges |

### Example Request

```
GET /api/v1/accounts/1/scout_overview_reports?scout_id=3&range=30&timezone_offset=-3
```

---

## Response

### 200 OK — Success

```json
{
  "summary": {
    "total_handled": 47,
    "qualification_rate": 51.06,
    "disqualification_rate": 29.79,
    "abandonment_rate": 12.77,
    "avg_messages_per_conversation": 8.4
  },
  "pipeline_stage_distribution": [
    { "stage_id": 1, "stage_name": "Novo",          "stage_position": 0, "count": 12 },
    { "stage_id": 2, "stage_name": "Qualificado",   "stage_position": 1, "count": 24 },
    { "stage_id": 3, "stage_name": "Negociação",    "stage_position": 2, "count": 7  },
    { "stage_id": 4, "stage_name": "Fechado",       "stage_position": 3, "count": 4  }
  ],
  "interest_by_stage": {
    "configured": true,
    "attribute_name": "Produto",
    "data": [
      {
        "stage_id": 1,
        "stage_name": "Novo",
        "breakdown": { "Seguro": 7, "Financiamento": 4, "null": 1 }
      },
      {
        "stage_id": 2,
        "stage_name": "Qualificado",
        "breakdown": { "Seguro": 14, "Financiamento": 10 }
      }
    ]
  }
}
```

### Nullable / Sentinel Values

| Field | When | Value |
|---|---|---|
| `summary.qualification_rate` | Scout has no `qualified_stage_id` configured, OR `total_handled == 0` | `null` |
| `summary.disqualification_rate` | Scout has no `unqualified_stage_id` configured, OR `total_handled == 0` | `null` |
| `summary.abandonment_rate` | Scout has no `rescue_stage_id` configured, OR `total_handled == 0` | `null` |
| `summary.avg_messages_per_conversation` | No handled conversations in the period | `null` |
| `interest_by_stage` | Scout has no `interest_attribute_definition` | `{ "configured": false }` |

### 200 OK — Empty State (no opportunities)

```json
{
  "summary": {
    "total_handled": 0,
    "qualification_rate": null,
    "disqualification_rate": null,
    "abandonment_rate": null,
    "avg_messages_per_conversation": null
  },
  "pipeline_stage_distribution": [
    { "stage_id": 1, "stage_name": "Novo",        "stage_position": 0, "count": 0 },
    { "stage_id": 2, "stage_name": "Qualificado", "stage_position": 1, "count": 0 }
  ],
  "interest_by_stage": { "configured": false }
}
```

Note: `pipeline_stage_distribution` always includes **all** account pipeline stages (count: 0 for empty ones), so the chart doesn't shift columns on Scout/period change.

### Error Responses

| Status | Condition | Body |
|---|---|---|
| `401 Unauthorized` | Missing or invalid auth token | Standard Chatwoot auth error |
| `403 Forbidden` | User lacks permission (`ScoutPolicy#show?` fails) | `{ "error": "..." }` |
| `404 Not Found` | `scout_id` not found in account | Standard Rails 404 |
| `422 Unprocessable Entity` | Missing `scout_id`, missing `range`, or invalid `range` value | `{ "error": "..." }` |

---

## Semantic Guarantees

1. `pipeline_stage_distribution` is **never period-filtered** — it reflects the current stage of all Scout-handled opportunities regardless of `range`. Changing `range` only affects `summary`.
2. `interest_by_stage.data` is also **not period-filtered** — same current-snapshot semantics as the stage distribution.
3. Rates are percentages (0–100, rounded to 2 decimal places). `null` is the explicit "not configured or no data" sentinel; `0.0` means "configured, has data, zero outcomes."
4. `pipeline_stage_distribution` includes all account pipeline stages in `position ASC` order, including stages managed by the human team after qualification.
5. The `null` key in `interest_by_stage.data[n].breakdown` represents opportunities with no value for the interest attribute.
6. **In Progress & Denominator Semantics (Clarification 2026-09-16)**: `summary.total_handled` includes all opportunities created by the Scout in the period across all pipeline stages, including those still In Progress. The outcome rates (`qualification_rate`, `disqualification_rate`, `abandonment_rate`) use `total_handled` as their denominator (`outcome_count ÷ total_handled * 100`). Because In Progress opportunities have no outcome stage, the sum of these rates is typically < 100% (the remainder represents in-progress volume).
7. **Authorization & Role Access (Clarification 2026-09-16 / FR-015)**: Accessible by any authenticated account member (`agent`, `administrator`, or `custom_role`) scoped to their account via `ScoutPolicy#show?`, mirroring the Captain Overview authorization. Does not use `ReportPolicy#view?` (which is admin-only).
8. **Performance Benchmark (Clarification SC-002)**: On-demand aggregations run against indexed columns (`origin_conversation_id`, `pipeline_stage_id`, `created_at`), returning in < 100ms on localhost/LAN for datasets up to ~10,000 opportunities per account, well within the 2.0-second limit.
