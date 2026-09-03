# Tasks: Ad Campaign Performance Report

**Input**: Design documents from `specs/044-campaign-performance-report/`  
**Prerequisites**: `plan.md`, `spec.md`, `data-model.md`, `contracts/`, `research.md`, `quickstart.md`  

## Format: `- [ ] [ID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files, no blocking dependencies)
- **[Story]**: User story identifier (`[US1]`, `[US2]`, `[US3]`)
- Every task includes explicit file paths

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify baseline test environments and define store mutation types.

- [x] T001 Verify baseline backend RSpec and frontend Vitest suites run cleanly via `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/` and `docker compose exec vite pnpm test`
- [x] T002 [P] Add mutation types for `CampaignPerformanceReports` and `CampaignAttributionSettings` in `app/javascript/dashboard/store/mutation-types.js`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Database schema, model exclusivity, and shared stage-reach calculator service that all user stories depend on.

**⚠️ CRITICAL**: Must complete before User Story 1 and User Story 2 can compute milestone progress and generate reports.

- [x] T003 Create database migration `db/migrate/21260903000000_add_campaign_report_milestone_to_ichatr_pipeline_stages.rb` adding `campaign_report_milestone` boolean column (`default: false, null: false`) to `ichatr_pipeline_stages`
- [x] T004 [P] Add `campaign_report_milestone` attribute and single-stage exclusivity callback `ensure_single_lane_exclusivity_for_campaign_milestone` in `custom/app/models/pipeline_stage.rb`
- [x] T005 [P] Add unit tests for `PipelineStage` milestone exclusivity in `custom/spec/models/pipeline_stage_spec.rb`
- [x] T006 Extract shared "reached stage X" computation helper `Reports::StageReachCalculator` in `custom/app/services/reports/stage_reach_calculator.rb`
- [x] T007 Refactor `Reports::OpportunityFunnelBuilder` in `custom/app/services/reports/opportunity_funnel_builder.rb` to delegate `max_stage_positions_reached` to `Reports::StageReachCalculator` and verify existing funnel specs pass

**Checkpoint**: Foundation ready — milestone column and shared reach calculator are available for builder services and API endpoints.

---

## Phase 3: User Story 1 - View ad campaign performance summary (Priority: P1) 🎯 MVP

**Goal**: Deliver the Ad Campaign Performance report summary: date-range filtering, 7 summary KPI cards (or 6 if no milestone), sidebar navigation gating (enabled + resolved data present), and backend report builder/API.

**Independent Test**: Open Reports → "Campanhas de Anúncios" with a date filter. Verify total leads, won/lost metrics, distinct counts, and milestone card (when configured) match data for the range. Verify sidebar entry hides when attribution is disabled or no resolved data exists.

### Tests for User Story 1

- [x] T008 [P] [US1] Create request spec for `CampaignPerformanceReportsController` in `custom/spec/requests/api/v1/accounts/campaign_performance_reports_controller_spec.rb` verifying auth (`ReportPolicy`), date range filtering, and summary KPI response shape
- [x] T009 [P] [US1] Create unit tests for `Reports::CampaignPerformanceBuilder` summary calculation in `custom/spec/services/reports/campaign_performance_builder_spec.rb`, explicitly covering: (a) `base_scope` excludes opportunities with `campaign_resolution_status` in `organic_post`/`not_applicable` and with nil/blank `campaign_source_id` (FR-004/SC-003), and (b) when no stage has `campaign_report_milestone: true`, the summary hash omits the `milestone_count`/`milestone_rate_pct` keys entirely rather than returning zero (FR-005)
- [x] T010 [P] [US1] Update request spec in `custom/spec/controllers/api/v1/accounts/campaign_attribution_settings_controller_spec.rb` to verify `resolved_data_present` boolean field
- [x] T011 [P] [US1] Add Vitest unit tests for `CampaignPerformanceReports` and `CampaignAttributionSettings` Vuex modules in `app/javascript/dashboard/store/modules/specs/CampaignPerformanceReports.spec.js` and `app/javascript/dashboard/store/modules/specs/CampaignAttributionSettings.spec.js`
- [x] T012 [P] [US1] Add Vitest unit test for `CampaignPerformanceReport.vue` summary KPI cards and date filter in `app/javascript/dashboard/routes/dashboard/settings/reports/specs/CampaignPerformanceReport.spec.js`, explicitly covering the 6-card grid (no milestone card rendered) when the API response has no `milestone_stage_name` (FR-005/Acceptance Scenario 3)
- [x] T013 [P] [US1] Update `app/javascript/dashboard/components-next/sidebar/specs/Sidebar.spec.js` to cover the gated "Campanhas de Anúncios" nav entry: hidden when `campaignAttributionSettings` state has `enabled: false` or `resolved_data_present: false`, shown when both are `true` (SC-004)

### Implementation for User Story 1

