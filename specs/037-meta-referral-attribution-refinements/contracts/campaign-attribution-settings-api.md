# API Contract: Campaign Attribution Settings

**Endpoints**:
1. `GET /api/v1/accounts/:account_id/campaign_attribution_settings`
2. `PATCH /api/v1/accounts/:account_id/campaign_attribution_settings`
3. `POST /api/v1/accounts/:account_id/campaign_attribution_settings/connect`
4. `POST /api/v1/accounts/:account_id/campaign_attribution_settings/reprocess_pending`

---

## 1. `GET /api/v1/accounts/:account_id/campaign_attribution_settings`

Retrieves the current Meta Campaign Attribution integration settings and status.

### Request
- **Method**: `GET`
- **Headers**:
  - `api_access_token`: `<user_api_token>`
  - `Content-Type`: `application/json`

### Response (200 OK)
```json
{
  "enabled": true,
  "connected": true,
  "pending_count": 14,
  "meta_app_id": "123456789012345",
  "meta_api_version": "v22.0"
}
```

---

## 2. `POST /api/v1/accounts/:account_id/campaign_attribution_settings/reprocess_pending`

Manually triggers the drainage and reprocessing of all pending opportunities for the account.

### Request
- **Method**: `POST`
- **Headers**:
  - `api_access_token`: `<user_api_token>`
  - `Content-Type`: `application/json`

### Response (200 OK)
```json
{
  "message": "14 oportunidades pendentes foram enviadas para reprocessamento.",
  "count": 14
}
```

### Response (422 Unprocessable Entity - If not connected or disabled)
```json
{
  "error": "Campaign attribution cannot be reprocessed without an active Meta connection."
}
```
