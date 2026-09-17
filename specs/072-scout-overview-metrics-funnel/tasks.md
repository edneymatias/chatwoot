# Tasks: Scout Overview — Summary Metrics & Funnel Distribution

**Input**: Design documents from `/specs/072-scout-overview-metrics-funnel/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/api.md`, `quickstart.md`, `tdd/test-list.md`
**Tests**: Mandatory per Project Constitution (Principle VI: Test-Driven Development). Every behavior test must be observed failing before implementation.
**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story, with tests strictly preceding implementation.

## Format: `- [ ] [TaskID] [P?] [Story?] [Behavior?] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (`[US1]`, `[US2]`, `[US3]`)
- **[Behavior]**: Load-bearing behavior id (`[U1]`, `[A1]`, etc.) from `tdd/test-list.md`
- Exact file paths are provided for all tasks

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Route registrations, navigation scaffolding, API client scaffolding, and base translation keys.

- [X] T001 Register `scout_overview_reports` API route in `config/routes.rb` via `resources :scout_overview_reports, only: [:index]` within the account-scoped resources block
- [X] T002 [P] Create frontend API client module in `app/javascript/dashboard/api/scoutOverviewReports.js` with `getOverviewReport(accountId, { scoutId, range, timezoneOffset })`
- [X] T003 [P] Add base i18n translation keys for Scout Overview under `SCOUT.OVERVIEW` and `SIDEBAR.SCOUT_OVERVIEW` in English `app/javascript/dashboard/i18n/locale/en.json` and Portuguese `app/javascript/dashboard/i18n/locale/pt_BR.json`
- [X] T006 [P] Register `scout_overview` route as the first child of the Scout section in `app/javascript/dashboard/routes/dashboard/scout/scout.routes.js` with path `frontendURL('accounts/:accountId/scout/overview')`, permissions `['administrator', 'agent', 'custom_role']`, and featureFlag `FEATURE_FLAGS.SCOUT`
- [X] T007 [P] Add 'Scout Overview' item with `activeOn: ['scout_overview']` and `to: accountScopedRoute('scout_overview')` as the first child in the Scout section of `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`

**Checkpoint**: Shared infrastructure and routing scaffolding in place.

---

## Phase 2: User Story 1 — Tests First (Priority: P1) 🎯 MVP

**Goal**: Establish failing tests for all US1 unit behaviors before writing backend or frontend implementations.

> **CRITICAL: Write these tests FIRST, run them to observe failure for the right reason before implementing.**

- [X] T008 [P] [US1] [U1] [U2] [U3] [U4] [U5] [U6] [U7] [U8] [U9] [U10] [U11] [U12] [U13] [U21] [U22] [U23] [U24] [U25] [U26] [U27] [U28] [U29] [U30] Add request specs for `scout_overview_reports_controller` in `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb` testing authentication (401), non-member forbidden (403), `ScoutPolicy` access for agents and administrators (200), parameter validation (`scout_id` presence/existence, `range` validity), period filtering, summary outcome rate calculations with in-progress denominator, neutral `null` rates for unconfigured stages (`qualified_stage_id`, `unqualified_stage_id`, `rescue_stage_id` nil) or `total_handled == 0`, and empty period handling
- [X] T009 [P] [US1] [U31] [U32] [U33] [U34] [U35] [U36] Add Vitest component specs for `ScoutSummaryCard.vue` and `ScoutSelector.vue` in `app/javascript/dashboard/components-next/scout/overview/ScoutSummaryCard.spec.js` and `app/javascript/dashboard/components-next/scout/overview/ScoutSelector.spec.js` testing metric card rendering, formatted numbers, unit suffixes, neutral "—" state, and conditional selector visibility when `scouts.length > 1` vs `scouts.length === 1`
- [X] T028 [P] [US1] [U41] [U42] [U43] [U44] Add Vitest component specs for `ScoutOverview.vue` in `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js` testing initial load with five summary cards, empty state rendering when `total_handled === 0`, and re-fetching on period or scout changes without page reload

---

## Phase 3: User Story 1 — Implementation (Priority: P1)

