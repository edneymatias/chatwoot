# Implementation Plan: WhatsApp Referral (Facebook/Instagram Ad) Attribution

**Branch**: `031-whatsapp-referral-attribution` | **Date**: 2026-08-11 | **Spec**:
[spec.md](./spec.md)

**Input**: Feature specification from `/specs/031-whatsapp-referral-attribution/spec.md`

## Summary

Turn the already-validated CTWA `referral` signal on inbound WhatsApp messages (both Cloud API and
Evolution API paths, Part 1 — resolved) into visible, actionable attribution on Opportunities:
seven new columns on `ichatr_opportunities` populated synchronously (raw id/URL/platform) at
Opportunity creation and asynchronously (resolved campaign/ad-set/ad names, with 12-hour
per-ad-id caching to avoid redundant Meta API calls) by a rate-limited, retrying Sidekiq job; a
realtime card update routed through the existing dispatcher/listener extension point; a new
boolean `campaign_referral_present` automation condition so rule authors stop relying on fragile
suggested-message text matching; a one-time idempotent backfill rake task for pre-existing
Opportunities; and a new, two-tier connection surface fully independent of the existing WhatsApp
Cloud embedded-signup config: a Super-Admin-configured, instance-wide Meta App credential (new
`META_MARKETING_*` keys, own `allowed_configs` group), and an Account-Administrator-only per-account
OAuth `ads_read` consent (master toggle + Meta connection), placed alongside the existing Card
Fields settings tab per the user's stated preference.

## Technical Context

**Language/Version**: Ruby (Rails, existing app version) backend; Vue 3 (Composition API,
`<script setup>`) frontend — no new language/runtime introduced.

**Primary Dependencies**: `HTTParty` (existing, via `Whatsapp::FacebookApiClient`-style client)
for Meta Graph API calls; `Redis::Alfred` for rate limiting and the 12-hour resolution cache;
Sidekiq `low` queue for async resolution; existing `Rails.configuration.dispatcher` /
`ActionCableListener` pattern for realtime broadcast; Pundit for authorization.

**Storage**: PostgreSQL — 7 new columns on `ichatr_opportunities`, new
`ichatr_campaign_attribution_settings` table (one row per account). Redis — ephemeral rate-limiter
counters and the 12-hour resolution cache (ephemeral, ephemeral by design; never the source of
truth).

**Testing**: RSpec (backend), `pnpm test` / Vitest (frontend) — existing suites and conventions
per `CLAUDE.md`; specs written only where they materially cover new logic (capture, resolution job
state transitions, condition filter SQL, backfill idempotency), per the "avoid writing specs
unless explicitly asked" project guideline balanced against `CLAUDE.md`'s existing Ruby/JS test
commands being the standard verification path for backend/frontend changes.

**Target Platform**: Existing Chatwoot web app (Rails + Vue SPA), containerized dev stack.

**Project Type**: Web application (existing monolith — `app/`, `custom/` fork-specific tree,
`app/javascript/dashboard`).

**Performance Goals**: SC-002 (≥95% resolved within 10 minutes under normal conditions), SC-006
(zero measurable Opportunity-creation latency added by resolution).

**Constraints**: Must self-throttle against Meta Marketing API rate limits against a live
production ad account (SC-004); Kanban/Opportunity module is fork-only (`custom/`), not an
upstream or `enterprise/` surface, so Constitution Principle V (Dual-Tree Awareness) does not
apply to this feature's own new code — it only applies to the four existing-core-file touches
listed below.

**Scale/Scope**: Multi-tenant by default — a Super Admin configures one instance-wide Meta App
credential (`META_MARKETING_APP_ID`/`SECRET`/`API_VERSION`), and every Chatwoot account
independently connects and manages its own Meta OAuth-authenticated token via its own
`CampaignAttributionSetting` row (one per account, per `data-model.md`). The per-release scope
limit is narrower: each Chatwoot account connects a single Meta ad account (an account managing
multiple Meta ad accounts simultaneously is out of scope per spec Assumptions). `Meta::RateLimiter`
and the 12-hour resolution cache must account for this — see `research.md`'s "Decision: Async
resolution job pattern" and "Decision: Resolution result caching".

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design below.*

