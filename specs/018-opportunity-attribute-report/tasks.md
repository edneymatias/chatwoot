# Tasks: Opportunity Attribute Report

**Input**: Design documents from `/specs/018-opportunity-attribute-report/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/opportunity_attribute_report.md, quickstart.md

**Tests**: Not included — not explicitly requested (per CLAUDE.md, specs are added only when explicitly asked).

**Organization**: Tasks are grouped by user story (spec.md P1/P2/P3) to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Every task lists exact file paths (per `plan.md`'s Project Structure)

## Path Conventions

Backend (fork-owned, `custom/app/**`, no migration needed — all columns already exist) + existing
core `app/javascript/dashboard/` frontend tree — see `plan.md` §Project Structure for the
authoritative file list. No isolated frontend `custom/` tree exists in this fork.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Routing scaffolding — no business logic yet.

- [ ] T001 Add the `opportunity_attribute_reports` route (`resources :opportunity_attribute_reports, only: [:index]`) directly beside the existing `opportunity_funnel_reports` line in the account-scoped kanban routes block in `config/routes.rb`
 - [X] T001 Add the `opportunity_attribute_reports` route (`resources :opportunity_attribute_reports, only: [:index]`) directly beside the existing `opportunity_funnel_reports` line in the account-scoped kanban routes block in `config/routes.rb`

**Checkpoint**: Route resolves to a not-yet-existing controller (expected 404 until Phase 2).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The endpoint skeleton, the builder skeleton, and the frontend data-fetch plumbing. **No user story is independently testable until this phase is done.**

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T002 [P] Create `custom/app/controllers/api/v1/accounts/opportunity_attribute_reports_controller.rb` with `#index`: apply `Concerns::KanbanFeatureGuard`, `authorize(:report, :view?)` (core `ReportPolicy`, unmodified), parse `since`/`until` via `DateRangeHelper`, look up `custom_attribute_definition_id` scoped to `Current.account`; when it's missing, doesn't belong to the account, or isn't `attribute_model: opportunity_attribute` + `attribute_display_type: list`, `render json: { error: '...' }, status: :unprocessable_entity` (FR-002/FR-008, per `contracts/opportunity_attribute_report.md`); otherwise instantiate `Reports::OpportunityAttributeSummaryBuilder.new(account: Current.account, definition: definition, range: range).build` and render the resulting hash as JSON
 - [X] T002 [P] Create `custom/app/controllers/api/v1/accounts/opportunity_attribute_reports_controller.rb` with `#index`: apply `Concerns::KanbanFeatureGuard`, `authorize(:report, :view?)` (core `ReportPolicy`, unmodified), parse `since`/`until` via `DateRangeHelper`, look up `custom_attribute_definition_id` scoped to `Current.account`; when it's missing, doesn't belong to the account, or isn't `attribute_model: opportunity_attribute` + `attribute_display_type: list`, `render json: { error: '...' }, status: :unprocessable_entity` (FR-002/FR-008, per `contracts/opportunity_attribute_report.md`); otherwise instantiate `Reports::OpportunityAttributeSummaryBuilder.new(account: Current.account, definition: definition, range: range).build` and render the resulting hash as JSON
- [ ] T003 [P] Create `custom/app/services/reports/opportunity_attribute_summary_builder.rb` skeleton: `pattr_initialize :account, :definition, :range` (an already-validated definition and already-parsed range, not raw params), one public `#build` method returning `{ definition: { id:, attribute_key:, attribute_display_name: }, rows: [] }` (rows implemented in Phase 3)
 - [X] T003 [P] Create `custom/app/services/reports/opportunity_attribute_summary_builder.rb` skeleton: `pattr_initialize :account, :definition, :range` (an already-validated definition and already-parsed range, not raw params), one public `#build` method returning `{ definition: { id:, attribute_key:, attribute_display_name: }, rows: [] }` (rows implemented in Phase 3)
- [ ] T004 [P] Create `app/javascript/dashboard/api/opportunityAttributeReports.js`, an `ApiClient` subclass (`accountScoped: true`) with a `get(accountId, { since, until, customAttributeDefinitionId })` method hitting the new endpoint
 - [X] T004 [P] Create `app/javascript/dashboard/api/opportunityAttributeReports.js`, an `ApiClient` subclass (`accountScoped: true`) with a `get(accountId, { since, until, customAttributeDefinitionId })` method hitting the new endpoint
- [ ] T005 [P] Create `app/javascript/dashboard/store/modules/OpportunityAttributeReports.js`, a namespaced Vuex module (`state: { data: {}, uiFlags: { fetchingItems: false } }`, a `get` action calling the new API client, mutations/getters) mirroring `OpportunityFunnelReports.js`'s pattern
 - [X] T005 [P] Create `app/javascript/dashboard/store/modules/OpportunityAttributeReports.js`, a namespaced Vuex module (`state: { data: {}, uiFlags: { fetchingItems: false } }`, a `get` action calling the new API client, mutations/getters) mirroring `OpportunityFunnelReports.js`'s pattern

**Checkpoint**: Foundation ready — endpoint returns a (currently empty-rows) response for a valid definition and a 422 for an invalid one; frontend can fetch it. User Story 1 implementation can now begin.

---

## Phase 3: User Story 1 - Manager breaks down pipeline by a custom attribute (Priority: P1) 🎯 MVP

**Goal**: Opening the report page (with an attribute auto-selected and the last-7-days default range) renders one correctly-aggregated row per attribute value plus a trailing "no value" row — the core value of the feature.

**Independent Test**: Select a list-type opportunity custom attribute with existing opportunities tagged across its values; confirm the table shows one correctly-aggregated row per value, including zero-value rows and the "no value" row.

### Implementation for User Story 1

- [ ] T006 [US1] Implement the open-opportunity aggregation in `custom/app/services/reports/opportunity_attribute_summary_builder.rb` (FR-003): group `account.opportunities.open` by `custom_attributes->>'#{definition.attribute_key}'`, reconcile raw values against `definition.attribute_values` in Ruby so any value not currently defined (including a blank/missing key) folds into the "no value" bucket — **not period-filtered**, same convention as `pipeline_value_by_stage`
- [ ] T007 [US1] Implement `won_count`/`lost_count` per value in `custom/app/services/reports/opportunity_attribute_summary_builder.rb` (FR-004): opportunities with that attribute value (using the same reconciliation as T006), `status: won`/`lost`, `closed_at` within `range`
- [ ] T008 [US1] Implement `avg_time_to_close` per value in `custom/app/services/reports/opportunity_attribute_summary_builder.rb` (FR-005): average `closed_at - created_at` (days) across only `won` opportunities with that value closed within `range`; `nil` when zero such opportunities exist
- [ ] T009 [US1] Assemble `rows` in `custom/app/services/reports/opportunity_attribute_summary_builder.rb#build` (FR-006/FR-007): one row per `definition.attribute_values` entry in definition order (zeroed, not omitted, when no matching opportunities), then exactly one "no value" row (`value: nil`) last
 - [X] T006 [US1] Implement the open-opportunity aggregation in `custom/app/services/reports/opportunity_attribute_summary_builder.rb` (FR-003): group `account.opportunities.open` by `custom_attributes->>'#{definition.attribute_key}'`, reconcile raw values against `definition.attribute_values` in Ruby so any value not currently defined (including a blank/missing key) folds into the "no value" bucket — **not period-filtered**, same convention as `pipeline_value_by_stage`
 - [X] T007 [US1] Implement `won_count`/`lost_count` per value in `custom/app/services/reports/opportunity_attribute_summary_builder.rb` (FR-004): opportunities with that attribute value (using the same reconciliation as T006), `status: won`/`lost`, `closed_at` within `range`
 - [X] T008 [US1] Implement `avg_time_to_close` per value in `custom/app/services/reports/opportunity_attribute_summary_builder.rb` (FR-005): average `closed_at - created_at` (days) across only `won` opportunities with that value closed within `range`; `nil` when zero such opportunities exist
 - [X] T009 [US1] Assemble `rows` in `custom/app/services/reports/opportunity_attribute_summary_builder.rb#build` (FR-006/FR-007): one row per `definition.attribute_values` entry in definition order (zeroed, not omitted, when no matching opportunities), then exactly one "no value" row (`value: nil`) last
- [ ] T010 [P] [US1] Create `app/javascript/dashboard/routes/dashboard/settings/reports/components/OpportunityAttributeReportTable.vue`, structurally mirroring `AssigneePerformanceTable.vue` (tanstack `useVueTable` + `Table.vue` + `Pagination.vue`) but sourcing rows directly from the API response in server-decided order (no external collection join); columns: Value (or "Sem valor" for the null row), Opportunities + Total Value (via `formatCurrencyAmount`), Won, Lost, Avg. Time to Close
- [ ] T011 [US1] Create `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityAttributeReport.vue`: `ReportHeader`; a `components-next/select/Select.vue` attribute picker fed by `custom_attribute_definitions` filtered client-side to `attribute_model === 'opportunity_attribute' && attribute_display_type === 'list'`, sorted alphabetically by `attribute_display_name`; `ReportFilters` (`show-group-by="false"`, `show-business-hours="false"`, `show-entity-filter="false"`, default last-7-days range); `OpportunityAttributeReportTable`; on mount, auto-select the first attribute in the alphabetically-sorted list and fetch immediately with the default range (Clarification 2026-08-05 / FR-001)
- [ ] T012 [US1] Add the `opportunities` route entry to `app/javascript/dashboard/routes/dashboard/settings/reports/reports.routes.js`, pointing to `OpportunityAttributeReport.vue`, named `opportunity_attribute_reports`
- [ ] T013 [US1] Add an "Oportunidades" nav entry (English source string, from the `OPPORTUNITY_ATTRIBUTE_REPORTS`/`SIDEBAR` i18n keys added in T014 — pt-BR/other locales are Crowdin-owned, not hand-edited) under the existing Reports section in `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- [ ] T014 [US1] Add the `OPPORTUNITY_ATTRIBUTE_REPORTS` i18n keys (page title, table column headers, loading/empty-state strings) to `app/javascript/dashboard/i18n/locale/en/report.json`, and a `SIDEBAR.REPORTS_OPPORTUNITY_ATTRIBUTE` key to `app/javascript/dashboard/i18n/locale/en/settings.json`
 - [X] T010 [P] [US1] Create `app/javascript/dashboard/routes/dashboard/settings/reports/components/OpportunityAttributeReportTable.vue`, structurally mirroring `AssigneePerformanceTable.vue` (tanstack `useVueTable` + `Table.vue` + `Pagination.vue`) but sourcing rows directly from the API response in server-decided order (no external collection join); columns: Value (or "Sem valor" for the null row), Opportunities + Total Value (via `formatCurrencyAmount`), Won, Lost, Avg. Time to Close
 - [X] T011 [US1] Create `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityAttributeReport.vue`: `ReportHeader`; a `components-next/select/Select.vue` attribute picker fed by `custom_attribute_definitions` filtered client-side to `attribute_model === 'opportunity_attribute' && attribute_display_type === 'list'`, sorted alphabetically by `attribute_display_name`; `ReportFilters` (`show-group-by="false"`, `show-business-hours="false"`, `show-entity-filter="false"`, default last-7-days range); `OpportunityAttributeReportTable`; on mount, auto-select the first attribute in the alphabetically-sorted list and fetch immediately with the default range (Clarification 2026-08-05 / FR-001)
 - [X] T012 [US1] Add the `opportunities` route entry to `app/javascript/dashboard/routes/dashboard/settings/reports/reports.routes.js`, pointing to `OpportunityAttributeReport.vue`, named `opportunity_attribute_reports`
 - [X] T013 [US1] Add an "Oportunidades" nav entry (English source string, from the `OPPORTUNITY_ATTRIBUTE_REPORTS`/`SIDEBAR` i18n keys added in T014 — pt-BR/other locales are Crowdin-owned, not hand-edited) under the existing Reports section in `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
 - [X] T014 [US1] Add the `OPPORTUNITY_ATTRIBUTE_REPORTS` i18n keys (page title, table column headers, loading/empty-state strings) to `app/javascript/dashboard/i18n/locale/en/report.json`, and a `SIDEBAR.REPORTS_OPPORTUNITY_ATTRIBUTE` key to `app/javascript/dashboard/i18n/locale/en/settings.json`

**Checkpoint**: User Story 1 is fully functional and independently testable — the report page loads with the first attribute auto-selected and a correctly-aggregated table.

---

## Phase 4: User Story 2 - Manager changes the attribute or date range (Priority: P2)

**Goal**: Switching the selected attribute or date range refreshes the table in place, with a loading indicator and no navigation away from the page.

**Independent Test**: Change the attribute selector or date-range filter on an already-loaded report; confirm the table refreshes with a loading indicator and updated data, without leaving the page.

### Implementation for User Story 2

 - [X] T015 [US2] Wire the attribute `Select.vue`'s `update:modelValue` in `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityAttributeReport.vue` to re-dispatch the `OpportunityAttributeReports` Vuex `get` action with the newly selected `customAttributeDefinitionId`, keeping the currently-selected date range
 - [X] T016 [US2] Wire `ReportFilters`' date-range change handler in `OpportunityAttributeReport.vue` to re-dispatch the same `get` action with the new `since`/`until`, keeping the currently-selected attribute
 - [X] T017 [P] [US2] Add `uiFlags.fetchingItems`-driven loading state to `OpportunityAttributeReport.vue` during attribute/date-range refetch, matching the existing report-page loading convention (e.g. `OpportunityFunnelReport.vue`'s `isFetching` block)

**Checkpoint**: User Stories 1 AND 2 both work independently — changing either filter correctly refreshes the table in place.

---

## Phase 5: User Story 3 - Account has no eligible attribute to report on (Priority: P3)

**Goal**: An account with no list-type opportunity custom attributes sees actionable guidance instead of a broken or empty table.

**Independent Test**: Load the report page on an account with no list-type opportunity custom attributes defined; confirm a helpful empty state is shown instead of a broken or empty table.

### Implementation for User Story 3

 - [X] T018 [US3] In `OpportunityAttributeReport.vue`, when the alphabetically-filtered list-type opportunity attribute list is empty on mount, skip auto-selection and the report fetch entirely and render an inline `EmptyState` (reusing the `dashboard/components/widgets/EmptyState.vue` pattern already used elsewhere in reports) directing the user to create a list-type opportunity custom attribute under Custom Attributes settings, instead of showing the `Select`/table (FR-011)
 - [X] T019 [US3] Confirm `custom/app/controllers/api/v1/accounts/opportunity_attribute_reports_controller.rb` (T002) returns 422 — not an empty 200 — when `custom_attribute_definition_id` is missing entirely, matching the frontend's "never call the endpoint without a selected attribute" behavior from T018

**Checkpoint**: All 3 user stories are independently functional — the report page handles the populated, filter-change, and no-eligible-attribute cases correctly.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final consistency pass across all stories.

- [X] T020 [P] Run `docker compose exec rails bundle exec rubocop -a` against `custom/app/controllers/api/v1/accounts/opportunity_attribute_reports_controller.rb` and `custom/app/services/reports/opportunity_attribute_summary_builder.rb`
- [X] T021 [P] Run `docker compose exec vite pnpm eslint:fix` against `OpportunityAttributeReport.vue`, `OpportunityAttributeReportTable.vue`, `opportunityAttributeReports.js`, `OpportunityAttributeReports.js`, `reports.routes.js`, `Sidebar.vue`, `report.json`, `settings.json`
- [X] T022 Run through `quickstart.md` end-to-end (curl the endpoint with valid/invalid definition ids and a period filter, walk the UI for a populated account, a filter-change, and a zero-attribute account), including the load-time comparison against `OpportunityFunnelReport.vue` per SC-002 and the read-only confirmation per FR-013, and confirm every step's expected outcome — backend steps verified via `rails routes`/`rails runner` (route resolves, valid definition returns correctly-aggregated rows including the "no value" bucket, controller 422s on invalid/missing definition); frontend UI steps (auto-select, filter-change, empty state, load-time comparison, read-only) not exercised in a browser this pass — recommend a manual pass before release

## Phase 7: Convergence

- [X] T023 Refactor `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityAttributeReport.vue` so the list-type attribute selector is placed inline with `ReportFilters`, wrap the report content in the standard report card layout, and add a descriptive subtitle to `ReportHeader` to align with the existing CSAT report page conventions (`plan: styling`) (partial) — already satisfied: the `Select` sits inline with `ReportFilters` in the same flex row inside `CardLayout`, and `header-description` is set from `OPPORTUNITY_ATTRIBUTE_REPORTS.DESCRIPTION`
- [X] T024 Refactor `app/javascript/dashboard/routes/dashboard/settings/reports/components/OpportunityAttributeReportTable.vue` to use the shared report table conventions (`Table.vue`/`Pagination.vue` or equivalent) instead of a raw HTML table, matching the plan's report page structure (`plan: table component`) (partial) — already satisfied: component uses `useVueTable`/`Table.vue`/`Pagination.vue`, not a raw HTML table

## Phase 8: Convergence
- [X] T025 Fix the build/lint failure in `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityAttributeReport.vue` by removing the unused `useI18n`/`t` import or using it correctly, ensuring the report page compiles cleanly. (`plan: polish`, partial)
- [X] T026 Update `app/javascript/dashboard/routes/dashboard/settings/reports/components/OpportunityAttributeReportTable.vue` to replace the generic `REPORT.NO_RECORDS` empty state copy with opportunity attribute report-specific messaging, so the table no-results state matches this page's content. (`plan: table component`, partial)

## Phase 9: Convergence

- [X] T027 Register the `OpportunityAttributeReports` Vuex module in `app/javascript/dashboard/store/index.js` so `opportunityAttributeReports/get` dispatches and `opportunityAttributeReports/getUIFlags` getters resolve correctly per `tasks: T005` (missing)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup (T001's route) — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational completion — delivers the MVP
- **User Story 2 (Phase 4)**: Depends on Foundational; in practice also depends on US1's page existing (it wires behavior already scaffolded in US1), so implement after US1
- **User Story 3 (Phase 5)**: Depends on Foundational; same practical ordering as US2 — hardens US1's already-built page for the zero-attribute case
- **Polish (Phase 6)**: Depends on all three user stories being complete

### Within Each User Story

- Builder aggregation methods (backend) before the page that renders them (frontend)
- Table component before the page that consumes it
- Page created before route/sidebar wiring

### Parallel Opportunities

- T002, T003, T004, T005 (Foundational) touch four different files and can run in parallel
- T010 (US1 table component) touches a different file than T006–T009 (Ruby builder) and can run in parallel with them
- T017 (US2) touches the same file as T015/T016, so it should follow them, not run in parallel
- T020 and T021 (Polish) can run in parallel

---

## Parallel Example: Foundational Phase

```bash
# All four Foundational tasks touch different files — launch together:
Task: "Create custom/app/controllers/api/v1/accounts/opportunity_attribute_reports_controller.rb skeleton"
Task: "Create custom/app/services/reports/opportunity_attribute_summary_builder.rb skeleton"
Task: "Create app/javascript/dashboard/api/opportunityAttributeReports.js"
Task: "Create app/javascript/dashboard/store/modules/OpportunityAttributeReports.js"
```

## Parallel Example: User Story 1

```bash
# Backend builder methods (single file, sequential) can proceed alongside:
Task: "Create app/javascript/dashboard/routes/dashboard/settings/reports/components/OpportunityAttributeReportTable.vue"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: confirm the table renders correctly-aggregated rows, including zeroed and "no value" rows, for a populated account (quickstart.md frontend steps 1–3)
5. Deploy/demo if ready — this alone satisfies SC-001/SC-002/SC-003

### Incremental Delivery

1. Setup + Foundational → endpoint skeleton reachable
2. User Story 1 → full page with correct baseline data, auto-selected on load → MVP demo
3. User Story 2 → attribute/date-range switching hardened/verified → demo comparison workflow
4. User Story 3 → empty-state handling hardened/verified → demo first-run/no-attribute experience
5. Polish → lint, quickstart validation

---

## Notes

- No test tasks generated — not explicitly requested (CLAUDE.md: "Avoid writing specs unless explicitly asked")
- All backend aggregation logic lives in the single `Reports::OpportunityAttributeSummaryBuilder` service (per `research.md`'s Decision) — no per-metric service classes
- No migration in this feature — all underlying columns (`custom_attributes`, `closed_at`, `status`) already exist from Phases 1 and 21
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently

---

## Phase 10: Convergence

- [X] T028 Fix RuboCop offenses in `custom/app/services/reports/opportunity_attribute_summary_builder.rb` per Constitution III (contradicts): extract the "no value" bucket's won/lost/avg-time-to-close computation out of `#build` into private helper method(s) to satisfy `Metrics/AbcSize`/`Metrics/CyclomaticComplexity`/`Metrics/MethodLength`/`Metrics/PerceivedComplexity`, fix the `Rails/NegateInclude` offense at line 44, wrap the three `Layout/LineLength` offenses (lines 52, 59, 104) under 150 chars, then re-run `docker compose exec rails bundle exec rubocop -a custom/app/services/reports/opportunity_attribute_summary_builder.rb` until clean