**Goal**: Implement backend builder, controller, and frontend components to turn US1 unit and acceptance tests green.

- [X] T004 [US1] [U21] [U22] [U23] [U24] [U25] [U26] [U27] [U28] [U29] [U30] Create `custom/app/controllers/api/v1/accounts/scout_overview_reports_controller.rb` inheriting from `Api::V1::Accounts::BaseController`, enforcing: `scout_id` required integer existing in account (else 404/422), `range` required in `%w[7 30 this_month last_month]` (else 422), optional `timezone_offset` numeric string, and Pundit authorization via `ScoutPolicy` (`authorize :scout, :show?`) permitting agents and administrators (denying unauthenticated/non-members with 401 Unauthorized)
- [X] T005 [US1] [U1] [U2] Create base builder service in `custom/app/services/reports/scout_overview_builder.rb` with `pattr_initialize [:account!, :scout!, :range!, :timezone_offset]`, period range resolution for `%w[7 30 this_month last_month]` with viewer timezone support, and base lifetime scope `scout_handled_scope` defined as `account.opportunities.joins(origin_conversation: :inbox).where(inboxes: { id: scout.inboxes.select(:id) })`
- [X] T010 [US1] [U3] [U4] [U5] [U6] [U7] [U8] [U9] [U10] [U11] [U12] [U13] Implement summary metrics calculation in `custom/app/services/reports/scout_overview_builder.rb` computing: `total_handled` (`period_scope.count`, including In Progress opportunities), `qualification_rate` (`(qualified_count.to_f / total_handled * 100).round(2)` or `nil` if `scout.qualified_stage_id.nil?` or `total_handled == 0`), `disqualification_rate` (`(unqualified_count.to_f / total_handled * 100).round(2)` or `nil` if `scout.unqualified_stage_id.nil?` or `total_handled == 0`), `abandonment_rate` (`(rescue_count.to_f / total_handled * 100).round(2)` or `nil` if `scout.rescue_stage_id.nil?` or `total_handled == 0`), and `avg_messages_per_conversation` (average conversational messages where `message_type != 2` in `origin_conversation` or `nil` when no conversations in period)
- [X] T011 [P] [US1] [U31] [U32] [U33] Create `app/javascript/dashboard/components-next/scout/overview/ScoutSummaryCard.vue` component rendering metric title, value, unit/percentage, and neutral placeholder ("—") when value is null
- [X] T012 [P] [US1] [U34] [U35] [U36] Create `app/javascript/dashboard/components-next/scout/overview/ScoutSelector.vue` component that fetches Scouts from account, conditionally renders only when `scouts.length > 1` (hidden when single Scout), and emits selected scout ID
- [X] T013 [US1] [U41] [U42] [U43] [U44] Create `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.vue` page integrating `RangeSelector.vue` (defaulting to '7'), `ScoutSelector.vue`, the five `ScoutSummaryCard.vue` cards in a responsive grid, and `EmptyStateLayout.vue` when `total_handled === 0`, updating data via `scoutOverviewReports.js` without full page reload on filter changes
- [X] T029 [US1] [A1] Verify outer-loop acceptance test A1 is green: Scout with handled opportunities renders 5 summary cards with period calculations
- [X] T030 [US1] [A2] Verify outer-loop acceptance test A2 is green: changing period selector updates summary cards without full page reload
- [X] T031 [US1] [A3] Verify outer-loop acceptance test A3 is green: switching Scout selector isolates selected Scout data without contamination
- [X] T032 [US1] [A4] Verify outer-loop acceptance test A4 is green: unconfigured outcome stages render neutral placeholders ("—") without error
- [X] T033 [US1] [A5] Verify outer-loop acceptance test A5 is green: zero handled opportunities displays zero counts, null rates, and renders EmptyStateLayout

**Checkpoint**: User Story 1 is fully functional and all acceptance criteria A1–A5 are verified green.

---

## Phase 4: User Story 2 — See Where Handled Opportunities Stand in the Full Pipeline (Priority: P2)

**Goal**: An operator can see a pipeline-stage distribution chart showing which pipeline stage every opportunity the Scout has handled is in right now across the full account pipeline, as a current snapshot unaffected by the period selector.

