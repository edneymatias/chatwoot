# Phase 0 Research: WhatsApp Referral (Facebook/Instagram Ad) Attribution

All items below were pre-resolved either by the approved source design
(`docs/kanban/ciclo 7/08-whatsapp-referral-attribution/spec26.md`), by the clarification session
recorded in `spec.md`, or by inspecting existing patterns already in this codebase. No open
`NEEDS CLARIFICATION` markers remain.

## Decision: Where campaign attribution capture lives

**Decision**: Extend `Custom::AutomationRules::ActionService#create_opportunity`
(`custom/app/services/custom/automation_rules/action_service.rb`) to read
`message.content_attributes['referral']` off the triggering message at the point of
`Opportunity.create!`, populating `campaign_source_id`, `campaign_source_url`, `campaign_platform`
(when derivable), and `campaign_resolution_status` synchronously.

**Rationale**: This is the single existing place in the codebase that creates an Opportunity from
a triggering message — matches Constitution Principle II (smallest change) and avoids introducing
a new listener or Conversation-level storage layer (explicitly out of scope per spec).

**Alternatives considered**: A new `message_created` event listener that pre-computes attribution
and stores it on the Conversation — rejected because it adds a persistence layer nothing else
needs and duplicates data that's already reachable from the triggering message at the moment of
Opportunity creation.

## Decision: Data storage shape

**Decision**: Seven new columns directly on `ichatr_opportunities` (fork-prefixed table, per
Constitution Principle I): `campaign_source_id`, `campaign_source_url`, `campaign_platform`,
`campaign_name`, `campaign_adset_name`, `campaign_ad_name`, `campaign_resolution_status`, plus a
partial index on `campaign_resolution_status` for the resolution job's polling/backfill queries.

**Rationale**: Campaign attribution is a general-purpose, flow-independent Opportunity attribute
(like `value`, already a dedicated column) — not scoped to a specific pipeline/stage the way
`custom_attributes` entries are. A migration under `db/migrate/` adding columns to an
already-fork-owned table is the allowed exception to Principle I's "no core table edits" rule
(the table itself is fork-owned, not upstream).

**Alternatives considered**: Folding attribution into the existing `custom_attributes` jsonb
column — rejected in the approved source design because it conflates a structural,
system-populated attribute with the account-configurable custom-attribute bucket used for
pipeline-specific fields.

## Decision: Async resolution job pattern (rate limiting + retries)

**Decision**: A new `Meta::RateLimiter` modeled directly on
`app/services/auto_assignment/rate_limiter.rb` (Redis sliding-window counter via
`Redis::Alfred.set`/`.keys_count`, `within_limit?`/`track_assignment`-shaped interface) for
proactive pacing, plus a `Meta::RateLimitError` wired through ActiveJob's native `retry_on`,
modeled on `app/jobs/data_imports/intercom/base_job.rb`'s `retry_on ... wait: 1.minute, attempts: N`
pattern, for reactive backoff. **The limiter's Redis counter key MUST include the Chatwoot
`account_id`** (e.g. `meta_rate_limiter:{account_id}`), not a single global counter — since
Chatwoot is multi-tenant and each account authenticates with its own independent Meta OAuth access
token, each account draws against its own independent Meta-side Business Use Case quota (per
`X-Business-Use-Case-Usage`, scoped per ad account/app-token pair). A global counter would
under-count real headroom (throttling account B's resolution work because of account A's traffic
against a completely different Meta token) or over-count it (letting one account's job burst past
what its own Meta-side quota actually allows once several accounts are active) — both wrong for a
per-tenant credential.

**Rationale**: Both patterns already exist in this codebase for the same class of problem
(external API pacing + retry-on-failure for a background enrichment job) — reusing them satisfies
Principle III (established conventions) and avoids inventing new infrastructure. Scoping the
counter key by `account_id` mirrors how `AutoAssignment::RateLimiter` itself is already scoped per
inbox/agent rather than global, so this isn't a new pattern, just applying the existing one at the
correct granularity for this feature's multi-tenant shape.

**Alternatives considered**: Sidekiq's built-in retry alone (no proactive limiter) — rejected
because it only reacts to 429s after they happen; the source design explicitly calls for
self-throttling ahead of hitting Meta's limits, given this ships against a live production ad
account.

