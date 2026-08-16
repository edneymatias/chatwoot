# Tasks: Meta Referral Attribution Refinements

**Input**: Design documents from `/specs/037-meta-referral-attribution-refinements/`  
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Database schema expansion for referral refinements

- [x] T001 Create database migration in `db/migrate/21260815000000_add_attribution_refinements_to_ichatr_opportunities.rb` to add `campaign_headline` (`string`), `campaign_body` (`text`), and `campaign_thumbnail_url` (`text`) to `ichatr_opportunities`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core model extensions, exception definitions, and localization that all stories depend on

- [x] T002 Update `Opportunity` model in `custom/app/models/opportunity.rb` with `has_one_attached :campaign_thumbnail`, status constants/scopes, and serialization methods
- [x] T003 [P] Define Meta Graph API exception classes (`Meta::Error`, `Meta::AuthenticationError`, `Meta::RateLimitError`, `Meta::NodeNotFoundError`, `Meta::ApiError`) in `custom/app/services/meta/exceptions.rb`
- [x] T004 [P] Add backend i18n keys for campaign attribution errors and statuses in `config/locales/en.yml` and `config/locales/pt_BR.yml`
- [x] T005 [P] Add frontend i18n keys for organic badges, popover labels, and reprocess actions in `app/javascript/dashboard/i18n/locale/en.json` and `app/javascript/dashboard/i18n/locale/pt_BR.json`

---

## Phase 3: User Story 1 - Organic Post Attribution & Non-Destructive Handling (Priority: P1) 🎯 MVP

**Goal**: Synchronously identify organic Facebook/Instagram posts upon incoming WhatsApp referral, store headline/body/thumbnail, mark as `organic_post`, and skip external ad API queries to prevent false disconnections.

**Independent Test**: Simulate an incoming message with `source_type: "post"`. Verify the opportunity is created with `campaign_resolution_status: 'organic_post'`, stores headline and body text, skips `Custom::CampaignResolutionJob`, and keeps the Meta integration enabled.

- [x] T006 [P] [US1] Update `Custom::AutomationRules::ActionService.process_campaign_attribution` in `custom/app/services/custom/automation_rules/action_service.rb` to parse organic referral payloads (`source_type == 'post'`, `story_fbid`, `video_url`), extract headline/body/thumbnail, persist status `organic_post`, and bypass ad resolution
- [x] T007 [P] [US1] Update `useOpportunityCardFields` composable in `app/javascript/dashboard/composables/useOpportunityCardFields.js` to compute `campaignAttribution` for organic posts (platform icon, `isOrganic`, headline, body)
- [x] T008 [US1] Update automated specs in `custom/spec/services/custom/automation_rules/action_service_spec.rb` to verify organic post referral capture and status assignment

---

## Phase 4: User Story 2 - Accurate OAuth Invalidation & Query Error Isolation (Priority: P1)

**Goal**: Accurately classify Graph API responses so that only authentic token revocation (`code: 190`) disconnects the account, while node/query errors (`code: 100`/404) fail only the individual opportunity and rate limits (`17/32/613`) trigger automatic retries.

**Independent Test**: Trigger resolution for an invalid or non-existent ad ID returning code 100. Verify the opportunity status becomes `failed` while the account integration remains `enabled: true`.

- [x] T009 [P] [US2] Update `Meta::GraphApiClient#fetch_ad_details` in `custom/app/services/meta/graph_api_client.rb` to parse JSON error responses (`code`, `error_subcode`, `type`, `message`) and raise typed exceptions (`Meta::AuthenticationError`, `Meta::RateLimitError`, `Meta::NodeNotFoundError`, `Meta::ApiError`)
- [x] T010 [US2] Update `Custom::CampaignResolutionJob` in `custom/app/jobs/custom/campaign_resolution_job.rb` to catch typed exceptions, isolating query failures to individual opportunities, retrying rate limits, and only disconnecting on `Meta::AuthenticationError`
- [x] T011 [P] [US2] Add unit specs for Graph API error classification in `custom/spec/services/meta/graph_api_client_spec.rb`
- [x] T012 [US2] Update resolution job specs in `custom/spec/jobs/custom/campaign_resolution_job_spec.rb` to verify non-destructive query failures, token revocation disconnections, and rate-limit retries

---

## Phase 5: User Story 3 - Visual Attribution Popover with Creative Thumbnail Preview (Priority: P2)

**Goal**: Provide rich visual context on Kanban cards by asynchronously caching creative thumbnails via ActiveStorage and rendering a hover/click popover displaying thumbnail preview, ad/post details, and friendly error messages.

**Independent Test**: Open the Kanban board and hover over the platform icon badge of an opportunity with thumbnail media. Verify the popover renders the creative preview image, title, and attribution details.