### Tests for User Story 2

> **CRITICAL: Write these tests FIRST, run them to observe failure before implementing.**

- [X] T014 [P] [US2] [U14] [U15] [U16] Add request specs in `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb` verifying `pipeline_stage_distribution` returns all account pipeline stages in `position ASC` order with current counts (including 0 for empty stages), and that changing the `range` query parameter does not alter `pipeline_stage_distribution` counts
- [X] T015 [P] [US2] [U37] [U38] Add Vitest component specs for `PipelineDistributionChart.vue` in `app/javascript/dashboard/components-next/scout/overview/PipelineDistributionChart.spec.js` testing stage data mapping, ordering, and horizontal bar chart rendering

### Implementation for User Story 2

- [X] T016 [US2] [U14] [U15] [U16] Implement `pipeline_stage_distribution` aggregation in `custom/app/services/reports/scout_overview_builder.rb` by querying `scout_handled_scope` grouped by `pipeline_stage_id` across lifetime (no date filter), left-joining all account `pipeline_stages` sorted by `position ASC`, returning an array of `{ stage_id, stage_name, stage_position, count }`
- [X] T017 [P] [US2] [U37] [U38] Create `app/javascript/dashboard/components-next/scout/overview/PipelineDistributionChart.vue` horizontal bar chart component using `vue-chartjs` / Chart.js, rendering stage labels, counts, and bar tooltips
- [X] T018 [US2] [U37] [U38] Integrate `PipelineDistributionChart.vue` into `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.vue`, displaying the chart alongside the summary cards and hiding it in favor of `EmptyStateLayout` when no opportunities exist for the Scout
- [X] T034 [US2] [A6] Verify outer-loop acceptance test A6 is green: Scout-handled opportunities across pipeline stages display correct counts in position order
- [X] T035 [US2] [A7] Verify outer-loop acceptance test A7 is green: pipeline distribution chart remains unchanged when period selector changes

**Checkpoint**: User Stories 1 and 2 work together and all acceptance criteria A1–A7 are verified green.

---

## Phase 5: User Story 3 — See Interest Distribution Across Pipeline Stages (Priority: P3)

**Goal**: An operator with `interest_attribute_definition` configured on the Scout can view how different interest values are distributed across pipeline stages, or see a prominent call-to-action card navigating to `scout_funnel` when the interest field is not configured.

### Tests for User Story 3

> **CRITICAL: Write these tests FIRST, run them to observe failure before implementing.**

- [X] T019 [P] [US3] [U17] [U18] [U19] [U20] Add request specs in `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb` verifying `interest_by_stage` returns `{ configured: false }` when `scout.interest_attribute_definition` is nil, and `{ configured: true, attribute_name: "...", data: [...] }` with custom attribute values (including `null` key) grouped by stage when configured across lifetime
- [X] T020 [P] [US3] [U39] [U40] Add Vitest component specs for `InterestByStageCard.vue` in `app/javascript/dashboard/components-next/scout/overview/InterestByStageCard.spec.js` testing both configured breakdown state and unconfigured CTA button navigation to `scout_funnel`

### Implementation for User Story 3

- [X] T021 [US3] [U17] [U18] [U19] [U20] Implement `interest_by_stage` in `custom/app/services/reports/scout_overview_builder.rb` returning `{ configured: false }` when `scout.interest_attribute_definition_id.nil?`, or `{ configured: true, attribute_name: defn.attribute_name, data: [...] }` grouping `scout_handled_scope` by `pipeline_stage_id` and `custom_attributes ->> defn.attribute_key` without date filtering (with `null` key representing opportunities with no value)
- [X] T022 [P] [US3] [U39] [U40] Create `app/javascript/dashboard/components-next/scout/overview/InterestByStageCard.vue` component displaying either a stacked breakdown by interest value per stage when `configured: true`, or an explanatory notice with a CTA button navigating to the Scout Funnel configuration screen (`scout_funnel` route) when `configured: false`
- [X] T023 [US3] [U39] [U40] Integrate `InterestByStageCard.vue` into `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.vue` below or alongside the pipeline distribution chart
- [X] T036 [US3] [A8] Verify outer-loop acceptance test A8 is green: Scout with interest attribute definition displays per-stage breakdown
- [X] T037 [US3] [A9] Verify outer-loop acceptance test A9 is green: Scout without interest attribute definition displays CTA card navigating to scout_funnel

