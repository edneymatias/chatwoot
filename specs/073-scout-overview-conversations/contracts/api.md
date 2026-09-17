# API Contract: Scout Overview — Recent Conversations List

**Endpoint**: `GET /api/v1/accounts/:account_id/scout_overview_reports/conversations`  
**Controller**: `Api::V1::Accounts::ScoutOverviewReportsController#conversations`  
**Authorization**: `ScoutPolicy#show?` (Any authenticated account member: Agent, Administrator, Custom Role)  

---

## 1. Request

### HTTP Request
```http
GET /api/v1/accounts/{account_id}/scout_overview_reports/conversations?scout_id=1&range=7&timezone_offset=-3&status=all&page=1&per_page=25 HTTP/1.1
Host: example.com
api_access_token: <token>
Content-Type: application/json
```

### URL Parameters
| Parameter | Type | Required | Description |
|---|---|---|---|
| `account_id` | Integer | Yes | The current account ID |

### Query Parameters
| Parameter | Type | Required | Default | Allowed Values / Validation |
|---|---|---|---|---|
| `scout_id` | Integer | Yes | — | ID of the Scout belonging to `account_id`. |
| `range` | String | Yes | — | `'7'`, `'30'`, `'this_month'`, `'last_month'`. |
| `timezone_offset` | String \| Number | No | Server TZ | Timezone offset in hours (e.g. `"-3"` or `"-3.0"`). |
| `status` | String | No | `'all'` | `'all'`, `'qualified'`, `'disqualified'`, `'abandoned'`, `'in_progress'`, `'transferred_without_opportunity'`. |
| `page` | Integer | No | `1` | Integer >= 1. |
| `per_page` | Integer | No | `25` | Integer between 1 and 100. |

---

## 2. Response (200 OK)

### Response Body Structure
```json
{
  "conversations": [
    {
      "id": 1052,
      "display_id": 482,
      "contact": {
        "id": 89,
        "name": "Maria Silva",
        "identifier": "+5511987654321",
        "email": "maria@example.com",
        "phone_number": "+5511987654321",
        "thumbnail": "https://example.com/avatar.png"
      },
      "inbox": {
        "id": 14,
        "name": "WhatsApp SDR",
        "channel_type": "Channel::Whatsapp"
      },
      "start_at": 1773662400,
      "duration_seconds": 245,
      "messages_count": 6,
      "status": "qualified",
      "opportunity": {
        "id": 312,
        "title": "Deal — Maria Silva",
        "stage_id": 5
      }
    }
  ],
  "status_counts": {
    "all": 48,
    "qualified": 18,
    "disqualified": 12,
    "abandoned": 6,
    "in_progress": 7,
    "transferred_without_opportunity": 5
  },
  "pagination": {
    "current_page": 1,
    "total_count": 48,
    "per_page": 25,
    "total_pages": 2
  }
}
```

### Field Definitions

#### `conversations[]`
- `id`: (Integer) Internal database ID of the conversation.
- `display_id`: (Integer) Display number used in the Chatwoot interface.
- `contact`: (Object) Summary information for the primary contact.
  - `id`: (Integer) Contact ID.
  - `name`: (String) Contact name.
  - `identifier`: (String|null) External identifier if present.
  - `email`: (String|null) Contact email address if present.
  - `phone_number`: (String|null) Contact phone number if present.
  - `thumbnail`: (String|null) Avatar URL or null.
- `inbox`: (Object) Channel inbox details.
  - `id`: (Integer) Inbox ID.
  - `name`: (String) Inbox display name.
  - `channel_type`: (String) Channel classification.
- `start_at`: (Integer) Unix epoch timestamp of conversation creation.
- `duration_seconds`: (Integer|null) Difference in seconds between first and last message. `null` when `messages_count <= 1`.
- `messages_count`: (Integer) Total incoming and outgoing messages recorded.
- `status`: (String) Funnel disposition enum (`qualified`, `disqualified`, `abandoned`, `in_progress`, `transferred_without_opportunity`).
- `opportunity`: (Object|null) Associated deal record (`id`, `title`, `stage_id`) or `null` if no deal was created.

#### `status_counts`
Counts of conversations for each status within the active period and Scout:
- `all`: Total handled conversations in period.
- `qualified`: Conversations whose opportunity reached `scout.qualified_stage_id`.
- `disqualified`: Conversations whose opportunity reached `scout.unqualified_stage_id`.
- `abandoned`: Conversations whose opportunity reached `scout.rescue_stage_id`.
- `in_progress`: Conversations currently active without terminal disposition.
- `transferred_without_opportunity`: Conversations handed off to human queue with no deal created.

#### `pagination`
- `current_page`: (Integer) Active page number.
- `total_count`: (Integer) Total conversations matching the selected `status` filter.
- `per_page`: (Integer) Number of records per page (default 25).
- `total_pages`: (Integer) Total calculated pages.

---

## 3. Error Responses

### 401 Unauthorized
```json
{
  "error": "You need to sign in or sign up before continuing."
}
```

### 403 Forbidden
```json
{
  "error": "You are not authorized to perform this action"
}
```

### 422 Unprocessable Entity
- Missing or invalid `scout_id`:
```json
{
  "error": "scout_id is required"
}
```
- Invalid `range`:
```json
{
  "error": "range is invalid or missing"
}
```
