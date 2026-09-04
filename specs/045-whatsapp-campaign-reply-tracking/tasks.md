---
description: "Task list template for feature implementation"
---

# Tasks: WhatsApp Campaign Reply Tracking

**Input**: Design documents from `/specs/045-whatsapp-campaign-reply-tracking/`

**Prerequisites**: [plan.md](./plan.md) (required), [spec.md](./spec.md) (required for user stories), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/campaign-recipients-api.md](./contracts/campaign-recipients-api.md), [quickstart.md](./quickstart.md)

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Exact file paths are provided for every task

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Project initialization and basic structure

- [X] T001 Create custom module directories for models, services, controllers, and specs at `custom/app/models/custom/`, `custom/app/services/custom/whatsapp/`, `custom/app/controllers/api/v1/accounts/campaigns/`, and `custom/spec/`
- [X] T002 [P] Verify development container environment and database readiness using `docker compose exec rails bundle exec rails runner "puts Account.count"`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core database and domain model infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 Create database migration for `ichatr_campaign_recipients` table with foreign keys, status enum, timestamps, reply correlation columns, and unique indexes in `db/migrate/21260903100000_create_ichatr_campaign_recipients.rb`
- [X] T004 Execute database migration in container via `docker compose exec rails bundle exec rails db:migrate`
- [X] T005 [P] Implement `Custom::CampaignRecipient` model with enum status, validations, associations, status lifecycle methods (`mark_sent!`, `mark_skipped!`, `mark_failed!`, `update_from_whatsapp_status!`, `mark_replied!`), and no-downgrade logic in `custom/app/models/custom/campaign_recipient.rb`
- [X] T006 [P] Implement `Custom::Campaign` module extension adding `has_many :ichatr_campaign_recipients` via `Campaign.include_mod_with('Campaign')` in `custom/app/models/custom/campaign.rb`
- [X] T007 [P] Implement model unit tests verifying validations, associations, status transitions, no-downgrade guard, and reply attributes in `custom/spec/models/custom/campaign_recipient_spec.rb`

**Checkpoint**: Foundation ready - `Custom::CampaignRecipient` model and DB table are tested and active. User story implementation can now begin.

---

## Phase 3: User Story 1 - Agent sees campaign context on a reply (Priority: P1) 🎯 MVP

**Goal**: When a customer replies to a WhatsApp one-off campaign (either via quick-reply button tap or unambiguous free text within 72 hours), correlate the reply to the campaign send, tag the newly created conversation with `campaign_id`, backfill the original campaign message as the first message of the conversation, and mark the recipient as `replied`. Never attribute ambiguous cases or retag existing open conversations.

**Independent Test**: Send a campaign to contacts, simulate inbound WhatsApp webhook replies (button tap with `context.id`, single candidate free text within 72h, ambiguous candidates, and reply on open conversation), and verify conversation attribution, context message creation, and recipient lifecycle status per acceptance scenarios.

### Implementation & Tests for User Story 1

- [X] T008 [P] [US1] Create unit and integration spec for one-off campaign send tracking in `custom/spec/services/custom/whatsapp/oneoff_campaign_service_spec.rb`
- [X] T009 [P] [US1] Create unit and integration spec for inbound message correlation, context backfill, and status handling in `custom/spec/services/custom/whatsapp/incoming_message_base_service_spec.rb` — including the ambiguous-candidates → no-attribution case (FR-003/SC-002) and the already-open-conversation-not-retagged case (FR-004)
- [X] T010 [US1] Implement `Custom::Whatsapp::OneoffCampaignService` (prepended over `Whatsapp::OneoffCampaignService`, replacing `perform` with no `super`) to track per-recipient lifecycle (`mark_sent!`, `mark_skipped!`, `mark_failed!`) in `ichatr_campaign_recipients` in `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb`
- [X] T011 [US1] Implement `Custom::Whatsapp::IncomingMessageBaseService#process_statuses` (prepended over `Whatsapp::IncomingMessageBaseService`, replacing with no `super`) to update `Custom::CampaignRecipient` via `update_from_whatsapp_status!` on webhook delivery/read/failed events in `custom/app/services/custom/whatsapp/incoming_message_base_service.rb`
- [X] T012 [US1] Implement `Custom::Whatsapp::IncomingMessageBaseService#set_conversation` hook (calling `super`) to correlate newly created conversations with campaigns via `context.id` exact match or 72h unambiguous fallback, attach `campaign_id`, mark recipient as replied (`mark_replied!`), and backfill the original outbound campaign message once into the conversation in `custom/app/services/custom/whatsapp/incoming_message_base_service.rb`
- [X] T013 [US1] Verify User Story 1 automated specs pass via `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/models/custom/campaign_recipient_spec.rb custom/spec/services/custom/whatsapp/oneoff_campaign_service_spec.rb custom/spec/services/custom/whatsapp/incoming_message_base_service_spec.rb`