- [x] T014 [US1] Implement `Reports::CampaignPerformanceBuilder` summary calculation (leads, won_count/won_rate_pct, lost_count/lost_rate_pct, milestone_count/milestone_rate_pct, distinct_campaigns, distinct_adsets, distinct_ads — field names per contracts/campaign-performance-reports.md) in `custom/app/services/reports/campaign_performance_builder.rb`
- [x] T015 [US1] Implement `Api::V1::Accounts::CampaignPerformanceReportsController` in `custom/app/controllers/api/v1/accounts/campaign_performance_reports_controller.rb` and register route in `config/routes.rb` (both API-version blocks)
- [x] T016 [US1] Update `Api::V1::Accounts::CampaignAttributionSettingsController#show` in `custom/app/controllers/api/v1/accounts/campaign_attribution_settings_controller.rb` to return `resolved_data_present`
- [x] T017 [P] [US1] Create API client `app/javascript/dashboard/api/campaignPerformanceReports.js`
- [x] T018 [P] [US1] Create Vuex module `app/javascript/dashboard/store/modules/CampaignPerformanceReports.js` and register in `app/javascript/dashboard/store/index.js`
- [x] T019 [P] [US1] Create Vuex module `app/javascript/dashboard/store/modules/CampaignAttributionSettings.js` and register in `app/javascript/dashboard/store/index.js`
- [x] T020 [US1] Add report route `campaign_performance_reports` in `app/javascript/dashboard/routes/dashboard/settings/reports/reports.routes.js`
- [x] T021 [US1] Update `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` to dispatch `campaignAttributionSettings/get` on mount and render gated "Campanhas de Anúncios" nav item under Reports
- [x] T022 [US1] Create report page `app/javascript/dashboard/routes/dashboard/settings/reports/CampaignPerformanceReport.vue` with `ReportHeader`, `ReportFilters` (date range), and summary KPI cards grid
- [x] T023 [P] [US1] Add i18n keys for sidebar item, report header, metrics, and empty state synchronously in `app/javascript/dashboard/i18n/locale/en/settings.json` and `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`

**Checkpoint**: User Story 1 complete & independently testable — summary report page loads with KPI cards and date filter, and sidebar navigation entry appears only when eligible.

---

## Phase 4: User Story 2 - Drill into performance by campaign, ad set, and ad (Priority: P2)

**Goal**: Provide hierarchical breakdown tables across "Campanhas", "Conjuntos", and "Criativos" tabs sorted by leads descending, with client-side tab switching without additional network requests and proper "Não identificado" grouping.

**Independent Test**: Load the report with multi-campaign lead data. Switch between the 3 tabs and confirm each table reflects the proper grouping hierarchy and leads-descending sort order with no extra network requests. Confirm unassigned/unresolved entries group under "Não identificado".

### Tests for User Story 2

- [x] T024 [P] [US2] Update unit tests in `custom/spec/services/reports/campaign_performance_builder_spec.rb` to cover `by_campaign`, `by_adset`, and `by_ad` breakdown arrays, "Não identificado" grouping, and sort order
- [x] T025 [P] [US2] Add Vitest unit tests for `CampaignPerformanceTable.vue` in `app/javascript/dashboard/routes/dashboard/settings/reports/components/specs/CampaignPerformanceTable.spec.js` covering 3-tab switching, table rendering, and conditional milestone column

### Implementation for User Story 2

- [x] T026 [US2] Implement grouping and breakdown generation for `by_campaign`, `by_adset`, and `by_ad` in `custom/app/services/reports/campaign_performance_builder.rb`
- [x] T027 [US2] Create breakdown table component `app/javascript/dashboard/routes/dashboard/settings/reports/components/CampaignPerformanceTable.vue` with 3 tabs, fixed leads descending sort, and conditional milestone column
- [x] T028 [US2] Integrate `CampaignPerformanceTable.vue` into `app/javascript/dashboard/routes/dashboard/settings/reports/CampaignPerformanceReport.vue`
- [x] T029 [P] [US2] Add i18n keys for breakdown tabs, table columns, and "Não identificado" label synchronously in `app/javascript/dashboard/i18n/locale/en/settings.json` and `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`

**Checkpoint**: User Stories 1 AND 2 complete — full report with summary cards and drilldown breakdown table works end-to-end.

---

## Phase 5: User Story 3 - Designate the funnel milestone stage (Priority: P3)

**Goal**: Allow pipeline administrators to designate exactly one pipeline stage per account as the funnel milestone tracked by the Ad Campaign Performance report directly from the stage add/edit forms.

**Independent Test**: In Settings → Pipeline Stages, open Add or Edit stage modal. Toggle "Usar como marco no Relatório de Campanhas de Anúncios" and save. Verify the stage saves with `campaign_report_milestone: true`, and designating another stage un-designates the previous one.

### Tests for User Story 3

- [x] T030 [P] [US3] Update request specs in `spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb` (core spec tree, no `custom/` prefix) to verify `campaign_report_milestone` parameter handling in create and update
- [x] T031 [P] [US3] Add Vitest unit tests for milestone toggle in `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/specs/EditPipelineStage.spec.js`

### Implementation for User Story 3