**Checkpoint**: All three user stories are functional, integrated, and acceptance criteria A1–A9 are verified green.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Translation completeness, code quality verification, lint compliance, and quickstart end-to-end validation.

- [X] T024 [P] Validate and finalize all English and Portuguese translations in `app/javascript/dashboard/i18n/locale/en.json` and `app/javascript/dashboard/i18n/locale/pt_BR.json` for all overview labels, cards, tooltips, and empty states
- [X] T025 Run RuboCop check on modified backend files via `docker compose exec rails bundle exec rubocop custom/app/controllers/api/v1/accounts/scout_overview_reports_controller.rb custom/app/services/reports/scout_overview_builder.rb custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb` to ensure zero offenses
- [X] T026 Run ESLint check on modified frontend files via `docker compose exec vite pnpm eslint app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.vue app/javascript/dashboard/components-next/scout/overview/` to ensure zero offenses
- [X] T027 Execute end-to-end quickstart validation scenarios from `specs/072-scout-overview-metrics-funnel/quickstart.md` verifying API responses, agent role authorization, unconfigured states, and frontend rendering on localhost


---

## Phase 7: TDD remediation

**Goal**: Clear blocking findings identified by `/speckit.tdd.verify` to achieve TDD verification pass.

> **CRITICAL: The feature is NOT complete until all blocking findings in this phase are cleared and verified green.**

- [X] T038 [HIGH] [Finding 1] [U10] Add direct unit specs for `Reports::ScoutOverviewBuilder` in `custom/spec/services/reports/scout_overview_builder_spec.rb` asserting strictly `nil` rates (non-NaN) and confirming early-return short-circuit avoids database grouping queries when `total_handled == 0`, and harden `compute_rate` with `return nil if total.to_i.zero?` in `custom/app/services/reports/scout_overview_builder.rb:88` (`docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/services/reports/scout_overview_builder_spec.rb`)
- [X] T039 [MED] [Finding 2] [U29] Strengthen timezone offset spec in `custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb:259` by creating opportunity on UTC month boundary and verifying `total_handled` count shifts between UTC and provided offset (`docker compose exec -T rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/requests/api/v1/accounts/scout_overview_reports_controller_spec.rb -e "with timezone offset"`)
- [X] T040 [MED] [Finding 3] [U22] Align `specs/072-scout-overview-metrics-funnel/tdd/test-list.md:65` and `tasks.md:47` behavior description for U22 to reflect actual HTTP 401 Unauthorized returned by `BaseController#current_account` for non-account members
- [X] T041 [LOW] [Finding 4] [U43, U44] Tighten `timezoneOffset` assertion in `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js:105,123` to assert explicit expected offset string under UTC test runner (`docker compose exec -T vite env TZ=UTC pnpm vitest run app/javascript/dashboard/routes/dashboard/scout/pages/ScoutOverview.spec.js`)
---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **US1 Tests First (Phase 2)**: Depends on Setup completion
- **US1 Implementation (Phase 3)**: Depends on US1 Tests being observed failing
- **US2 (Phase 4)**: Depends on US1 completion — Tests first, then implementation
- **US3 (Phase 5)**: Depends on US1/US2 completion — Tests first, then implementation
- **Polish (Phase 6)**: Depends on all user stories and acceptance criteria A1–A9 being verified green

### Within Each User Story

- Tests MUST be written and observed failing before implementation (Principle VI: TDD)
- Service layer aggregations before frontend component integration
- Leaf components (`ScoutSummaryCard`, `ScoutSelector`, `PipelineDistributionChart`, `InterestByStageCard`) before parent page integration (`ScoutOverview.vue`)
- Final acceptance task (`[A1]`..`[A9]`) verifies outer loop is green before the story is considered complete
