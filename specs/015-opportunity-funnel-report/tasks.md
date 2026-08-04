# Tasks: Opportunity Funnel Report

**Input**: Design documents from `/specs/015-opportunity-funnel-report/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/opportunity_funnel_report.md, quickstart.md

**Tests**: Not included — not explicitly requested (per CLAUDE.md, specs are added only when explicitly asked).

**Organization**: Tasks are grouped by user story (spec.md P1/P2/P3) to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Every task lists exact file paths (per `plan.md`'s Project Structure)

## Path Conventions

Backend (fork-owned, `custom/app/**`) + one core-shared migration + existing
core `app/javascript/dashboard/` frontend tree — see `plan.md` §Project
Structure for the authoritative file list. No isolated frontend `custom/`
tree exists in this fork.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Additive schema change and routing scaffolding — no business logic yet.

- [X] T001 Generate and write the migration (`bundle exec rails g migration AddClosedAtToMatiasOpportunities`) adding a nullable `closed_at:datetime` column to `matias_opportunities` plus a `[account_id, closed_at]` index, in `db/migrate/<timestamp>_add_closed_at_to_matias_opportunities.rb` (per `data-model.md`)
- [X] T002 [P] Add the `opportunity_funnel_reports` route (`resources :opportunity_funnel_reports, only: [:index]`) to the existing account-scoped kanban routes block in `config/routes.rb`

**Checkpoint**: Schema migrated, route resolves to a not-yet-existing controller (expected 404 until Phase 2).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure every user story depends on — the `closed_at` lifecycle, the endpoint skeleton, the builder skeleton, and the frontend data-fetch plumbing. **No user story is independently testable until this phase is done**, since FR-004 requires the endpoint to always return all 7 metrics in one response.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T003 Add the `closed_at` lifecycle callback (`before_save :set_or_clear_closed_at, if: :status_changed?`) to `custom/app/models/opportunity.rb`, implementing the three transition rules from `data-model.md` §State transitions (open→won/lost sets `Time.current`; won/lost→open clears to `nil`; direct won↔lost is a no-op)
- [X] T004 [P] Create `custom/app/controllers/api/v1/accounts/opportunity_funnel_reports_controller.rb` with `#index`: apply `Concerns::KanbanFeatureGuard`, `authorize(:report, :view?)` (core `ReportPolicy`, unmodified), parse `since`/`until` into a range via `DateRangeHelper` (the only place this feature parses date params), instantiate `Reports::OpportunityFunnelBuilder.new(account: Current.account, range: range).build`, render the resulting hash as JSON (per `contracts/opportunity_funnel_report.md`)
- [X] T005 [P] Create `custom/app/services/reports/opportunity_funnel_builder.rb` skeleton: `pattr_initialize :account, :range` (an already-parsed range, not raw params — see `data-model.md`), one public `#build` method returning the 7-key hash (`conversion_funnel`, `win_rate`, `pipeline_value_by_stage`, `avg_time_in_stage`, `new_opportunities_over_time`, `sales_cycle_time`, `performance_by_assignee`) delegating each key to a private method stub (implemented in Phase 3)
- [X] T006 [P] Create `app/javascript/dashboard/api/opportunityFunnelReports.js`, an `ApiClient` subclass (`accountScoped: true`) with a `get(accountId, { since, until })` method hitting the new endpoint
- [X] T007 [P] Create `app/javascript/dashboard/store/modules/OpportunityFunnelReports.js`, a namespaced Vuex module (`state: { data: {}, uiFlags: { fetchingItems: false } }`, a `get` action calling the new API client, mutations/getters) mirroring `SLAReports.js`'s pattern

**Checkpoint**: Foundation ready — endpoint returns a (currently stubbed/empty) 7-key response, frontend can fetch it. User Story 1 implementation can now begin.

---

## Phase 3: User Story 1 - Sales manager reviews pipeline health at a glance (Priority: P1) 🎯 MVP

**Goal**: Opening the Funnel report page for a selected date range renders all 7 charts with correct data — the core value of the feature.

**Independent Test**: Navigate to the report page with an account that has opportunities in various stages/statuses; confirm all 7 charts render with correct, non-empty data.

### Implementation for User Story 1

- [X] T008 [US1] Implement `conversion_funnel` in `custom/app/services/reports/opportunity_funnel_builder.rb` (FR-005): opportunities created in the period, per pipeline stage in `position` order, % that reached that stage or later via `OpportunityStageChange`
- [X] T009 [US1] Implement `win_rate` in `custom/app/services/reports/opportunity_funnel_builder.rb` (FR-006): count of `won`/`lost` opportunities with `closed_at` in the period
- [X] T010 [US1] Implement `pipeline_value_by_stage` in `custom/app/services/reports/opportunity_funnel_builder.rb` (FR-007): sum of `value` for currently-open opportunities grouped by `pipeline_stage_id`, independent of `since`/`until`
- [X] T011 [US1] Implement `avg_time_in_stage` in `custom/app/services/reports/opportunity_funnel_builder.rb` (FR-008): lifetime average of completed `OpportunityStageChange` durations per stage, excluding each opportunity's current still-open interval
- [X] T012 [US1] Implement `new_opportunities_over_time` in `custom/app/services/reports/opportunity_funnel_builder.rb` (FR-009): count of opportunities created in the period, bucketed by day, no-gap day range matching `DateRangeHelper`'s convention
- [X] T013 [US1] Implement `sales_cycle_time` in `custom/app/services/reports/opportunity_funnel_builder.rb` (FR-010): average `closed_at - created_at` (days) for `won` opportunities closed in the period; `nil` when zero such opportunities
- [X] T014 [US1] Implement `performance_by_assignee` in `custom/app/services/reports/opportunity_funnel_builder.rb` (FR-011): count + summed value of `won` opportunities closed in the period, grouped by `assignee_id`, ranked descending by value, `nil` assignee grouped as `"Unassigned"`
- [X] T015 [P] [US1] Create `app/javascript/shared/components/charts/DonutChart.vue` per `research.md`'s Chart.js decision: register `ArcElement`, `Tooltip`, `Legend`; wrap typed `Doughnut`; own `defaultChartOptions` with `plugins: { legend: { display: true, position: 'bottom' } }` (no `scales` block)
- [X] T016 [P] [US1] Create `app/javascript/shared/components/charts/LineChart.vue` per `research.md`'s Chart.js decision: register `LineElement`, `PointElement`, `CategoryScale`, `LinearScale`, `Tooltip` (no `Legend`, matching `BarChart.vue`'s real no-legend mechanism); wrap typed `Line`; own `defaultChartOptions` keeping `BarChart.vue`'s `scales` shape
- [X] T017 [US1] Create `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue`: reuse `ReportHeader`/`ReportFilters`/`ReportMetricCard` exactly as sibling report pages; render `BarChart` (conversion funnel, pipeline value by stage, avg time in stage, performance by assignee), `DonutChart` (win rate), `LineChart` (new opportunities over time); map each pipeline-stage-keyed bar's `backgroundColor` to that stage's `accent_color` (via the already-loaded `pipelineStages` Vuex store), falling back to the existing default bar color; use the hex equivalents of `KanbanCard.vue`'s `n-teal`/`n-ruby` won/lost tokens for the win-rate donut segments
- [X] T018 [US1] Add the `funnel` route entry to `app/javascript/dashboard/routes/dashboard/settings/reports/reports.routes.js`, pointing to `OpportunityFunnelReport.vue`
- [X] T019 [US1] Add a "Funnel" nav entry (English source string, from the `OPPORTUNITY_FUNNEL_REPORTS` i18n keys added in T020 — pt-BR/other locales are Crowdin-owned, not hand-edited) under the existing Reports section in `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- [X] T020 [US1] Add the `OPPORTUNITY_FUNNEL_REPORTS` i18n keys (page title, per-chart titles, metric card labels) to `app/javascript/dashboard/i18n/locale/en/en.json`

**Checkpoint**: User Story 1 is fully functional and independently testable — the report page loads with all 7 charts showing correct data for the default date range.

---

## Phase 4: User Story 2 - Manager narrows the report to a specific date range (Priority: P2)

**Goal**: Changing the date-range filter updates the 5 period-scoped charts while the 2 current-state/lifetime charts stay stable.

**Independent Test**: Change the date-range filter on an already-loaded report page; confirm the 5 period-scoped charts update and the 2 non-period-filtered charts remain unchanged.

### Implementation for User Story 2

- [X] T021 [US2] Verify/harden `pipeline_value_by_stage` and `avg_time_in_stage` in `custom/app/services/reports/opportunity_funnel_builder.rb` so neither method reads `since`/`until` at all (current-state/lifetime only, per FR-007/FR-008) — add a code comment noting this is intentional if not already obvious from the method body
- [X] T022 [US2] Wire `ReportFilters`' date-range change handler in `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue` to re-dispatch the `OpportunityFunnelReports` Vuex `get` action with the new `since`/`until`, re-rendering only the 5 period-scoped chart bindings
- [X] T023 [P] [US2] Add `uiFlags.fetchingItems`-driven loading state to `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue` during date-range refetch, matching the existing report-page loading convention

**Checkpoint**: User Stories 1 AND 2 both work independently — date-range changes correctly partition period-scoped vs. current-state charts.

---

## Phase 5: User Story 3 - Manager views the report for an account with no opportunity data yet (Priority: P3)

**Goal**: Zero-data accounts/periods render a clean empty state per chart instead of an error.

**Independent Test**: Load the report for an account with zero opportunities (or a date range with none created/closed); confirm the page loads successfully with empty/zero states instead of failing.

### Implementation for User Story 3

- [X] T024 [US3] Confirm each private method in `custom/app/services/reports/opportunity_funnel_builder.rb` returns the documented empty-state shape (empty `labels`/`data` arrays, zero counts, `average_days: nil`, empty `performance_by_assignee` array) when no matching records exist, per `contracts/opportunity_funnel_report.md`'s empty-state example — adjust any method that would instead raise or return `nil`/`NaN`
- [X] T025 [P] [US3] Handle `win_rate` divide-by-zero in `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue`'s headline-percentage computed value (render `0%` when `won + lost === 0`, not `NaN`)
- [X] T026 [P] [US3] Handle `sales_cycle_time.average_days: null` in `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue`'s `ReportMetricCard` (render the existing empty-value convention, e.g. `—`, instead of blank/`NaN`)
- [X] T027 [P] [US3] Confirm `DonutChart.vue`, `LineChart.vue`, and the reused `BarChart.vue` render without a JS error when passed empty/zero-filled `collection` data (manual check, all three chart types)

**Checkpoint**: All 3 user stories are independently functional — the report page handles the full baseline data, period, and empty-state cases correctly.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final consistency pass across all stories.

- [X] T028 [P] Run `docker compose exec rails bundle exec rubocop -a` against `custom/app/models/opportunity.rb`, `custom/app/services/reports/opportunity_funnel_builder.rb`, `custom/app/controllers/api/v1/accounts/opportunity_funnel_reports_controller.rb`
- [X] T029 [P] Run `docker compose exec vite pnpm eslint:fix` (`DonutChart.vue`, `LineChart.vue`, `OpportunityFunnelReport.vue`, `opportunityFunnelReports.js`, `OpportunityFunnelReports.js`, `reports.routes.js`, `Sidebar.vue`, `en.json`)
- [X] T030 Run through `quickstart.md` end-to-end (migration + callback check in `rails console`, `curl` the endpoint, walk the UI for both populated and empty accounts, section 6's load-time sanity check against another report page per SC-002) and confirm every "Done when" criterion

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup (T001's migration) — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Foundational completion — delivers the MVP
- **User Story 2 (Phase 4)**: Depends on Foundational; in practice also depends on US1's builder/page existing (it hardens/wires behavior already scaffolded in US1), so implement after US1
- **User Story 3 (Phase 5)**: Depends on Foundational; same practical ordering as US2 — hardens US1's already-built metrics/page for the zero-data case
- **Polish (Phase 6)**: Depends on all three user stories being complete

### Within Each User Story

- Builder metric methods (backend) before the page that renders them (frontend)
- Chart wrapper components (`DonutChart.vue`, `LineChart.vue`) before the page that consumes them
- Page created before route/sidebar wiring

### Parallel Opportunities

- T001 and T002 (Setup) can run in parallel
- T004, T005, T006, T007 (Foundational) touch four different files and can run in parallel once T003 lands
- T015 and T016 (US1 chart wrappers) touch different files and can run in parallel with each other and with T008–T014 (different files: Ruby builder vs. Vue components)
- T023 (US2) and T025/T026/T027 (US3) touch different files and can run in parallel with each other
- T028 and T029 (Polish) can run in parallel

---

## Parallel Example: Foundational Phase

```bash
# After T003 (closed_at callback) lands, launch these together:
Task: "Create custom/app/controllers/api/v1/accounts/opportunity_funnel_reports_controller.rb skeleton"
Task: "Create custom/app/services/reports/opportunity_funnel_builder.rb skeleton"
Task: "Create app/javascript/dashboard/api/opportunityFunnelReports.js"
Task: "Create app/javascript/dashboard/store/modules/OpportunityFunnelReports.js"
```

## Parallel Example: User Story 1

```bash
# Backend metric methods (single file, sequential) can proceed alongside:
Task: "Create app/javascript/shared/components/charts/DonutChart.vue"
Task: "Create app/javascript/shared/components/charts/LineChart.vue"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: confirm all 7 charts render correct data for a populated account (quickstart.md steps 1–4)
5. Deploy/demo if ready — this alone satisfies SC-001/SC-002

### Incremental Delivery

1. Setup + Foundational → endpoint skeleton reachable
2. User Story 1 → full page with correct baseline data → MVP demo
3. User Story 2 → date-range filtering hardened/verified → demo period comparison
4. User Story 3 → empty-state handling hardened/verified → demo first-run/no-data experience
5. Polish → lint, quickstart validation

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- No test tasks generated — not explicitly requested (CLAUDE.md: "Avoid writing specs unless explicitly asked")
- Every backend metric method lives in the single `Reports::OpportunityFunnelBuilder` service (per `research.md`'s Decision) — no per-metric service classes
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently

## Phase 7: Convergence

- [X] T031 Fix CRITICAL constitution violation: replace hardcoded `labels: ['Won', 'Lost']` in `winRateData` computed (`app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue`) with i18n-backed labels; add corresponding keys to `app/javascript/dashboard/i18n/locale/en/report.json` under `OPPORTUNITY_FUNNEL_REPORTS.CHARTS` per Constitution III (contradicts)
- [X] T032 Fix CRITICAL constitution violation: replace hardcoded `'—'` fallback in `winRatePercent` computed (`app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue`) with `t('OPPORTUNITY_FUNNEL_REPORTS.METRICS.WIN_RATE_EMPTY')`, reusing the existing unused i18n key per Constitution III (contradicts)
- [X] T033 Remove the redundant unconditional `fetchReport()` call from `OpportunityFunnelReport.vue`'s `onMounted` (`app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue`), since `ReportFilters.vue`'s own mount-time `emitChange()` already triggers an equivalent initial fetch via `onFilterChange`, causing a duplicate `GET /opportunity_funnel_reports` request on every page load per SC-002 (partial)

## Phase 8: Convergence (user-requested UI adjustments)

- [X] T034 Extend `performance_by_assignee` in `custom/app/services/reports/opportunity_funnel_builder.rb` to also compute, per `assignee_id`, the count and summed `value` of that agent's currently-open (in-progress) opportunities — current-state, NOT period-filtered, same convention as `pipeline_value_by_stage` — alongside the existing period-scoped won count/value (rename `count`/`value` to `won_count`/`won_value` for clarity) per user request (missing)
- [X] T035 Replace the "Performance by Assignee" `BarChart` panel in `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue` with a new agent-list table (new components under `app/javascript/dashboard/routes/dashboard/settings/reports/components/`, mirroring the existing `components/overview/AgentTable.vue` + `AgentCell.vue` pattern) showing avatar, name, and email per row, joined from the `agents/getAgents` store getter (dispatch `agents/get` on mount) against `performance_by_assignee` rows by `assignee_id`, with "Open" and "Converted (period)" columns each showing count + monetary value via `formatCurrencyAmount` from `dashboard/constants/pipelineCurrency` per user request (missing)
- [X] T036 Add i18n keys to `app/javascript/dashboard/i18n/locale/en/report.json` under `OPPORTUNITY_FUNNEL_REPORTS` for the new assignee table's column headers (Agent/Open/Converted) and remove the now-unused `CHARTS.PERFORMANCE_BY_ASSIGNEE` bar-chart label once the table fully replaces the chart per user request (missing)
  - Note: `CHARTS.PERFORMANCE_BY_ASSIGNEE` was intentionally *retained* as the panel's `<h3>` section heading rather than removed — every other chart panel in the template uses this same heading pattern, and the panel still needs a title after the chart→table swap.

## Phase 9: Convergence (post-implementation UI/i18n additions)

- [X] T037 CRITICAL: Resolve pt-BR i18n Constitution conflict — either revert the hand-edited `OPPORTUNITY_FUNNEL_REPORTS` keys in `app/javascript/dashboard/i18n/locale/pt_BR/report.json` to restore Crowdin-only translation ownership, or formally amend `.specify/memory/constitution.md`'s Personalization Boundaries bullet via `/speckit-constitution` to record this feature's explicit exception, per Constitution: Personalization Boundaries (contradicts) — resolved by amending the constitution (v1.1.0 → v1.1.1) to record a named, scoped exception for this feature's `OPPORTUNITY_FUNNEL_REPORTS` keys
- [X] T038 Document/justify the value-vs-quantity toggle (`showValue` ref, `SHOW_VALUE_TOGGLE` i18n key, and `value_data` variants on `pipeline_value_by_stage`/`new_opportunities_over_time` in `custom/app/services/reports/opportunity_funnel_builder.rb`) by recording it in `spec.md`/`plan.md` as an accepted scope addition, or remove it if not wanted, per FR-005/FR-007/FR-009 (unrequested) — recorded in spec.md's "Post-launch scope additions" and plan.md's "Post-Plan Additions" sections
- [X] T039 Document/justify the five per-chart consolidated headline computeds (`conversionFunnelHeadline`, `winRateHeadline`, `pipelineHeadline`, `avgTimeInStageHeadline`, `newOpportunitiesHeadline` in `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue`) against FR-014, which only specifies a headline percentage for win-rate and a headline figure for sales-cycle-time, per FR-014 (unrequested) — recorded in spec.md's "Post-launch scope additions" section
- [X] T040 Document/justify the chart cosmetic polish pass (`h-72` panel height, hidden y-axis ticks, %/currency-aware tooltip callbacks via `percentChartOptions`/`valueChartOptions`/`donutChartOptions`, and compact-number formatting in `formatMetric`) in `OpportunityFunnelReport.vue` as an accepted UI-polish scope addition beyond `plan.md`'s minimal chart-wrapper description, per plan.md: Project Structure (unrequested) — recorded in plan.md's "Post-Plan Additions" section