- [x] T032 [US3] Permit `:campaign_report_milestone` in `pipeline_stage_params` in `custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb`
- [x] T033 [P] [US3] Add milestone toggle checkbox to `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/AddPipelineStage.vue`
- [x] T034 [P] [US3] Add milestone toggle checkbox to `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/EditPipelineStage.vue`
- [x] T035 [P] [US3] Add i18n keys for milestone form toggle label and help text synchronously in `app/javascript/dashboard/i18n/locale/en/opportunities.json` and `app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json`

**Checkpoint**: All three user stories functional and independently manageable.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Automated test validation, lint verification, sync hooks audit, and manual scenario execution.

- [x] T036 [P] Run backend RSpec tests via `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/models/pipeline_stage_spec.rb custom/spec/services/reports/campaign_performance_builder_spec.rb custom/spec/requests/api/v1/accounts/campaign_performance_reports_controller_spec.rb custom/spec/controllers/api/v1/accounts/campaign_attribution_settings_controller_spec.rb spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb`
- [x] T037 [P] Run backend RuboCop checks via `docker compose exec rails bundle exec rubocop`
- [x] T038 [P] Run frontend Vitest test suite via `docker compose exec vite pnpm test`
- [x] T039 [P] Run frontend ESLint checks via `docker compose exec vite pnpm eslint`
- [x] T040 Verify sync custom module hooks via `docker compose exec rails ruby bin/sync-custom-module-hooks --check`
- [x] T041 Execute manual verification scenarios per `specs/044-campaign-performance-report/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — baseline verification starts immediately.
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories (migration, model exclusivity, `StageReachCalculator`).
- **User Story 1 (Phase 3 - P1)**: Depends on Phase 2 — MVP delivering the summary report and sidebar gating.
- **User Story 2 (Phase 4 - P2)**: Depends on Phase 3 (extends builder and report page with breakdown table).
- **User Story 3 (Phase 5 - P3)**: Depends on Phase 2 model/column changes; can run in parallel with US1/US2.
- **Polish (Phase 6)**: Depends on all user stories being completed.

### User Story Dependencies

- **US1 (P1)**: Unlocks the report page and API summary endpoint.
- **US2 (P2)**: Consumes data from the builder and mounts inside the US1 report page.
- **US3 (P3)**: Provides UI to configure the milestone stage used by US1 and US2.

### Within Each User Story

- Test tasks marked [P] can be drafted before or alongside implementations.
- Backend services and endpoints before frontend consumption.
- Vuex modules and API clients before report page assembly.
- Translations added synchronously in both `en` and `pt_BR`.

---

## Parallel Opportunities

- **Phase 1**: `T002` can run in parallel with setup checks.
- **Phase 2**: `T004` and `T005` (model + spec) can run in parallel with `T006` and `T007` (service extraction).
- **Phase 3**:
  - Tests `T008`, `T009`, `T010`, `T011`, `T012`, `T013` can run in parallel.
  - Frontend client/stores `T017`, `T018`, `T019` can run in parallel with backend endpoints `T015`, `T016`.
  - Translations `T023` can run in parallel with component work.
- **Phase 4**: `T024` (backend spec) and `T025` (table spec) can run in parallel; `T029` (i18n) can run in parallel.
- **Phase 5**: `T033` (`AddPipelineStage.vue`) and `T034` (`EditPipelineStage.vue`) can run in parallel with `T032` (controller permit) and `T035` (i18n).

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 (Setup) and Phase 2 (Foundational).
2. Complete Phase 3 (User Story 1).
3. **STOP and VALIDATE**: Test User Story 1 independently (Reports → "Campanhas de Anúncios" summary cards + date filtering).

### Incremental Delivery

1. Foundation ready (migration, model exclusivity, `StageReachCalculator`).
2. US1 delivers Summary Report & Sidebar gating (MVP).
3. US2 delivers Breakdown Table (Campanhas, Conjuntos, Criativos).
4. US3 delivers Milestone Stage Management UI.
5. Polish validates with full test suites, linters, and quickstart scenarios.

---

## Phase 7: Convergence

- [x] T042 Rename the `won`/`lost` keys to `won_count`/`lost_count` in `Reports::CampaignPerformanceBuilder#build_by_campaign`, `#build_by_adset`, and `#build_by_ad` (`custom/app/services/reports/campaign_performance_builder.rb`), and update the consuming `CampaignPerformanceTable.vue` (`row.won`/`row.lost` bindings) and `custom/spec/services/reports/campaign_performance_builder_spec.rb` assertions to match, so breakdown rows match the field names already documented in contracts/campaign-performance-reports.md and data-model.md per FR-008 (contradicts)
- [x] T043 Update `CampaignPerformanceReport.vue` so a zero-lead date range shows the normal summary cards (all at zero) and empty breakdown tables instead of swapping to the generic `EmptyState` placeholder, per spec.md's Edge Cases section for User Story 1 (contradicts)

---

## Phase 8: Convergence

- [x] T044 Remove the orphaned `CAMPAIGN_PERFORMANCE_REPORTS.EMPTY_STATE.TITLE`/`MESSAGE` keys from `app/javascript/dashboard/i18n/locale/en/report.json` and `app/javascript/dashboard/i18n/locale/pt_BR/report.json`, left unused after T043 removed the `EmptyState` usage from `CampaignPerformanceReport.vue`, per T043 (unrequested)