## Decision: Resolution result caching (12-hour TTL, from clarification)

**Decision**: Cache resolved `{ campaign_name, campaign_adset_name, campaign_ad_name, platform }`
in Redis via `Redis::Alfred`, keyed by `campaign_source_id`, with a 12-hour expiry
(`Redis::Alfred.setex`-equivalent). The resolution job checks the cache before calling the Meta
Graph API; a hit populates the Opportunity directly without an external call, a miss (including
post-TTL-expiry) calls Meta and refreshes the cache.

**Rationale**: Directly resolves the clarification answer — avoids redundant Graph API calls when
many Opportunities share one ad, while the 12-hour expiry still lets renamed
campaigns/ad-sets/ads eventually surface with updated names. Redis (via `Redis::Alfred`) is the
existing convention for this kind of short-lived keyed cache in this codebase (see the rate
limiter above), rather than introducing `Rails.cache` as a second caching mechanism.

**Alternatives considered**: A dedicated ActiveRecord cache table — rejected as unnecessary
persistence for data that's inherently time-bound and reconstructible from Meta at any time.

**Multi-tenancy note**: unlike the rate limiter above, this cache key is intentionally left
**not** scoped by `account_id`. Meta ad ids (`campaign_source_id`) are globally unique across
Meta's entire platform, not just within one advertiser's ad account — two different Chatwoot
accounts cannot legitimately share the same `campaign_source_id` unless they are, in fact, both
referencing the exact same underlying Meta ad, in which case the resolved
name/adset/campaign/platform data is identical regardless of which account's token happened to
resolve it first. Keeping the cache global is therefore both safe and a (rare-case) efficiency
win, with no cross-tenant data leakage risk.

## Decision: Platform derivation fallback (from clarification)

**Decision**: `campaign_platform` derives synchronously from `source_url` (contains `instagram` →
`instagram`, else `facebook`) when `source_url` is present. When absent, the field is left unset
at capture time and the async resolution job additionally requests the ad's creative data — nested
one level deeper than originally assumed, since `effective_object_story_id`/`object_story_spec`
live on the **`AdCreative`** object, not directly on the `Ad` node — via `creative{
effective_object_story_id, object_story_spec}` in the same field-expansion call already fetching
`name`/`adset`/`campaign`, checking `object_story_spec` for an `instagram_actor_id` (→ `instagram`)
vs. a `page_id`-only reference (→ `facebook`), and fills in platform alongside the resolved names.

**Rationale**: Matches the clarification answer exactly — no additional API round trip, since the
data needed is obtainable from a broadened field selection on the resolution job's existing
Graph API call. **Validated** against Meta's official Ad (`adgroup`) object reference: nested field
expansion of the shape `GET /v25.0/<AD_ID>/?fields=name,adset{id,name},campaign{id,name},
creative{effective_object_story_id,object_story_spec}` is explicitly supported syntax — confirms
the resolution call shape proposed here and in "Decision: Where campaign attribution capture
lives" is correct, with the one correction that creative fields must be nested under `creative{}`
rather than requested top-level.

**Alternatives considered**: A separate insights/placements API call using the `publisher_platform`
breakdown — rejected as needless extra API surface and rate-limit pressure for a fallback path
expected to be rare (Part 1's validated payloads on both WhatsApp numbers always carried
`source_url`); confirmed via research that `publisher_platform` insights breakdown is the only
other viable signal, and it is strictly more expensive (a separate Insights call) than the chosen
`object_story_spec` inspection folded into the existing lookup.

## Decision: Realtime UI update path

**Decision**: Route `Opportunity#broadcast_opportunity_updated` through
`Rails.configuration.dispatcher.dispatch('opportunity_updated', ...)` →
`Custom::ActionCableListener#opportunity_updated` (new file under `custom/app/listeners/custom/`)
instead of calling `ActionCableBroadcastJob.perform_later` directly, and have the resolution job
fire the same event on completion.

**Rationale**: `ActionCableListener` and `AutomationRule` already carry a trailing
`prepend_mod_with('X')` extension point wired into Chatwoot core — routing both the model's
existing broadcast and the new resolution job's broadcast through this standard
event-dispatch pattern needs zero core file changes (Constitution Principle I) and avoids having
two different broadcast mechanisms for the same event type.

