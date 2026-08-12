# Phase 1 Data Model: WhatsApp Referral (Facebook/Instagram Ad) Attribution

## Entity: Opportunity (extended)

Existing model: `custom/app/models/opportunity.rb`, table `ichatr_opportunities`. Adds seven
new columns — all nullable, all independent of pipeline/stage configuration.

| Field | Type | Populated | Notes |
|---|---|---|---|
| `campaign_source_id` | `string` | Synchronously, at creation | Raw Meta ad id from `message.content_attributes['referral']['source_id']`. Also the resolution cache key. |
| `campaign_source_url` | `string` | Synchronously, at creation | Raw `referral['source_url']`. Used to derive `campaign_platform` when present. |
| `campaign_platform` | `string` (`facebook` \| `instagram` \| `null`) | Synchronously if derivable from `source_url`; otherwise asynchronously by the resolution job | `null` only in the transient window between capture (no `source_url`) and resolution completing. |
| `campaign_name` | `string` | Asynchronously, by the resolution job | From Meta Graph API `campaign.name`. |
| `campaign_adset_name` | `string` | Asynchronously, by the resolution job | From Meta Graph API `adset.name`. |
| `campaign_ad_name` | `string` | Asynchronously, by the resolution job | From Meta Graph API `name` (the ad itself). |
| `campaign_resolution_status` | `string` enum: `not_applicable` \| `pending` \| `resolved` \| `failed` | Both stages | See state machine below. Partial index on this column for the resolution job's polling query and the backfill task's scope query. |

### State machine: `campaign_resolution_status`

```
not_applicable  ── (no referral data on triggering message; terminal, majority of Opportunities)

pending  ── (referral data present at capture; synchronous fields set)
  │
  ├─→ resolved  ── (resolution job succeeds; campaign_name/adset_name/ad_name populated)
  │
  └─→ failed  ── (resolution job's retries exhausted; raw source_id/platform remain as fallback)
```

- `not_applicable` is set once, at Opportunity creation, and never transitions — it is the default
  for the vast majority of Opportunities unrelated to ad campaigns.
- `pending` → `resolved`/`failed` is driven exclusively by the resolution job (real-time or
  backfill-enqueued); no other code path changes this status.
- There is no `resolved`/`failed` → `pending` transition in v1 (no manual retry, per spec
  Assumptions) — a `failed` Opportunity stays `failed` until the backfill task or a future manual
  retry feature re-enqueues it.

### Validation

- No new presence/uniqueness validations on the campaign fields themselves (all nullable,
  independent of the existing `title`/`contact_id`/`pipeline_stage_id`/`account_id` presence
  validations already on `Opportunity`).
- `campaign_resolution_status` MUST be one of the four enum values above; invalid values are a
  programmer error (setup/deployment bug per `CLAUDE.md` guidance), not a case to silently guard.

## Entity: Campaign Attribution Setting (new)

New model `CampaignAttributionSetting`, table `ichatr_campaign_attribution_settings`, one row per
account — modeled directly on `PipelineCurrencySetting`.

| Field | Type | Notes |
|---|---|---|
| `account_id` | `bigint`, FK, unique | `belongs_to :account`; `validates :account_id, uniqueness: true` |
| `enabled` | `boolean`, default `false` | The master toggle (FR-013). Gates async resolution + backfill only — synchronous capture is unconditional. |
| `provider_config` | `jsonb`, default `{}` | Holds `{ "access_token" => "<long-lived-user-token>", "expires_at" => "<timestamp>" }` — obtained via the Account Administrator's own Facebook OAuth consent (`ads_read` scope), exchanged server-side by `Meta::MarketingAuthorizationService` against the Super-Admin-configured `META_MARKETING_APP_ID`/`SECRET` (see `research.md`). The long-lived token nominally expires (~60 days), but `Meta::TokenRefreshJob` (daily Sidekiq-cron) proactively re-exchanges it before expiry, resetting the 60-day clock without user interaction — reconnection is only needed if that job lapses or Meta invalidates the token out-of-band. A resolution job call that hits an `OAuthException` flips `campaign_resolution_status: failed` and surfaces `connected: false` on this record, prompting the Administrator to reconnect. Mirrors `Channel::Whatsapp#provider_config`'s jsonb *convention* only — a fully separate configuration surface, storing tokens issued against fully independent Meta App credentials (FR-014). |
| `created_at`/`updated_at` | timestamps | Standard. |

