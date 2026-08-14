# API Contract: Opportunity Custom Attribute Filtering

## Endpoint
- **GET** `/api/v1/accounts/{account_id}/opportunities`
- **GET** `/api/v1/accounts/{account_id}/opportunities/pipeline_stages/{stage_id}/cards`

## Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `payload` | String (JSON Array) | No | List of filter definition objects |
| `pipeline_id` | Integer | No | Pipeline filter |
| `pipeline_stage_id` | Integer | No | Stage filter |
| `status` | String | No | Opportunity status (`open`, `won`, `lost`) |
| `page` | Integer | No | Pagination page |

## Filter Payload Object Schema

```json
[
  {
    "attribute_key": "data_agendamento",
    "filter_operator": "is_greater_than",
    "values": ["2026-08-01"],
    "attribute_model": "customAttributes"
  },
  {
    "attribute_key": "data_agendamento",
    "filter_operator": "is_less_than",
    "values": ["2026-08-31"],
    "attribute_model": "customAttributes"
  },
  {
    "attribute_key": "data_agendamento",
    "filter_operator": "equal_to",
    "values": ["2026-08-13"],
    "attribute_model": "customAttributes"
  }
]
```

## Response Schema (Success 200 OK)

```json
{
  "payload": [
    {
      "id": 123,
      "title": "Opportunity 1",
      "value": "1500.0",
      "status": "open",
      "pipeline_stage_id": 4,
      "custom_attributes": {
        "data_agendamento": "2026-08-13"
      },
      "created_at": "2026-08-10T12:00:00.000Z",
      "updated_at": "2026-08-13T15:30:00.000Z"
    }
  ],
  "meta": {
    "count": 1,
    "current_page": 1,
    "total_pages": 1
  }
}
```