**Alternatives considered**: Job calls `ActionCableBroadcastJob` directly, duplicating the model's
existing ad-hoc call — rejected; would leave two divergent broadcast code paths for the same
logical event.

**Frontend impact**: None. `app/javascript/dashboard/helper/actionCable.js` already listens for
`opportunity_updated` and dispatches `opportunities/updateOpportunity` (added in a prior phase,
commit `0eab699cf`) — it is unaffected by which backend code path triggers the broadcast, as long
as the event name and payload shape are preserved.

## Decision: Automation condition implementation

**Decision**: Additive touches across four existing files plus i18n, mirroring the existing
`private_note` boolean condition end-to-end:
- `lib/filters/filter_keys.yml`: new `campaign_referral_present` entry under `messages:`
  (`attribute_type: standard`, `data_type: boolean`, `equal_to`/`not_equal_to` operators).
- `app/services/automation_rules/conditions_filter_service.rb#message_query_string`: one new
  branch building a presence-check SQL fragment (`messages.content_attributes -> 'referral' IS NOT
  NULL`) compared against the boolean filter value, following the same
  `attribute_key`-remapping pattern already used for `content`/`private_note`.
- `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js`: new entry in
  `AUTOMATIONS.message_created.conditions`, mirroring the `private_note` entry shape
  (`inputType: 'search_select'`, `filterOperators: OPERATOR_TYPES_1`).
- `app/javascript/dashboard/helper/automationHelper.js#conditionFilterMaps`: new
  `campaign_referral_present: booleanFilterOptions` entry, mirroring `private_note`.
- `en.yml`/`pt_BR.yml` (backend) and `en.json`/`pt_BR.json` (frontend): new condition label.

**Rationale**: `referral` is raw JSON on `Message.content_attributes`, not an account-defined
`CustomAttributeDefinition`, so it can't ride the existing dynamic `custom_attribute_query` path —
this is genuinely additive core-file surface area, the one deliberate exception to Principle I's
extension-point preference (there is no existing extension point for automation condition
filters). Kept intentionally minimal: one boolean presence check, nothing else.

**Alternatives considered**: Modeling `campaign_referral_present` as a virtual/computed custom
attribute — rejected; custom attributes are account-configurable and contact/conversation-scoped
by convention, not a fit for a system-computed message-level boolean.

## Decision: Master toggle + Meta connection storage & access control

**Superseded note**: An earlier iteration of this decision (see prior git history of this file)
proposed a pasted, non-expiring Meta **System User Access Token** in place of OAuth, on the
grounds that OAuth user tokens expire and that Meta's Marketing API has no "embedded signup"
equivalent. That reasoning is still technically accurate, but it optimized for token
lifetime/reliability over the product shape actually wanted for this feature. The decision below
supersedes it: this feature deliberately mirrors the **two-tier connection shape** already used by
WhatsApp Embedded Signup in this product (a Super-Admin-level app credential, plus a per-account
OAuth consent step) — but built as fully independent, parallel code, sharing no models, services,
controllers, or config keys with the WhatsApp integration. The token-expiry tradeoff this
reintroduces is called out explicitly below rather than re-litigated.

**Decision**: Two-tier configuration, split by actor, replicating the *shape* of the existing
WhatsApp Cloud Embedded Signup config pattern without reusing any of its code or config keys:

1. **Super Admin (instance-level) — Meta App credentials.** A new, independent config section is
   added to `config/installation_config.yml` (`META_MARKETING_APP_ID`, `META_MARKETING_APP_SECRET`,
   `META_MARKETING_API_VERSION`, default `v22.0`), persisted per-instance in the existing
   `InstallationConfig` model and read at runtime via `GlobalConfigService.load('META_MARKETING_APP_ID',
   ...)` etc. A new `'meta_marketing'` entry is added to the `mapping` hash in
   `app/controllers/super_admin/app_configs_controller.rb#allowed_configs`, alongside the existing
   `'whatsapp_embedded'`, `'slack'`, `'notion'`, `'tiktok'` entries. This rides the same generic,
   channel-agnostic Super Admin App Config mechanism every integration in this codebase already
   uses independently (each with its own distinct key names and no shared code between them) — it
   is shared infrastructure, not WhatsApp-specific code, so adding a new key set here does not
   create a dependency on the WhatsApp integration.