### I. Upstream Compatibility First

- **Opportunity model/columns, new settings table/model, resolution job, rate limiter, cache,
  backfill rake task, settings controller/UI**: all new files under `custom/` (or new columns on
  an already-fork-owned `ichatr_`-prefixed table) — fully isolated, zero core file edits. **PASS**.
- **Realtime broadcast refactor**: `Opportunity#broadcast_opportunity_updated` changes from a
  direct `ActionCableBroadcastJob.perform_later` call to
  `Rails.configuration.dispatcher.dispatch(...)`. This edits one existing core-adjacent
  fork-owned file (`custom/app/models/opportunity.rb`, already a `custom/` file, not upstream) —
  no core file touched; the new listener lives at
  `custom/app/listeners/custom/action_cable_listener.rb`, riding the existing
  `prepend_mod_with('X')` extension point on `ActionCableListener`. **PASS**.
- **Automation condition** (`lib/filters/filter_keys.yml`,
  `app/services/automation_rules/conditions_filter_service.rb`,
  `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js`,
  `app/javascript/dashboard/helper/automationHelper.js`): genuinely edits four existing core
  files, each with a small, additive change (one new YAML entry, one new `case`/branch, one new
  array entry, one new map entry) mirroring the existing `private_note` boolean condition exactly.
  There is no existing extension point for automation condition filters (`custom_attribute_query`
  only covers account-defined `CustomAttributeDefinition`s, not raw message JSON). **Flagged
  below in Complexity Tracking as the one deliberate, justified exception.**
- **`Custom::Concerns::Account`**: adding `has_one :campaign_attribution_setting` to this
  already-existing fork concern file is itself a `custom/` file edit, not a core edit — no change
  needed to `Account.include_mod_with('Concerns::Account')` in `app/models/account.rb` (already
  wired). **PASS**.
- **Super-Admin Meta App config** (`config/installation_config.yml`,
  `app/controllers/super_admin/app_configs_controller.rb`,
  `app/helpers/super_admin/features.yml`): three small, additive core-file touches —
  a new config section (three new `META_MARKETING_*` keys), a new `'meta_marketing'` entry in
  the existing `allowed_configs` mapping, and a new `meta_marketing` entry in `features.yml` (the
  same file that already drives the "WhatsApp Embedded"/"Slack"/"Notion" links in the Super Admin
  Settings sidebar) so a "Meta Marketing" link appears there too. All three files are shared,
  channel-agnostic infrastructure already extended independently by every integration in the
  codebase (WhatsApp, Slack, Notion, TikTok, etc.) — this feature adds its own entries alongside
  theirs, without editing or depending on any existing integration's keys/entries. **Flagged below
  in Complexity Tracking as a second, minor, precedented exception.**
- **OAuth connection flow** (Meta App JS SDK popup + `connect` controller action +
  `Meta::MarketingAuthorizationService`): fully new, independent code under `custom/` — does not
  call, extend, or share config keys with `Whatsapp::EmbeddedSignupService`,
  `Whatsapp::FacebookApiClient`, or `whatsapp/authorizations_controller.rb`. **PASS**.
- **`Meta::TokenRefreshJob` cron registration** (`config/schedule.yml`): one small, additive
  core-file touch — a new top-level entry (`class: Meta::TokenRefreshJob`) in the existing
  `sidekiq-cron`-format schedule file loaded by `config/initializers/sidekiq.rb`. There is no
  extension point for registering additional cron jobs from `custom/` — `config/schedule.yml` is a
  single hardcoded file with no merge/include mechanism, and no existing entry in it references
  `custom/`, `Meta::`, or `Whatsapp::` namespaces (confirmed via inspection), meaning this is the
  first fork-owned job registered here. **Flagged below in Complexity Tracking as a third, minor
  exception.**

### II. Smallest Production-Ready Change

- Capture logic added at the single existing creation point
  (`Custom::AutomationRules::ActionService#create_opportunity`) rather than a new listener/storage
  layer. Resolution job, rate limiter, and cache each reuse an existing in-repo pattern rather than
  introducing new infrastructure. No speculative fields, no manual-retry UI, no multi-account
  token management (all explicitly deferred per spec). **PASS**.

