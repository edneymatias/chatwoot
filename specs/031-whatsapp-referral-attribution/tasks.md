---

description: "Task list for WhatsApp Referral (Facebook/Instagram Ad) Attribution"

---

# Tasks: WhatsApp Referral (Facebook/Instagram Ad) Attribution

**Input**: Design documents from `/specs/031-whatsapp-referral-attribution/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md (all present)

**Tests**: Included, scoped exactly to the four areas plan.md's Testing strategy calls out as materially covering new logic (capture, resolution job state transitions, condition filter SQL, backfill idempotency) — per `CLAUDE.md`'s "avoid writing specs unless explicitly asked" balanced against this being an explicit call-out in the approved plan.

**Organization**: Tasks are grouped by user story (US1/US2/US3, per spec.md priorities P1/P2/P3) to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

## Path Conventions

Existing Chatwoot monolith: `app/`, `custom/` (fork-specific), `app/javascript/dashboard`, `db/migrate/`, `lib/`, `config/`. Paths below are exact, per plan.md's Project Structure.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Migrations and Super Admin config scaffolding needed before any story-level code can run.

- [X] T001 Create migration `db/migrate/<ts>_add_campaign_attribution_to_ichatr_opportunities.rb` — adds `campaign_source_id` (string), `campaign_source_url` (string), `campaign_platform` (string), `campaign_name` (string), `campaign_adset_name` (string), `campaign_ad_name` (string), `campaign_resolution_status` (string) to `ichatr_opportunities`, all nullable, plus a partial index on `campaign_resolution_status` (per data-model.md)
- [X] T002 [P] Create migration `db/migrate/<ts>_create_ichatr_campaign_attribution_settings.rb` — creates `ichatr_campaign_attribution_settings` (`account_id` bigint FK unique, `enabled` boolean default false, `provider_config` jsonb default `{}`, timestamps)
- [X] T003 [P] Add `META_MARKETING_APP_ID`, `META_MARKETING_APP_SECRET`, `META_MARKETING_API_VERSION` (default `v22.0`) keys to `config/installation_config.yml`
- [X] T004 [P] Add `'meta_marketing'` entry (`%w[META_MARKETING_APP_ID META_MARKETING_APP_SECRET META_MARKETING_API_VERSION]`) to the `mapping` hash in `app/controllers/super_admin/app_configs_controller.rb#allowed_configs`
- [X] T005 [P] Add a `meta_marketing` entry (`name`, `description`, `enabled: true`, `icon`, `config_key: 'meta_marketing'`) to `app/helpers/super_admin/features.yml` so a "Meta Marketing" link appears in the Super Admin Settings sidebar

**Checkpoint**: Schema and Super Admin config scaffolding exist; no functional code yet.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core connection/settings infrastructure shared by every user story.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T006 Create `CampaignAttributionSetting` model in `custom/app/models/campaign_attribution_setting.rb` (`belongs_to :account`, `validates :account_id, uniqueness: true`, per data-model.md) (depends on T002)
- [X] T007 Wire `has_one :campaign_attribution_setting, dependent: :destroy` onto `custom/app/models/custom/concerns/account.rb` (depends on T006)
- [X] T008 [P] Create `custom/app/policies/campaign_attribution_setting_policy.rb` (Pundit, restricts `show`/`update`/`connect` to Account Administrators, per FR-018, mirroring `PipelineCurrencySettingPolicy`)
- [X] T009 [P] Create `custom/app/services/meta/marketing_authorization_service.rb` — exchanges an OAuth `code` for a short-lived then long-lived (`grant_type=fb_exchange_token`) Meta user access token against `META_MARKETING_APP_ID`/`META_MARKETING_APP_SECRET` (read via `GlobalConfigService.load`), independent of `Whatsapp::EmbeddedSignupService`/`Whatsapp::FacebookApiClient` (depends on T003)
- [X] T010 Create `custom/app/controllers/api/v1/accounts/campaign_attribution_settings_controller.rb` (`show`/`update`/`connect`, per contracts/campaign-attribution-settings-api.md) (depends on T006, T008, T009)
- [X] T011 Add routes for the `campaign_attribution_setting` singular resource (`show`/`update`) plus its `connect` action in `config/routes.rb` (depends on T010)
- [X] T012 [P] Create `custom/app/services/meta/rate_limiter.rb` — Redis::Alfred sliding-window limiter keyed by `account_id` (`meta_rate_limiter:{account_id}`), modeled on `app/services/auto_assignment/rate_limiter.rb`
- [X] T013 [P] Create `custom/app/services/meta/rate_limit_error.rb`
- [X] T014 [P] Create `custom/app/services/meta/campaign_resolution_cache.rb` — Redis::Alfred-backed, 12h TTL, keyed by `campaign_source_id` (global, not account-scoped, per research.md)
- [X] T015 Create `custom/app/services/meta/graph_api_client.rb` — HTTParty client fetching `name,adset{id,name},campaign{id,name},creative{effective_object_story_id,object_story_spec}` for a given ad id, against `META_MARKETING_API_VERSION` (depends on T003)
- [X] T016 Refactor `Opportunity#broadcast_opportunity_updated` in `custom/app/models/opportunity.rb` to call `Rails.configuration.dispatcher.dispatch('opportunity_updated', ...)` instead of `ActionCableBroadcastJob.perform_later` directly
- [X] T017 Create `custom/app/listeners/custom/action_cable_listener.rb` (`Custom::ActionCableListener#opportunity_updated`, broadcasting to the `account_#{account_id}` channel) and wire it via `prepend_mod_with('X')` per research.md's realtime decision (depends on T016)
- [X] T018 Extend `Opportunity#as_json`/broadcast payload in `custom/app/models/opportunity.rb` to include the 7 new `campaign_*` fields (per contracts/opportunity-updated-event.md) (depends on T001, T017)