2. **Account Administrator (per-account) — OAuth consent for ad-data access.** Within the new
   `ichatr_campaign_attribution_settings` row (one per account, modeled on `PipelineCurrencySetting`
   exactly as before — `belongs_to :account`, `validates :account_id, uniqueness: true`, wired onto
   `Account` via `Custom::Concerns::Account`), the Account Administrator authenticates with their
   own Facebook account to grant `ads_read` access to their ad data. The frontend uses Meta's
   Facebook JS SDK popup (`FB.login({ scope: 'ads_read' })`) — the same *mechanism* Embedded Signup
   uses (a client-side popup that returns an authorization `code` directly to the browser, no
   server-side redirect/callback URL, no state/CSRF token machinery), configured against the
   Super-Admin-level `META_MARKETING_APP_ID` from step 1. The popup's `code` is POSTed to a new
   `connect` action on `Api::V1::Accounts::CampaignAttributionSettingsController`
   (`show`/`update`/`connect`), which performs the code→token exchange server-side.
   `provider_config` (jsonb) stores `{ "access_token" => "<long-lived-token>", "expires_at" =>
   "<timestamp>" }`.

Both tiers are entirely new, independent code: a new config section (not the WhatsApp one), a new
`allowed_configs` group (not `whatsapp_embedded`), and a new service — e.g.
`custom/app/services/meta/marketing_authorization_service.rb` — performing the Graph API
`code`→short-lived-token→long-lived-token exchange against `META_MARKETING_APP_ID`/
`META_MARKETING_APP_SECRET`, independent of `Whatsapp::FacebookApiClient` and
`Whatsapp::EmbeddedSignupService` (neither is reused, extended, or called into).

**Rationale**: Matches the user's explicit direction: replicate the *pattern* (Super Admin sets app
credentials once, instance-wide; each Account Administrator separately consents via their own
Facebook login) without depending on or reusing any existing WhatsApp/upstream code for it. The
Super-Admin-level config piece reuses only the codebase's generic, already-shared
`installation_config.yml`/`GlobalConfigService`/`allowed_configs` mechanism — the same mechanism
Slack, Notion, TikTok, and every other integration already uses independently — not anything
WhatsApp-specific. The OAuth consent step reuses only the general *mechanism* Meta's JS SDK popup
provides (also usable by any Meta product), not any WhatsApp-specific controller, service, or
config key.

**Tradeoff made explicit (token lifetime), and how it's mitigated**: a Facebook user access token,
even after the standard short-lived → 60-day long-lived exchange (`grant_type=fb_exchange_token`),
still has a hard ceiling — there is no separate OAuth `refresh_token` grant for this token type.
However, Meta does allow an already-long-lived token (≥24h old, not yet expired) to be re-submitted
through that same `fb_exchange_token` exchange to obtain a fresh token with the 60-day clock reset,
with no user interaction required. A new scheduled job, `Meta::TokenRefreshJob` (Sidekiq-cron,
daily), sweeps all `CampaignAttributionSetting` rows with a non-empty `provider_config` and calls
this exchange for any token within ~10 days of `expires_at`, silently extending the connection
indefinitely as long as the job keeps running. Re-consent (via the `FB.login` popup again) is only
required if: the refresh job itself fails/is skipped for the full ~60-day window (an operational
issue, not expected in normal operation), or Meta/the user invalidates the token out-of-band
(password change, permission review, app access revoked) — both cases are already handled by the
existing `OAuthException` → `campaign_resolution_status: failed` + `connected: false` fallback,
which remains the Administrator-facing signal to reconnect. This lands close to the System User
token's "no periodic reauth" property while keeping the OAuth-popup UX consistency the two-tier
shape was chosen for.