### III. Adhere to Established Conventions

- RuboCop/ESLint/Tailwind/Composition API/i18n conventions apply unchanged; new Vue additions to
  the settings screen extend the existing `SettingsLayout`/`TabBar` pattern already in
  `pipelineStages/Index.vue`. New i18n keys added to `en.yml`/`en.json` and `pt_BR.yml`/
  `pt_BR.json` synchronously (per `CLAUDE.md` — this fork ships pt-BR translations directly,
  unlike upstream's Crowdin flow). **PASS**.

### IV. Safe, Reversible Change Management

- All new tables/columns are additive (no drops/renames of existing columns). Backfill rake task
  is read-scoped + idempotent, no destructive operations. Master toggle defaults to `enabled:
  false`, so the feature is inert until an Administrator explicitly opts in. **PASS**.

### V. Dual-Tree Awareness (OSS + Enterprise)

- Not applicable to the new fork-specific code (Kanban/Opportunity module has no
  `enterprise/` counterpart). The four core files touched by the automation condition
  (filter_keys.yml, conditions_filter_service.rb, constants.js, automationHelper.js) are OSS-only
  automation infrastructure with no enterprise-specific override for message-created conditions
  found during research — confirmed no `enterprise/` equivalent of these four files exists.
  **PASS** (no enterprise override needed).

**Overall gate result**: PASS, with three recorded exceptions (automation condition core-file
edits; Super-Admin Meta App config core-file touches; `config/schedule.yml` cron registration)
justified in Complexity Tracking below.

## Project Structure

### Documentation (this feature)

```text
specs/031-whatsapp-referral-attribution/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md         # Phase 1 output
├── quickstart.md         # Phase 1 output
├── contracts/            # Phase 1 output
│   ├── campaign-attribution-settings-api.md
│   ├── opportunity-updated-event.md
│   └── automation-condition-filter.md
└── tasks.md              # Phase 2 output (/speckit-tasks — not created here)
```

### Source Code (repository root)

```text
db/migrate/
├── <ts>_add_campaign_attribution_to_ichatr_opportunities.rb
└── <ts>_create_ichatr_campaign_attribution_settings.rb

config/installation_config.yml                       # extend: new META_MARKETING_* keys (own section, independent of WHATSAPP_*)

app/controllers/super_admin/
└── app_configs_controller.rb                         # extend: allowed_configs gains 'meta_marketing' group

app/helpers/super_admin/features.yml                  # extend: new meta_marketing entry (Settings sidebar link)

custom/app/models/
├── opportunity.rb                                  # extend: expose new columns in as_json / broadcast payload
├── campaign_attribution_setting.rb                 # new
└── custom/concerns/account.rb                      # extend: has_one :campaign_attribution_setting

custom/app/services/custom/automation_rules/
└── action_service.rb                               # extend: create_opportunity captures referral synchronously

custom/app/services/                                # new namespace for this feature
└── meta/
    ├── rate_limiter.rb                              # new, modeled on AutoAssignment::RateLimiter
    ├── rate_limit_error.rb                          # new
    ├── campaign_resolution_cache.rb                 # new, Redis::Alfred-backed, 12h TTL
    ├── graph_api_client.rb                          # new, HTTParty client for ad/campaign/adset lookup
    └── marketing_authorization_service.rb           # new, OAuth code→short-lived→long-lived token exchange (independent of Whatsapp::EmbeddedSignupService/FacebookApiClient)

custom/app/jobs/
├── custom/campaign_resolution_job.rb                # new, queue :low, retry_on Meta::RateLimitError
└── meta/token_refresh_job.rb                        # new, daily Sidekiq-cron, proactively re-exchanges tokens near expiry (FR-021)

config/schedule.yml                                   # extend: new sidekiq-cron entry registering Meta::TokenRefreshJob

custom/app/listeners/custom/
└── action_cable_listener.rb                         # new, Custom::ActionCableListener#opportunity_updated

custom/app/controllers/api/v1/accounts/
└── campaign_attribution_settings_controller.rb      # new: show/update/connect

custom/app/policies/
└── campaign_attribution_setting_policy.rb           # new, Account Administrator only

lib/tasks/
└── campaign_attribution.rake                        # new: campaign_attribution:backfill

lib/filters/filter_keys.yml                          # extend: campaign_referral_present entry

app/services/automation_rules/
└── conditions_filter_service.rb                     # extend: message_query_string presence-check branch

app/javascript/dashboard/routes/dashboard/settings/automation/
└── constants.js                                     # extend: new condition entry

app/javascript/dashboard/helper/
└── automationHelper.js                              # extend: conditionFilterMaps entry

app/javascript/dashboard/routes/dashboard/settings/pipelineStages/
├── Index.vue                                        # extend or new tab: campaign attribution settings entry point
└── CampaignAttributionSettings.vue                  # new (or a new section inside CardFieldConfig.vue)

app/javascript/dashboard/components-next/Opportunities/
└── ContactOpportunityCard.vue                       # extend: render campaign attribution indicator/names

en.yml / pt_BR.yml                                   # new i18n keys (backend)
en.json / pt_BR.json                                 # new i18n keys (frontend)

custom/spec/                                         # new specs mirroring the above, where they materially cover new logic
```

**Structure Decision**: Existing Chatwoot monolith layout retained. All genuinely new
fork-specific logic lives under `custom/` (models, services under a new `custom/app/services/meta/`
namespace, jobs, listeners, controllers, policies), mirroring how the rest of the Kanban module is
already organized — no new top-level project or service boundary introduced. The only edits
outside `custom/`/`app/javascript` are the four small, additive automation-condition touches
(`lib/filters/filter_keys.yml` and `app/services/automation_rules/conditions_filter_service.rb`
on the backend; `constants.js` and `automationHelper.js` on the frontend) plus i18n files — all
justified in Constitution Check above.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Editing 4 existing core files for the `campaign_referral_present` automation condition (`filter_keys.yml`, `conditions_filter_service.rb`, `constants.js`, `automationHelper.js`) instead of routing through an extension point | `referral` is raw JSON on `Message.content_attributes`, not an account-defined `CustomAttributeDefinition` — the existing `custom_attribute_query` dynamic path (the one extension point automation conditions have) only covers account-configured attributes, not system-computed message JSON presence checks. No other extension point for automation condition filters exists in the codebase today. | Modeling this as a virtual custom attribute was considered and rejected — custom attributes are account-configurable and contact/conversation-scoped by convention; forcing a system-computed, message-level boolean into that model would be a worse fit and a larger, more confusing change than four small, additive, `private_note`-mirroring edits. |
| Editing 3 existing core files for the Super-Admin Meta App config (`config/installation_config.yml`, `super_admin/app_configs_controller.rb`, `app/helpers/super_admin/features.yml`) instead of a bespoke new model/table | Super-Admin-level, instance-wide app credential config in this codebase is declared exclusively through this shared, generic mechanism (`InstallationConfig` + `GlobalConfigService` + the `allowed_configs` mapping + the `features.yml`-driven Settings sidebar) — every existing integration (WhatsApp, Slack, Notion, TikTok, Instagram, etc.) uses it the same additive way, each with its own independent key set and sidebar entry. | A bespoke new ActiveRecord model/table for a single set of instance-wide key/value config was rejected as needless new infrastructure duplicating a pattern the codebase already provides generically — worse fit for Constitution Principle II (smallest change) than three small, additive entries mirroring the exact shape every other integration already uses. |
| Editing 1 existing core file, `config/schedule.yml`, to register `Meta::TokenRefreshJob`'s daily cron | Sidekiq-cron jobs in this codebase are declared exclusively in this single hardcoded file, loaded once via `Sidekiq::Cron::Job.load_from_hash!` in `config/initializers/sidekiq.rb`; there is no per-namespace or `custom/`-scoped schedule file, and no merge/include mechanism to add one without also touching the initializer. | A bespoke in-app scheduler (e.g. a periodic self-rescheduling job, or a custom loader reading a second `custom/config/schedule.yml`) was rejected as needless new infrastructure duplicating `sidekiq-cron`, the convention every other scheduled job in this codebase already relies on — worse fit for Constitution Principle II than one small, additive entry. |
