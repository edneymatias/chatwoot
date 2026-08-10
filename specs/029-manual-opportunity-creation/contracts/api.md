# API Contracts

## Update Opportunity

**Endpoint**: `PUT /api/v1/accounts/:account_id/opportunities/:id`

**Modifications**:
- Accepts `origin_conversation_id` in the JSON payload.

**Request Payload Example**:
```json
{
  "origin_conversation_id": 12345
}
```

**Response**:
- `200 OK`: If the opportunity was successfully updated.
- `422 Unprocessable Entity`: If `origin_conversation_id` was already set previously (validation failure).