**Alternatives considered**: The previously-documented pasted System User Access Token flow —
rejected per the user's explicit direction to mirror the existing product's Super-Admin-app +
per-account-OAuth shape rather than a manually-generated, pasted-token flow, even though the System
User token has a better lifetime profile. Reusing `Whatsapp::EmbeddedSignupService`,
`Whatsapp::FacebookApiClient`, the `WHATSAPP_APP_ID`/`WHATSAPP_APP_SECRET`/`WHATSAPP_API_VERSION`
config keys, or `whatsapp/authorizations_controller.rb` directly — rejected per the user's explicit
"don't depend on upstream" instruction; this feature's Super-Admin config keys, `allowed_configs`
group, controller action, and authorization service are all new and independent. Reusing
`Channel::Whatsapp#provider_config` itself for the Meta Marketing token — rejected; the spec
requires this connection be a separate configuration surface from the WhatsApp Cloud embedded-signup
config (FR-014), and it now also uses fully independent Meta App credentials, not the WhatsApp
integration's app id/secret.

## Decision: Settings UI placement

**Decision**: A new section/tab within the existing Pipeline settings screen
(`app/javascript/dashboard/routes/dashboard/settings/pipelineStages/Index.vue`), placed alongside
(or within) the existing "Card Fields" tab (`CardFieldConfig.vue`, tab index 0) — per the user's
stated preference that this belongs with card/pipeline setup, since resolved campaign data
surfaces on the Opportunity card. Exact sub-placement (new tab vs. new section inside the existing
tab) is left to implementation, consistent with the spec's Assumptions section.

**Rationale**: Matches the clarification session's recorded placement preference and reuses the
existing `SettingsLayout` + `TabBar` pattern already present in this file, requiring no new
settings-screen scaffolding.

## Decision: Backfill task shape

**Decision**: `lib/tasks/campaign_attribution.rake`, task `campaign_attribution:backfill`, using
`Opportunity.where(campaign_resolution_status: nil).where.not(origin_conversation_id: nil)
.find_each` in batches, calling the same synchronous-capture method extracted from
`ActionService#create_opportunity` (so capture logic is not duplicated), then enqueueing the same
resolution job used by the real-time path per Opportunity where data was found. Per-account gate
checks the new settings table's `enabled` flag before processing that account's Opportunities.

**Rationale**: Matches the approved source design's backfill section exactly; reusing the
extracted capture method and the same resolution job means the rate limiter/cache introduced above
paces the backfill automatically, with no separate throttling logic needed in the rake task
itself.

## Summary: Technical Context resolution

| Item | Resolution |
|---|---|
| Language/Version | Ruby (Rails, existing app version) for backend; Vue 3 (Composition API, `<script setup>`) for frontend — matches existing stack, no new language introduced |
| Primary Dependencies | `HTTParty` (already used by `Whatsapp::FacebookApiClient`) for Meta Graph API calls; `Redis::Alfred` for rate limiting and the resolution cache; Sidekiq (`low` queue) for the async job; ActionCable (existing dispatcher/listener pattern) for realtime UI updates |
| Storage | PostgreSQL — new columns on `ichatr_opportunities`, new `ichatr_campaign_attribution_settings` table; Redis for rate-limiter counters and the 12-hour resolution cache (ephemeral, not source of truth) |
| Testing | RSpec (backend), `pnpm test`/Vitest (frontend) — existing suites, per `CLAUDE.md` |
| Target Platform | Existing Chatwoot web app (Rails + Vue SPA), containerized dev stack per `CLAUDE.md` |
| Project Type | Web application (existing monolith: `app/`, `custom/`, `app/javascript/dashboard`) |
| Performance Goals | SC-002: ≥95% of eligible Opportunities resolved within 10 minutes; SC-006: zero measurable delay to Opportunity creation from resolution work |
| Constraints | Must self-throttle against Meta Marketing API rate limits (SC-004); must not touch enterprise-gated code paths (Kanban module is fork-only, not upstream/enterprise surface) |
| Scale/Scope | Multi-tenant by default: a Super Admin configures one instance-wide Meta App (`META_MARKETING_APP_ID`/`SECRET`), and every Chatwoot account independently connects via its own Account-Administrator-driven OAuth consent into its own `CampaignAttributionSetting` row (see data-model.md). Per-release limit is narrower — one Meta ad account per Chatwoot account (per spec Assumptions) |
