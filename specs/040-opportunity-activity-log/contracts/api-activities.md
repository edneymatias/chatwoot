# API Contract: Opportunity Activities

**Endpoint**: `GET /api/v1/accounts/:account_id/opportunities/:opportunity_id/activities`  
**Authentication**: Standard Chatwoot User session / API Token  
**Authorization**: Opportunity policy (`show?` permission on the opportunity)  
**Scoping**: Enforced to `Current.account.opportunities.find(params[:opportunity_id])`  

---

## Request

### Headers
```http
Accept: application/json
Content-Type: application/json
api_access_token: <token>
```

### URL Parameters
- `account_id` (integer, required): Account identifier
- `opportunity_id` (integer, required): Opportunity identifier

### Query Parameters
None in v1 (full history returned in reverse chronological order).

---

## Response

### `200 OK`
Returns an array of activity objects ordered by `occurred_at DESC`.

```json
[
  {
    "id": 104,
    "event_type": "conversation_opened",
    "occurred_at": 1755442800,
    "actor": {
      "id": 12,
      "type": "user",
      "name": "Jane Agent"
    },
    "metadata": {
      "conversation_id": 456,
      "conversation_display_id": 78,
      "is_origin": false
    }
  },
  {
    "id": 103,
    "event_type": "opportunity_stage_changed",
    "occurred_at": 1755439200,
    "actor": {
      "id": 3,
      "type": "automation_rule",
      "name": "Move Qualified Deals"
    },
    "metadata": {
      "from_stage_id": 1,
      "to_stage_id": 2
    }
  },
  {
    "id": 102,
    "event_type": "opportunity_won",
    "occurred_at": 1755435600,
    "actor": {
      "type": "system",
      "name": "System"
    },
    "metadata": {
      "from_stage_id": 2,
      "approximate": true
    }
  },
  {
    "id": 101,
    "event_type": "opportunity_created",
    "occurred_at": 1755400000,
    "actor": {
      "id": 12,
      "type": "user",
      "name": "Jane Agent"
    },
    "metadata": {}
  }
]
```

### `401 Unauthorized`
Returned when user is not authenticated.

### `403 Forbidden`
Returned when user lacks permission to access the opportunity.

### `404 Not Found`
Returned when `opportunity_id` does not exist in the scoped account.