**Checkpoint**: At this point, User Story 1 should be fully functional and testable independently (MVP complete).

---

## Phase 4: User Story 2 - Manager reviews campaign reply performance (Priority: P2)

**Goal**: Provide delivery metrics, unique reply count, per-button click breakdown (with rates), and contacts list for WhatsApp campaigns in UI without requiring an Enterprise license.

**Independent Test**: Hit the new recipients controller endpoints (`metrics`, `contacts`, `reply_breakdown`), verify response calculations and click-rate percentages, and verify the campaign analytics page in dashboard renders the delivery metrics, replied metric card, and reply breakdown table.

### Implementation & Tests for User Story 2

- [X] T014 [P] [US2] Create request spec for recipients controller covering `metrics`, `contacts`, and `reply_breakdown` endpoints and permissions in `custom/spec/requests/api/v1/accounts/campaigns/recipients_controller_spec.rb`
- [X] T015 [US2] Add unconditional routes for `recipients/metrics`, `recipients/contacts`, and `recipients/reply_breakdown` under `resources :campaigns` in `config/routes.rb`
- [X] T016 [US2] Implement `Api::V1::Accounts::Campaigns::RecipientsController` with `metrics`, `contacts`, and `reply_breakdown` actions (calculating audience, sent, delivered, read, replied, failed, skipped, per-button click rates, and synthetic "other" row), reusing `CampaignPolicy#show?` (`authorize @campaign, :show?`) and the `ensure_whatsapp_campaign_analytics_enabled!` gate per contracts/campaign-recipients-api.md, in `custom/app/controllers/api/v1/accounts/campaigns/recipients_controller.rb`
- [X] T017 [P] [US2] Add i18n translation keys for replied metric and reply breakdown table in `app/javascript/dashboard/i18n/locale/en/campaign.json`
- [X] T018 [P] [US2] Add i18n translation keys for replied metric and reply breakdown table in Portuguese in `app/javascript/dashboard/i18n/locale/pt_BR/campaign.json`
- [X] T019 [US2] Update campaigns API client in `app/javascript/dashboard/api/campaigns.js` to rename `analyticsMetrics`/`analyticsContacts` to `recipientsMetrics`/`recipientsContacts` (pointing to new endpoints) and add `recipientsReplyBreakdown`
- [X] T020 [P] [US2] Create `CampaignReplyBreakdown.vue` component using Tailwind and BaseTable to render button clicks, counts, click rates, and other replies in `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignReplyBreakdown.vue`
- [X] T021 [US2] Update `WhatsAppCampaignAnalyticsPage.vue` to fetch metrics, deliveries, and reply breakdown from repointed API, render replied metric card, and display `CampaignReplyBreakdown` component in `app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue`
- [X] T022 [US2] Verify User Story 2 request and frontend tests pass via `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/requests/api/v1/accounts/campaigns/recipients_controller_spec.rb` and `docker compose exec vite pnpm test`

**Checkpoint**: At this point, User Stories 1 and 2 are functional. Managers can analyze campaign replies directly from the dashboard.

---

## Phase 5: User Story 3 - Workflow builder conditions automation on campaign origin (Priority: P3)

**Goal**: Enable automation rules to filter conversations by campaign (`campaign_id` equal to, not equal to, is present, is not present) for both `conversation_created` and `message_created` event triggers.

**Independent Test**: Configure automation rules with condition "Campaign" (`is_present`, `equal_to`), trigger matching and non-matching conversations, and verify rule actions execute only for matching attributed conversations.

### Implementation & Tests for User Story 3

- [X] T023 [P] [US3] Add a `context 'when filtering campaign_id'` block testing `ConditionsFilterService` query generation with `campaign_id` filter operators and values to the existing `spec/services/automation_rules/conditions_filter_service_spec.rb` — matching the established convention this fork already used for the `campaign_referral_present` condition (feature 031), not a new `custom/spec/` file
- [X] T024 [US3] Add `campaign_id` attribute configuration with standard filter operators under `conversations:` in `lib/filters/filter_keys.yml`
- [X] T025 [P] [US3] Add i18n label for `CAMPAIGN` attribute in `app/javascript/dashboard/i18n/locale/en/automation.json`
- [X] T026 [P] [US3] Add i18n label for `CAMPAIGN` attribute in Portuguese in `app/javascript/dashboard/i18n/locale/pt_BR/automation.json`
- [X] T027 [P] [US3] Add `campaign_id` condition definition to `conversation_created` and `message_created` events in `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js`
- [X] T028 [US3] Add `campaign_id: generateConditionOptions(campaigns)` mapping in `app/javascript/dashboard/helper/automationHelper.js`
- [X] T029 [US3] Verify User Story 3 automation specs pass via `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec spec/services/automation_rules/conditions_filter_service_spec.rb` and `docker compose exec vite pnpm test`