- [x] T013 [P] [US3] Create `Meta::AttachCampaignThumbnailJob` in `custom/app/jobs/meta/attach_campaign_thumbnail_job.rb` to download remote thumbnail URLs and attach blobs to `opportunity.campaign_thumbnail` with timeouts and error tolerance
- [x] T014 [US3] Wire `Meta::AttachCampaignThumbnailJob` dispatch into `ActionService` (for organic referrals) and `Custom::CampaignResolutionJob` (for resolved ads with creative media)
- [x] T015 [P] [US3] Create `OpportunityAttributionPopover.vue` in `app/javascript/dashboard/components-next/Opportunities/OpportunityAttributionPopover.vue` to render the creative thumbnail preview, campaign/adset/ad or post metadata, and human-readable failure explanations
- [x] T016 [US3] Integrate `OpportunityAttributionPopover.vue` into `KanbanCard.vue` in `app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue` and `ContactOpportunityCard.vue`
- [x] T017 [P] [US3] Add unit specs for `Meta::AttachCampaignThumbnailJob` in `custom/spec/jobs/meta/attach_campaign_thumbnail_job_spec.rb`

---

## Phase 6: User Story 4 - Automatic Reconnect Drainage & Orphaned Attribution Sweeper (Priority: P2)

**Goal**: Automatically drain and resolve backlog pending opportunities when the integration is reconnected or enabled, provide an hourly background sweeper for stranded records, and offer a manual "Reprocessar Pendentes" button in Settings.

**Independent Test**: With pending opportunities in the database, click "Reprocessar Pendentes" or reconnect the integration in Settings. Verify that all pending opportunities are queued and resolved in the background.

- [x] T018 [P] [US4] Implement `Meta::DrainPendingAttributionsJob` in `custom/app/jobs/meta/drain_pending_attributions_job.rb` to batch and enqueue resolution for pending opportunities with rate-limiting delays
- [x] T019 [P] [US4] Implement `Meta::PendingAttributionsSweeperJob` in `custom/app/jobs/meta/pending_attributions_sweeper_job.rb` to periodically find pending opportunities older than 15 minutes in active accounts and enqueue drainage
- [x] T020 [US4] Update `CampaignAttributionSettingsController` in `custom/app/controllers/api/v1/accounts/campaign_attribution_settings_controller.rb` to trigger auto-drain on connect/update and implement `reprocess_pending` action
- [x] T021 [P] [US4] Update `CampaignAttributionSettings.vue` in `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/CampaignAttributionSettings.vue` and `campaignAttributionSettings.js` API client with "Reprocessar Pendentes" button, pending counter, and toast notifications
- [x] T022 [P] [US4] Add specs for `DrainPendingAttributionsJob` and `PendingAttributionsSweeperJob` in `custom/spec/jobs/meta/`
- [x] T023 [US4] Add controller specs for `reprocess_pending` and auto-drain triggers in `custom/spec/controllers/api/v1/accounts/campaign_attribution_settings_controller_spec.rb`

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Validation, code quality checks, and end-to-end verification

- [x] T024 [P] Run RuboCop on backend changes: `docker compose exec rails bundle exec rubocop -a custom/ db/migrate/`
- [x] T025 [P] Run ESLint on frontend changes: `docker compose exec vite pnpm eslint:fix app/javascript/dashboard/`
- [x] T026 Run full attribution RSpec test suite: `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/`
- [x] T027 Run frontend Vitest test suite: `docker compose exec vite pnpm test`
- [x] T028 Execute manual verification scenarios documented in `specs/037-meta-referral-attribution-refinements/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Can start immediately.
- **Foundational (Phase 2)**: Depends on Phase 1 completion (migration must exist).
- **User Story 1 (Phase 3)**: Depends on Phase 2 completion.
- **User Story 2 (Phase 4)**: Depends on Phase 2 completion.
- **User Story 3 (Phase 5)**: Depends on Phase 2 completion and Phase 3/4 resolution hooks.
- **User Story 4 (Phase 6)**: Depends on Phase 2 completion and Phase 4 resolution job.
- **Polish (Phase 7)**: Depends on all user stories being implemented.

### Parallel Opportunities

- Within Phase 2: T003, T004, T005 can be executed in parallel.
- Within Phase 3 (US1): T006, T007 can be executed in parallel.
- Within Phase 4 (US2): T009, T011 can run in parallel before T010, T012.
- Within Phase 5 (US3): T013, T015, T017 can run in parallel.
- Within Phase 6 (US4): T018, T019, T021, T022 can run in parallel.
- Within Phase 7: T024, T025 can run in parallel.

---

## Implementation Strategy

### MVP First (User Story 1 & User Story 2)
1. Complete Phase 1 (Migration) + Phase 2 (Foundational model, exceptions, i18n).
2. Complete Phase 3 (User Story 1: Organic Post Attribution).
3. Complete Phase 4 (User Story 2: Accurate OAuth Error Classification).
4. **Validate MVP**: Ensure incoming organic leads and query errors do not disconnect the Meta account.

### Incremental Delivery
1. Add User Story 3 (Phase 5: Creative Thumbnail ActiveStorage caching & Popover preview).
2. Add User Story 4 (Phase 6: Auto-drain, Sweeper, and Reprocess Settings Button).
3. Execute Phase 7 (Full test suites, linter fixes, quickstart verification).
