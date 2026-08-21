# API Contract: Scout Account Configuration

## 1. Endpoints

### 1.1. Get Account LLM Configuration
Retrieves the current account LLM configuration.

- **Method**: `GET`
- **URL**: `/api/v1/accounts/:account_id/scout_account_config`
- **Permissions**: Administrator only (`ScoutAccountConfigPolicy#show?`)

#### Response (Configured - 200 OK)
```json
{
  "provider": "gemini",
  "model_name": "gemini-2.5-flash",
  "has_api_key": true,
  "configured": true
}
```

#### Response (Not Configured - 200 OK)
```json
{
  "provider": null,
  "model_name": null,
  "has_api_key": false,
  "configured": false
}
```

---

### 1.2. Update Account LLM Configuration
Creates or updates the account LLM configuration, automatically verifying credentials before persisting.

- **Method**: `PATCH` / `PUT`
- **URL**: `/api/v1/accounts/:account_id/scout_account_config`
- **Permissions**: Administrator only (`ScoutAccountConfigPolicy#update?`)

#### Request Body
```json
{
  "scout_account_config": {
    "provider": "gemini",
    "model_name": "gemini-2.5-flash",
    "api_key": "AIzaSy..."
  }
}
```
*Note: If updating only `provider` or `model_name` when a key is already configured, `api_key` can be omitted or blank, keeping the existing key.*

#### Response (Success - 200 OK)
```json
{
  "provider": "gemini",
  "model_name": "gemini-2.5-flash",
  "has_api_key": true,
  "configured": true
}
```

#### Response (Invalid Key / Provider Failure - 422 Unprocessable Entity)
```json
{
  "error": "API Key is invalid or connection to provider failed: [error details]"
}
```

---

## 2. Frontend Client (`dashboard/api/scout.js`)

Updated methods on `ScoutAPI`:
```javascript
getAccountConfig() {
  const accountUrl = this.url.replace(/\/scouts$/, '');
  return axios.get(`${accountUrl}/scout_account_config`);
}

updateAccountConfig(data) {
  const accountUrl = this.url.replace(/\/scouts$/, '');
  return axios.patch(`${accountUrl}/scout_account_config`, {
    scout_account_config: data,
  });
}
```
*(Deprecates `getProviderSettings(scoutId)` and `updateProviderSettings(scoutId, data)`).*