**Checkpoint**: Foundation ready — user story implementation can now begin.

---

## Phase 3: User Story 1 - See campaign origin on an Opportunity card (Priority: P1) 🎯 MVP

**Goal**: Synchronous capture of raw attribution at Opportunity creation, asynchronous name resolution with realtime card updates, and a fallback display on permanent failure.

**Independent Test**: Send a real/simulated CTWA WhatsApp message with `referral` data into either WhatsApp path, let `create_opportunity` fire, confirm the platform indicator appears immediately and the resolved campaign/ad-set/ad names appear live once resolution completes (per quickstart.md steps 0-3).

### Tests for User Story 1

- [X] T019 [P] [US1] RSpec for synchronous capture logic in `custom/spec/services/custom/automation_rules/action_service_spec.rb` — covers referral present/absent, `source_url` present/absent (platform left unset), per Acceptance Scenarios 1 and 4
- [X] T020 [P] [US1] RSpec for `Custom::CampaignResolutionJob` state transitions in `custom/spec/jobs/custom/campaign_resolution_job_spec.rb` — `pending` → `resolved`/`failed`, cache hit vs. miss, `OAuthException` → `connected: false`

### Implementation for User Story 1

- [X] T021 [US1] Extract the synchronous capture logic (reads `message.content_attributes['referral']`, sets `campaign_source_id`/`campaign_source_url`/`campaign_platform`/`campaign_resolution_status`) into a reusable method on `custom/app/services/custom/automation_rules/action_service.rb`, callable independently for reuse by the backfill task (US3) (depends on T001)
- [X] T022 [US1] Wire the extracted capture method into `Custom::AutomationRules::ActionService#create_opportunity` (depends on T021)
- [X] T023 [US1] Create `custom/app/jobs/custom/campaign_resolution_job.rb` — queue `:low`, `retry_on Meta::RateLimitError`; checks `Meta::CampaignResolutionCache` before calling `Meta::GraphApiClient`; updates `campaign_name`/`campaign_adset_name`/`campaign_ad_name`/`campaign_platform` (if still unset)/`campaign_resolution_status`; fires the `opportunity_updated` event via the dispatcher on completion (depends on T012, T014, T015, T017)
- [X] T024 [US1] Enqueue `Custom::CampaignResolutionJob` from the capture method when a `campaign_source_id` is captured and the account's `CampaignAttributionSetting#enabled` is true (depends on T022, T023, T006)
- [X] T025 [US1] Create `custom/app/jobs/meta/token_refresh_job.rb` — daily Sidekiq-cron; sweeps `CampaignAttributionSetting` rows with a non-empty `provider_config` and re-exchanges tokens within ~10 days of `expires_at` via `Meta::MarketingAuthorizationService` (FR-021) (depends on T009, T006)
- [X] T026 [US1] Register `Meta::TokenRefreshJob` as a new daily entry in `config/schedule.yml` (e.g. `meta_token_refresh_job: {cron: '0 3 * * *', class: 'Meta::TokenRefreshJob', queue: 'scheduled_jobs'}`, mirroring existing entries' shape) (depends on T025)
- [X] T027 [P] [US1] Add "Connect Meta" action (Facebook JS SDK `FB.login({ scope: 'ads_read' })` popup, POSTs the returned `code` to the `connect` endpoint) in `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/CampaignAttributionSettings.vue` (new file, alongside the existing Card Fields tab)
- [X] T028 [P] [US1] Wire the master enable/disable toggle and connected/disconnected status display into `CampaignAttributionSettings.vue`, calling the `show`/`update` endpoints (depends on T011)
- [X] T029 [US1] Register `CampaignAttributionSettings.vue` as a new tab/section in `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/Index.vue` (depends on T027, T028)
- [X] T030 [P] [US1] Extend `app/javascript/dashboard/components-next/Opportunities/ContactOpportunityCard.vue` to render the platform indicator, resolved campaign/ad-set/ad names, and the raw-identifier fallback on `campaign_resolution_status: failed`
- [X] T031 [P] [US1] Add i18n keys (connect button, toggle label, connected/disconnected states, platform indicator labels) to `en.yml`/`pt_BR.yml` and `en.json`/`pt_BR.json`

**Checkpoint**: User Story 1 fully functional and independently testable (quickstart.md steps 0-3).

---

## Phase 4: User Story 2 - Trigger opportunity creation reliably from campaign leads (Priority: P2)

**Goal**: A boolean `campaign_referral_present` automation condition, independent of message text, available on the `message_created` trigger.

**Independent Test**: Create an Automation Rule with the new condition, send a CTWA message with edited/replaced suggested text, confirm the rule still fires (per quickstart.md step 4 / contracts/automation-condition-filter.md).

### Tests for User Story 2

- [X] T032 [P] [US2] RSpec for the `campaign_referral_present` condition filter SQL in `spec/services/automation_rules/conditions_filter_service_spec.rb` — covers `equal_to true`/`false` and the edited/replaced-text case per contracts/automation-condition-filter.md

### Implementation for User Story 2

- [X] T033 [US2] Add `campaign_referral_present` entry in `lib/filters/filter_keys.yml` (mirroring `private_note` under `messages`)
- [X] T034 [US2] Add logic in `app/services/automation_rules/conditions_filter_service.rb` `#message_query_string` to map `campaign_referral_present` to SQL (e.g. `messages.content_attributes -> 'referral' IS NOT NULL`) (depends on T033)
- [X] T035 [US2] Add `campaign_referral_present` entry to `AUTOMATIONS.message_created.conditions` in `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js` (depends on T034)
- [X] T036 [US2] Add `campaign_referral_present: booleanFilterOptions` entry to `conditionFilterMaps` in `app/javascript/dashboard/helper/automationHelper.js` (depends on T035)
- [X] T037 [US2] Add the condition label i18n keys to `en.yml`/`pt_BR.yml` (backend) and `en.json`/`pt_BR.json` (frontend) (depends on T035)
- [X] T038 [US2] RSpecs for `ConditionsFilterService` checking `campaign_referral_present` filter matching correctly (depends on T034)

**Checkpoint**: User Stories 1 AND 2 both work independently.

---

## Phase 5: User Story 3 - Backfill attribution on existing production opportunities (Priority: P3)

**Goal**: A one-time, idempotent, account-gated backfill for pre-existing Opportunities.

**Independent Test**: Run the backfill against a mixed set of pre-existing Opportunities (some with recoverable referral data, some without, some belonging to accounts with the toggle off), confirm each is handled per its case, and confirm a re-run does not reprocess (per quickstart.md step 5).

**Note**: Per spec.md, this story is intentionally dependent on User Story 1 (capture method, resolution job) and User Story 2 already existing — not independent of them, unlike US1/US2 relative to each other.

### Tests for User Story 3

- [X] T038 [P] [US3] RSpec for backfill idempotency and account gating in `custom/spec/tasks/campaign_attribution_spec.rb` — covers Acceptance Scenarios 1-5 (recoverable data, no data, account gated, re-run safety, summary counts)

### Implementation for User Story 3 (Backfill Support)

- [X] T039 [US3] Create `lib/tasks/meta_marketing.rake` containing `task :backfill_referral_attribution => :environment`
- [X] T040 [US3] Rake task queries `Message.where("content_attributes -> 'referral' IS NOT NULL")` (depends on T039)
- [X] T041 [US3] Rake task iterates matching messages, finds `Opportunity` via `message.conversation_id`, and calls the extracted synchronous capture logic (depends on T040, T021)
- [X] T042 [US3] Enqueue `Custom::CampaignResolutionJob` asynchronously for each backfilled opportunity where `campaign_source_id` was recovered and setting is enabled (depends on T041)

**Checkpoint**: All three user stories independently functional.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final validation across all stories.

- [X] T040 [P] Run `docker compose exec rails bundle exec rubocop -a` and `docker compose exec vite pnpm eslint:fix` across all touched files
- [X] T041 [P] Run `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec` for all specs added in T019, T020, T032, T038
- [X] T042 [P] Run `docker compose exec vite pnpm test` for the frontend changes in T027-T031, T035-T036
- [X] T043 Run the full `quickstart.md` validation checklist end-to-end (SC-001 through SC-006) against the dev stack

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately.
- **Foundational (Phase 2)**: Depends on Setup (T002, T003) — BLOCKS all user stories.
- **User Story 1 (Phase 3)**: Depends on Foundational completion (all of T006-T018).
- **User Story 2 (Phase 4)**: Depends on Foundational completion only — genuinely independent of US1's runtime code (the condition is a pure presence-check on `Message.content_attributes`, unrelated to the Opportunity columns or the Meta connection). Can be built in parallel with US1.
- **User Story 3 (Phase 5)**: Depends on US1 (T021 capture method, T023 resolution job) and the account gate (T006) — per spec.md's own stated dependency, not independently startable before US1.
- **Polish (Phase 6)**: Depends on all desired user stories being complete.

### Within Each User Story

- US1: T019-T020 (tests) may be written alongside T021-T026 (backend); T021 → T022 → T024; T023 is independent of T021/T022 until T024 wires them together. Frontend tasks T027-T031 depend only on the backend contract (T010, T011) being in place, not on T021-T026.
- US2: T033 → T034 (backend); T035-T037 are independent of each other and of the backend tasks except for sharing the same condition key name.
- US3: T039 depends on T021 and T023 from US1.

### Parallel Opportunities

- Setup: T002, T003, T004, T005 in parallel (T001 touches the same migrations directory but a different file, so it can run alongside them too).
- Foundational: T008, T009, T012, T013, T014 in parallel once T006/T002 land.
- US1: T027, T028, T030, T031 (frontend) in parallel with each other and with T023/T025 (backend), once T010/T011 exist.
- US2: T035, T036, T037 in parallel once T033/T034 land.
- Once Foundational completes, US1 and US2 can be staffed and built in parallel (US3 must wait on US1).

---

## Parallel Example: User Story 1

```bash
# Once T010/T011 (controller/routes) exist, launch frontend tasks together:
Task: "Add Connect Meta action in CampaignAttributionSettings.vue"
Task: "Wire master toggle + connected status in CampaignAttributionSettings.vue"
Task: "Extend ContactOpportunityCard.vue with attribution display"
Task: "Add i18n keys to en.yml/pt_BR.yml and en.json/pt_BR.json"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories).
3. Complete Phase 3: User Story 1.
4. **STOP and VALIDATE**: run quickstart.md steps 0-3 independently.
5. Deploy/demo if ready — this alone delivers the core "see campaign origin on the card" value.

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. User Story 1 → validate → deploy/demo (MVP).
3. User Story 2 → validate → deploy/demo (can be built in parallel with US1 if staffed, since it has no runtime dependency on it).
4. User Story 3 → validate → deploy/demo (only after US1 exists).

### Parallel Team Strategy

With two developers, once Foundational is done: Developer A takes User Story 1 (backend + frontend), Developer B takes User Story 2 (fully independent, small surface area) in parallel; User Story 3 starts once Developer A's US1 backend pieces (T021, T023) land.

---

## Notes

- [P] tasks touch different files with no unmet dependency.
- [Story] labels map every story-phase task to US1/US2/US3 for traceability, per spec.md priorities.
- Tests (T019, T020, T032, T038) are included per plan.md's explicit Testing strategy — no additional specs beyond these four areas per `CLAUDE.md`'s "avoid writing specs unless explicitly asked."
- Commit after each task or logical group; stop at any checkpoint to validate a story independently.

## Phase 7: Convergence

- [X] T044 Add "Connect Meta" OAuth popup action using Facebook JS SDK in `CampaignAttributionSettings.vue` per FR-014 (missing)
- [X] T045 Wire master enable/disable toggle and connected status in `CampaignAttributionSettings.vue` per FR-013 (missing)
- [X] T046 Register `CampaignAttributionSettings.vue` as a new tab/section in `pipelineStages/Index.vue` per plan: settings UI (missing)
- [X] T047 Extend `ContactOpportunityCard.vue` to render platform indicator, resolved names, and fallback status per FR-006, FR-007 (missing)
- [X] T048 Add frontend i18n keys for the attribution UI to `en.json` and `pt_BR.json` per plan: i18n (missing)

## Phase 8: Convergence

- [X] T049 Implement summary counters for account-gating and missing data in backfill task per FR-012 (partial)
- [X] T050 Update CampaignAttributionSetting to disconnected state on OAuthException in CampaignResolutionJob per T020 (missing)