**Checkpoint**: All three user stories are functional and independently verified.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Verification of sync hooks, linting compliance, and end-to-end quality gates

- [X] T030 [P] Register upstream file insertion anchors for `config/routes.rb`, `lib/filters/filter_keys.yml`, `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js`, and `app/javascript/dashboard/helper/automationHelper.js` in `bin/sync-custom-module-hooks`
- [X] T031 Verify sync hooks and audit pass via `docker compose exec rails ruby bin/sync-custom-module-hooks --check && docker compose exec rails ruby bin/sync-custom-module-hooks --audit`
- [X] T032 [P] Run RuboCop and auto-fix across backend files to ensure 0 offenses via `docker compose exec rails bundle exec rubocop -a`
- [X] T033 [P] Run ESLint on frontend codebase via `docker compose exec vite pnpm eslint`
- [X] T034 Run full test suite for custom and modified components via `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/ spec/services/automation_rules/conditions_filter_service_spec.rb` and `docker compose exec vite pnpm test`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational phase completion (T003-T007) - provides core attribution and recipient tracking
- **User Story 2 (Phase 4)**: Depends on Foundational phase completion (T003-T007); consumes recipient data populated by US1
- **User Story 3 (Phase 5)**: Depends on Foundational phase completion (T003-T007); filters `conversations.campaign_id` populated by US1
- **Polish (Phase 6)**: Depends on completion of all desired user stories

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories
- **User Story 2 (P2)**: Can start after Foundational (Phase 2) - Independently testable using mock or seeded `Custom::CampaignRecipient` records
- **User Story 3 (P3)**: Can start after Foundational (Phase 2) - Independently testable using conversations with `campaign_id`

### Within Each User Story

- Test specifications written and verified before implementation completes
- Data models and services before controllers and routes
- Backend APIs before frontend components
- Translations (en + pt_BR synchronously) before UI component consumption

### Parallel Opportunities

- In Phase 1: T002 runs in parallel with directory setup T001
- In Phase 2: T005 (`Custom::CampaignRecipient`), T006 (`Custom::Campaign`), and T007 (`campaign_recipient_spec.rb`) can proceed in parallel once T004 migration completes
- In Phase 3 (US1): Specs T008 and T009 can be written in parallel
- In Phase 4 (US2): Request spec T014, translation tasks T017/T018, and Vue component T020 can be created in parallel with controller T016
- In Phase 5 (US3): Spec T023, translation tasks T025/T026, and constants definition T027 can proceed in parallel with filter keys T024
- In Phase 6: Sync hook registration T030, RuboCop T032, and ESLint T033 can run in parallel

---

## Parallel Example: User Story 1

```bash
# Launch specs in parallel:
Task: "T008 [P] [US1] Create unit and integration spec in custom/spec/services/custom/whatsapp/oneoff_campaign_service_spec.rb"
Task: "T009 [P] [US1] Create unit and integration spec in custom/spec/services/custom/whatsapp/incoming_message_base_service_spec.rb"

# Implement services sequentially or concurrently:
Task: "T010 [US1] Implement Custom::Whatsapp::OneoffCampaignService"
Task: "T011 [US1] Implement Custom::Whatsapp::IncomingMessageBaseService#process_statuses"
Task: "T012 [US1] Implement Custom::Whatsapp::IncomingMessageBaseService#set_conversation"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T002)
2. Complete Phase 2: Foundational (T003-T007) — Database table and model ready
3. Complete Phase 3: User Story 1 (T008-T013) — Send tracking, webhook status updates, reply correlation, context message backfill
4. **STOP and VALIDATE**: Verify User Story 1 end-to-end via Rails console and test scenarios in [quickstart.md](./quickstart.md) (Scenarios 1-5)

### Incremental Delivery

1. Setup + Foundational → Database schema and model foundation ready
2. User Story 1 (MVP) → Agents immediately see campaign context and button tapped in conversations
3. User Story 2 → Campaign managers gain full visibility into delivery metrics and button click rates in dashboard
4. User Story 3 → Workflow builders can route and tag conversations based on originating campaign
5. Polish → Sync hooks registered, RuboCop clean, ESLint clean, test suites green

---

## Notes

- All tasks strictly follow `- [ ] [TaskID] [P?] [Story?] Description with file path`
- [P] indicates tasks in different files with no dependencies on incomplete tasks
- [Story] label ([US1], [US2], [US3]) indicates the corresponding story from spec.md
- Synchronous English and Portuguese translations maintained per project constitution
- Pre-commit/commit constraint: Always obtain explicit user confirmation before committing or pushing
