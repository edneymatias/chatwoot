# Tasks: Sales Forecast Widget (Preview)

**Input**: Design documents from `/specs/016-sales-forecast-widget/`
**Prerequisites**: plan.md, spec.md, data-model.md, contracts/opportunity_funnel_report.md, research.md, quickstart.md

**Tests**: Not included — per CLAUDE.md, specs are only written when explicitly requested; none requested for this feature.

**Organization**: Tasks are grouped by user story (US1 = P1 headline total, US2 = P2 bucket breakdown, US3 = P3 empty state) to allow independent implementation and testing, per spec.md.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: which user story a task belongs to (US1, US2, US3); omitted for Setup/Foundational/Polish

## Path Conventions

- Backend: `custom/app/services/reports/opportunity_funnel_builder.rb` (already fork-owned, edited in place)
- Frontend: `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue` (already fork-owned, edited in place)
- i18n: `app/javascript/dashboard/i18n/locale/en/report.json`

---

## Phase 1: Setup

**Purpose**: Confirm the touch surface before editing — no new files, no new dependencies for this feature.

- [X] T001 Confirm `custom/app/services/reports/opportunity_funnel_builder.rb`, `app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue`, and `app/javascript/dashboard/i18n/locale/en/report.json` exist and contain the Phase 21 (`015-opportunity-funnel-report`) implementation this feature extends (no new npm/gem dependency needed — `vue-chartjs`/chart.js already present)

