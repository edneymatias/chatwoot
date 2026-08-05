# Contract: Opportunity Attribute Report Endpoint

## `GET /api/v1/accounts/:account_id/opportunity_attribute_reports`

Read-only; mirrors `GET .../opportunity_funnel_reports` conventions exactly (same auth, same date
param shape).

### Authorization

`ReportPolicy#view?` (administrator only), enforced via `authorize :report, :view?`, same as
`OpportunityFunnelReportsController`. Also gated by `Concerns::KanbanFeatureGuard` (403 when the
account's `opportunities` feature flag is disabled).

### Query Parameters

| Param | Type | Required | Notes |
|---|---|---|---|
| `custom_attribute_definition_id` | integer | Yes | Must belong to `Current.account`, `attribute_model: opportunity_attribute`, `attribute_display_type: list` |
| `since` | unix timestamp (string/int) | No | Start of the period filter for won/lost/`avg_time_to_close`; open-opportunity aggregates are never period-filtered |
| `until` | unix timestamp (string/int) | No | End of the period filter, same semantics as `since` |

`since`/`until` follow the exact same `DateRangeHelper#range` convention already used by
`OpportunityFunnelReportsController` — both must be present to apply a filter; if either is
blank, `range` is `nil` and period-scoped metrics fall back to all-time.

### Success Response — `200 OK`

```json
{
  "definition": {
    "id": 42,
    "attribute_key": "interesse",
    "attribute_display_name": "Interesse"
  },
  "rows": [
    {
      "value": "Implantes",
      "opportunities_count": 12,
      "total_value": 48000.0,
      "won_count": 3,
      "won_value": 9000.0,
      "lost_count": 1,
      "lost_value": 2500.0,
      "avg_time_to_close": 14.5
    },
    {
      "value": "Ortodontia",
      "opportunities_count": 0,
      "total_value": 0.0,
      "won_count": 0,
      "won_value": 0.0,
      "lost_count": 0,
      "lost_value": 0.0,
      "avg_time_to_close": null
    },
    {
      "value": null,
      "opportunities_count": 5,
      "total_value": 9000.0,
      "won_count": 0,
      "won_value": 0.0,
      "lost_count": 2,
      "lost_value": 1200.0,
      "avg_time_to_close": null
    }
  ]
}
```

Row order: `definition.attribute_values` order, then the `value: null` ("no value") row last
(FR-006). Every defined value is present even with all-zero metrics (FR-007) — never omitted.

### Error Response — `422 Unprocessable Entity`

Returned when `custom_attribute_definition_id` is missing/invalid, doesn't belong to the account,
or isn't an opportunity-scoped list attribute (FR-002):

```json
{ "error": "Invalid or missing list-type opportunity custom attribute" }
```

### Error Response — `403 Forbidden`

Returned by `ReportPolicy`/`KanbanFeatureGuard` under the same conditions as every other
kanban/report endpoint (non-administrator user, or the `opportunities` feature disabled for the
account) — no feature-specific logic.
