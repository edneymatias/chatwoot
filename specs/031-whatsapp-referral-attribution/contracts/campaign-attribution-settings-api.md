# Contract: Campaign Attribution Settings API

Account-scoped REST resource, mirroring the shape of the existing
`Api::V1::Accounts::PipelineCurrencySettingsController`. Restricted to Account Administrators
(FR-018).

**Base path**: `/api/v1/accounts/:account_id/campaign_attribution_setting`

## GET (show)

Returns the account's current setting, creating an unpersisted default if none exists yet
(mirrors `PipelineCurrencySettingsController#show`'s `|| PipelineCurrencySetting.new(...)`
pattern — never 404s for an account that hasn't configured this yet).

**Response 200**:
```json
{
  "enabled": false,
  "connected": false
}
```

- `connected` is derived (not a raw DB column) — `true` only when `provider_config` holds a
  non-expired Meta access token. The raw token/expiry are never included in the response.

## PATCH/PUT (update)

**Request body** (either field optional, but see connection semantics below):
```json
{
  "enabled": true
}
```

To establish or refresh the Meta connection, a separate action is used (see below) rather than
accepting a raw token through this endpoint — keeps connection establishment (which involves an
external validation call to Meta) separate from the plain enable/disable toggle.

**Response 200**: same shape as GET.

**Response 422** (e.g. attempting to enable without a connected Meta account):
```json
{
  "error": "Campaign attribution cannot be enabled without a connected Meta account."
}
```

## POST (connect) — `/api/v1/accounts/:account_id/campaign_attribution_setting/connect`

The Account Administrator authenticates via Meta's Facebook JS SDK popup (`FB.login({ scope:
'ads_read' })`) in the frontend, configured against the Super-Admin-level `META_MARKETING_APP_ID`
(see `data-model.md`'s "Meta Marketing App Config" entity). The popup returns an authorization
`code` directly to the browser (no redirect/callback URL, no state/CSRF token — same mechanism as
the existing WhatsApp Embedded Signup popup, but against this feature's own independent Meta App
and backend service). The frontend POSTs that `code` here; the backend exchanges it server-side for
a short-lived, then long-lived (`grant_type=fb_exchange_token`), user access token via a new,
independent `Meta::MarketingAuthorizationService` (not `Whatsapp::EmbeddedSignupService` or
`Whatsapp::FacebookApiClient`), and persists the result in `provider_config`.

**Request body**:
```json
{ "code": "<oauth-authorization-code>" }
```

**Response 200**: same shape as GET, with `connected: true`.

**Response 422** on exchange/validation failure:
```json
{ "error": "Meta authorization failed." }
```

**`expires_at` is stored and tracked, and proactively refreshed.** Long-lived Facebook user access
tokens nominally last ~60 days, but `Meta::TokenRefreshJob` (daily Sidekiq-cron) re-exchanges any
token within ~10 days of `expires_at` via `grant_type=fb_exchange_token`, silently resetting the
60-day clock with no user interaction — see `research.md`'s "Master toggle + Meta connection storage
& access control" decision. If that job lapses for the full window, or Meta invalidates the token
out-of-band (e.g. a permissions review revokes it), the resolution job's next Graph API call fails
with a `401`/error code `190`; this MUST mark the affected Opportunities'
`campaign_resolution_status: failed` and flip this endpoint's `connected` flag to `false` on the
next `GET`, signaling the Administrator to reconnect via the popup again.

## Authorization contract

- All actions MUST 403 for any role other than Account Administrator (FR-018).
- Enforced via the existing Pundit `authorize` convention already used by sibling settings
  controllers (`PipelineCurrencySettingsController`, `PipelineClosingRequiredFieldsController`).