Wired onto `Account` via `custom/app/models/custom/concerns/account.rb`:
`has_one :campaign_attribution_setting, dependent: :destroy`.

Access control: `show`/`update`/`connect` restricted to Account Administrators, via the same
`authorize`/Pundit-policy convention already used by `PipelineCurrencySettingsController`.

## Entity: Meta Marketing App Config (new, Super Admin / instance-level)

Not a new database table — three new keys declared in `config/installation_config.yml`
(`META_MARKETING_APP_ID`, `META_MARKETING_APP_SECRET`, `META_MARKETING_API_VERSION`, default
`v22.0`), persisted per-instance in the existing core `InstallationConfig` model (one row per key,
shared by every integration's Super Admin config) and read at runtime via
`GlobalConfigService.load('META_MARKETING_APP_ID', ...)`. Managed through the existing generic
Super Admin App Config UI/endpoint under a new `'meta_marketing'` config group (added to
`allowed_configs` in `app/controllers/super_admin/app_configs_controller.rb`, plus a matching
`meta_marketing` entry in `app/helpers/super_admin/features.yml` so a "Meta Marketing" link appears
in the Super Admin Settings sidebar), the same mechanism already used independently by `'slack'`,
`'notion'`, `'tiktok'`, `'whatsapp_embedded'`, etc. — no new bespoke model, controller, or table
for this entity; it rides existing shared infrastructure with a new, independent key set. See `research.md`'s "Decision: Master toggle + Meta connection
storage & access control".

| Field (installation_config.yml `name`) | Notes |
|---|---|
| `META_MARKETING_APP_ID` | Meta App ID used for the OAuth popup (`FB.login`) and server-side token exchange. |
| `META_MARKETING_APP_SECRET` | Meta App Secret used for server-side code→token exchange. |
| `META_MARKETING_API_VERSION` | Graph API version prefix (e.g. `v22.0`), independently configurable from `WHATSAPP_API_VERSION`. |

Instance-wide, not account-scoped — set once by a Super Admin, shared by every Chatwoot account's
own OAuth consent step.

## Entity: Campaign Referral Data (existing, read-only for this feature)

Not a new persisted entity — the structured signal already present on
`Message#content_attributes['referral']` (Part 1, prior work). Documented here only for its
consumed shape:

```
content_attributes.referral = {
  source_id: string,       # Meta ad id — becomes campaign_source_id
  source_type: string,     # "ad"
  source_url: string,      # becomes campaign_source_url; derives campaign_platform
  headline: string,        # not persisted onto Opportunity
  body: string,             # not persisted onto Opportunity
  media_type: string,       # not persisted onto Opportunity
  image_url: string          # not persisted onto Opportunity
}
```

## Entity: Campaign Resolution Cache Entry (Redis, ephemeral — not a DB entity)

Keyed by `campaign_source_id`, stored via `Redis::Alfred`, TTL 12 hours.

| Field | Type |
|---|---|
| `campaign_name` | string |
| `campaign_adset_name` | string |
| `campaign_ad_name` | string |
| `campaign_platform` | string (`facebook`/`instagram`), only when derived asynchronously |

Not the source of truth — always mirrored onto whichever Opportunity row(s) triggered or reused
the cache entry. Expiry causes the next resolution to re-query Meta and overwrite the entry (also
the mechanism by which renamed campaigns/ad-sets/ads eventually surface, per clarification).

## Entity: Automation Rule Condition (extended, no new table)

Existing `AutomationRule` condition JSON gains one new valid `attribute_key`:
`campaign_referral_present`, `attribute_type: standard`, `data_type: boolean`, scoped to the
`message_created` trigger's `messages:` filter group in `lib/filters/filter_keys.yml`. No schema
change — this is a filter-key/condition-evaluation addition, not a new persisted entity.

## Relationships

```
InstallationConfig (META_MARKETING_APP_ID/SECRET/API_VERSION)  ──(read via GlobalConfigService)──▶  Meta::MarketingAuthorizationService
Account 1───1 CampaignAttributionSetting   (has_one, dependent: :destroy)
Account 1───* Opportunity                   (existing)
Opportunity *───1 Conversation (origin_conversation, optional)  (existing)
Conversation 1───* Message                  (existing)
Message.content_attributes['referral']  ──(read at creation)──▶  Opportunity.campaign_* columns
Opportunity.campaign_source_id  ──(cache key)──▶  Redis Campaign Resolution Cache Entry
```