**Checkpoint**: Existing files confirmed — safe to begin foundational edits.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core `sales_forecast` computation shared by every user story — the sufficiency gate (needed by US1 and US3) and the full weighted computation (US1's total is the sum of US2's buckets, so they cannot be split at the backend level per data-model.md's computation pipeline). No user story can be completed or independently tested until this phase is done.

**⚠️ CRITICAL**: No user story implementation should begin until this phase is complete.

- [X] T002 Implement `stage_win_probabilities` private method in `custom/app/services/reports/opportunity_funnel_builder.rb`: for every pipeline stage, `won_count / (won_count + lost_count)` among lifetime opportunities that reached that stage or later (data-model.md step 1)
- [X] T003 Implement `forecast_sufficient?` private method in `custom/app/services/reports/opportunity_funnel_builder.rb`: `true` only when every pipeline stage has a non-empty win-probability entry (T002) and the account has at least one lifetime `won` and one lifetime `lost` opportunity overall (data-model.md step 3 / FR-006)
- [X] T004 Implement `expected_close_offset_days` private method in `custom/app/services/reports/opportunity_funnel_builder.rb`, reusing the existing `build_stage_durations` average-duration data: sum of average stage duration for an opportunity's current stage and every stage at or after its position in pipeline order (data-model.md step 5, FR-003)
- [X] T005 Implement the `sales_forecast` private method in `custom/app/services/reports/opportunity_funnel_builder.rb` wiring T002–T004 together: returns `{ status: "insufficient_data" }` when `forecast_sufficient?` is false; otherwise computes `current_pipeline` (count + raw sum of `value` across all currently-open opportunities, data-model.md step 4 / FR-005a), per-opportunity `weighted_value` and bucket assignment (`0_30`/`31_60`/`61_90`, boundary values go to the earlier bucket, >90 days excluded — FR-004), and sums each bucket's `count`/`weighted_value` plus `total_weighted_value` as the sum of all three buckets (data-model.md steps 5–6, FR-002, FR-005)
- [X] T006 Add the `sales_forecast` key (from T005) to `Reports::OpportunityFunnelBuilder#build`'s response hash in `custom/app/services/reports/opportunity_funnel_builder.rb`, unscoped by `since`/`until` (FR-001), matching the shape in `contracts/opportunity_funnel_report.md`
- [X] T007 [P] Add `OPPORTUNITY_FUNNEL_REPORTS.SALES_FORECAST` i18n keys to `app/javascript/dashboard/i18n/locale/en/report.json`: card title, preview badge label, current-pipeline label, total label, **and the `infoText` copy required by `ReportMetricCard.vue`'s required `infoText` prop for each of the two big-number cards** (left "current pipeline" card and right "total weighted value" card)
- [X] T008 [P] Add an 8th card scaffold to `OpportunityFunnelReport.vue` (`app/javascript/dashboard/routes/dashboard/settings/reports/OpportunityFunnelReport.vue`): positioned after the existing 7 charts, reading `sales_forecast` from the report data, showing the card title and a "preview" badge (FR-007), with a `v-if`/`v-else` branch on `sales_forecast.status` (branches filled in by US1/US3 below)

**Checkpoint**: `sales_forecast` is present in the API response with correct `status`/`current_pipeline`/`buckets`/`total_weighted_value` shape; the card container renders with title + preview badge. User story implementation can now begin.

---

## Phase 3: User Story 1 - Sales manager sees the near-term forecast total (Priority: P1) 🎯 MVP

**Goal**: The manager sees a single probability-weighted headline total for currently-open pipeline expected to close within 90 days, alongside the raw open-pipeline baseline for comparison, unaffected by the report's date-range filter.

**Independent Test**: Open the report for an account with sufficient history and confirm the card shows the current-pipeline baseline and a single weighted total that doesn't change when the date-range filter changes.

### Implementation for User Story 1

- [X] T009 [US1] In the `status === "ok"` branch of the 8th card (`OpportunityFunnelReport.vue`), render a left `ReportMetricCard` sourced from `sales_forecast.current_pipeline.count`/`.value` (the "Agora ativo leads" baseline, FR-005a), using T007's `label`/`infoText` i18n keys for that card
- [X] T010 [US1] In the same branch, render a right `ReportMetricCard` sourced from `sales_forecast.total_weighted_value` as the card's headline figure, with count sourced from the sum of the three buckets' `count` (FR-008), using T007's `label`/`infoText` i18n keys for that card
- [X] T011 [US1] Verify (via the existing report Vuex getter/action) that `sales_forecast` is read from the same `since`/`until`-independent report response as the other period-scoped charts, so the two `ReportMetricCard`s do not re-fetch or recompute when the date-range filter changes (FR-001, Acceptance Scenario 1.2)

**Checkpoint**: User Story 1 is fully functional and independently testable — headline total + baseline render correctly and ignore the date-range filter.

---

## Phase 4: User Story 2 - Manager sees the near-term breakdown by time window (Priority: P2)

**Goal**: Below the total, the manager sees the forecast split into 0–30/31–60/61–90 day buckets, each with its own count and weighted value.

**Independent Test**: Confirm the three bars' underlying bucket values sum to the card's total, that an overdue opportunity lands in the 0–30 bucket while a >90-day-out opportunity is excluded from all three, and that each bucket's opportunity count is visible (not just its weighted value).

### Implementation for User Story 2

- [X] T012 [P] [US2] Add `OPPORTUNITY_FUNNEL_REPORTS.CHARTS.SALES_FORECAST` bucket-label i18n keys (0–30, 31–60, 61–90 days) and a count-tooltip label template (e.g. "{count} deals") to `app/javascript/dashboard/i18n/locale/en/report.json`
- [X] T013 [US2] In the `status === "ok"` branch of the 8th card (`OpportunityFunnelReport.vue`), render a middle `BarChart.vue` between the two `ReportMetricCard`s, with `collection.labels` from T012's bucket labels and `collection.datasets[0].data` from the three buckets' `weighted_value` (FR-008), following the same `collection`/`chartOptions` prop pattern used by the page's existing bar charts
- [X] T014 [US2] On the `BarChart.vue` instance from T013, override `chartOptions.plugins.tooltip.callbacks.label` (passed down through the `chartOptions` prop) to also surface each bucket's `count` alongside its `weighted_value`, using T012's count-label i18n key, so FR-008's "each bucket showing its label, opportunity count, and weighted value" is fully satisfied (not value-only)

**Checkpoint**: All P1–P2 functionality now works together — total, baseline, and bucket breakdown (value and count) all render and stay consistent.

---

## Phase 5: User Story 3 - Manager on a data-sparse account sees an explicit "not enough data" state (Priority: P3)

**Goal**: On an account that doesn't meet the sufficiency gate, the card shows an explicit message instead of a chart or a zeroed/fabricated number.

**Independent Test**: Load the report for an account missing a required piece of history (e.g. no closed-lost opportunities, or one pipeline stage with no completed transitions) and confirm the card shows the empty state, title, and preview badge — no chart, no numbers.

### Implementation for User Story 3

- [X] T015 [P] [US3] Add `OPPORTUNITY_FUNNEL_REPORTS.SALES_FORECAST.EMPTY_STATE` title/message i18n keys to `app/javascript/dashboard/i18n/locale/en/report.json` (FR-009)
- [X] T016 [US3] In the `status === "insufficient_data"` branch of the 8th card (`OpportunityFunnelReport.vue`), render `EmptyState.vue` with T015's copy in place of the `ReportMetricCard`s/`BarChart.vue`, keeping the card's title and preview badge from T008 (FR-009)

**Checkpoint**: All three user stories independently functional — sufficient-data accounts see total + baseline + buckets (with counts), insufficient-data accounts see the empty state.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Repo-wide checks that span all user stories.

- [X] T017 [P] Run `docker compose exec rails bundle exec rubocop -a custom/app/services/reports/opportunity_funnel_builder.rb`
- [X] T018 [P] Run `docker compose exec vite pnpm eslint` on `OpportunityFunnelReport.vue` and `report.json` (fix with `pnpm eslint:fix` if needed)
- [X] T019 Walk through `quickstart.md` Scenarios 1–4 and the Regression check against a running dev stack (insufficient data, sufficient data, date-range independence, overdue/out-of-range bucketing, existing 7 charts unaffected)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories (T002→T003→T004→T005→T006 are sequential, same file; T007/T008 can run in parallel with each other and with the backend chain since they touch different files)
- **User Stories (Phase 3–5)**: All depend on Foundational (Phase 2) completion. US1 (Phase 3) should land first since US2/US3 build on the same card scaffold and branch structure, but US2 and US3 touch disjoint branches (`status === "ok"` vs `status === "insufficient_data"`) of the same file, so they are not independent of each other at the file level (both edit `OpportunityFunnelReport.vue`) even though they are logically independent
- **Polish (Phase 6)**: Depends on all desired user stories being complete

### Within Each User Story

- T009/T010 (US1) touch the same file and same `v-if` branch — sequential
- T012 and T013 (US2) can run in parallel (different files); T014 depends on T013 (same `BarChart.vue` instance's `chartOptions`) and on T012's i18n key
- T015 (i18n) can run in parallel with T009–T014; T016 depends on T015's keys existing and on T008's scaffold

### Parallel Opportunities

- T007 and T008 (Phase 2) — different files
- T012 and T013 (Phase 4) — different files, before T014
- T015 (Phase 5) can run in parallel with all of Phase 3/4 since it's a disjoint i18n key + disjoint `v-else` branch
- T017 and T018 (Phase 6) — different toolchains/files

---

## Parallel Example: Foundational Phase

```bash
# T007 and T008 touch different files and can run together:
Task: "Add OPPORTUNITY_FUNNEL_REPORTS.SALES_FORECAST i18n keys (incl. infoText) to app/javascript/dashboard/i18n/locale/en/report.json"
Task: "Add 8th card scaffold (title + preview badge + status branch) to OpportunityFunnelReport.vue"
```

## Parallel Example: User Story 2

```bash
# T012 and T013 touch different files and can run together; T014 follows T013:
Task: "Add bucket-label + count-tooltip i18n keys to app/javascript/dashboard/i18n/locale/en/report.json"
Task: "Render middle BarChart.vue with bucket weighted_value data in OpportunityFunnelReport.vue"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (backend `sales_forecast` computation + card scaffold) — CRITICAL, blocks all stories
3. Complete Phase 3: User Story 1 (baseline + headline total)
4. **STOP and VALIDATE**: Confirm Scenario 2 of quickstart.md shows a correct total and baseline that doesn't move with the date-range filter
5. Ship as the MVP preview if ready

### Incremental Delivery

1. Setup + Foundational → sufficiency gate and computation correct, card container renders
2. Add User Story 1 → validate independently → ship (MVP)
3. Add User Story 2 → validate bucket sums (value and count) against the total → ship
4. Add User Story 3 → validate the empty-state path on a sparse account → ship
5. Polish (rubocop/eslint/quickstart walkthrough)

