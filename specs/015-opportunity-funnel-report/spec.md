# Feature Specification: Opportunity Funnel Report

**Feature Branch**: `015-opportunity-funnel-report`

**Created**: 2026-08-04

**Status**: Draft

**Input**: User description: "Phase 21: Opportunity Funnel Report — a new fixed dashboard page in Chatwoot's Reports module showing the 7 highest-value charts for a CRM funnel (conversion funnel, win rate, pipeline value by stage, average time in stage, new opportunities over time, sales cycle time, and performance by assignee), reusing existing chart/report infrastructure. Depends on Phase 11 (stage dwell-time tracking)."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Sales manager reviews pipeline health at a glance (Priority: P1)

A sales manager opens the new Funnel report page for a selected date range and immediately sees where opportunities are dropping off in the pipeline, what the team's win rate is, and how much value is sitting in each open stage — without configuring any chart or filter beyond the date range.

**Why this priority**: This is the core value of the feature — a single page answering "how healthy is our pipeline right now" replaces manual spreadsheet exports. Without this, the rest of the feature has no purpose.

**Independent Test**: Can be fully tested by navigating to the report page with an account that has opportunities in various stages and statuses, and confirming all 7 charts render with correct, non-empty data for that account.

**Acceptance Scenarios**:

1. **Given** an account with opportunities created and closed within the last 30 days, **When** the manager opens the Funnel report with the last-30-days date range selected, **Then** the conversion funnel, win rate, new-opportunities trend, sales cycle time, and performance-by-assignee charts reflect only opportunities matching that range's respective cohort (created-in-period or closed-in-period).
2. **Given** an account with currently-open opportunities across multiple pipeline stages, **When** the manager opens the Funnel report with any date range, **Then** the pipeline-value-by-stage and average-time-in-stage charts show current-state data unaffected by the selected date range.

---

### User Story 2 - Manager narrows the report to a specific date range (Priority: P2)

The manager changes the date-range filter (e.g., from "last 30 days" to "last quarter") to compare pipeline performance across periods.

**Why this priority**: Date filtering is essential for period-over-period comparison, a standard sales-reporting workflow, but the report is still useful with just a default range (P1 covers that baseline).

**Independent Test**: Can be tested independently by changing the date-range filter on an already-loaded report page and confirming the 5 period-scoped charts update while the 2 non-period-filtered charts remain unchanged.

**Acceptance Scenarios**:

1. **Given** the Funnel report is displaying data for one date range, **When** the manager selects a different date range, **Then** conversion funnel, win rate, new-opportunities-over-time, sales-cycle-time, and performance-by-assignee update to reflect the new range.
2. **Given** the Funnel report is displaying data for one date range, **When** the manager selects a different date range, **Then** pipeline-value-by-stage and average-time-in-stage do not change.

---

### User Story 3 - Manager views the report for an account with no opportunity data yet (Priority: P3)

A manager on a newly created account, or one with no opportunities in the selected period, opens the report and sees a clean empty state per chart rather than an error.

**Why this priority**: Important for a good first-run experience and for periods with genuinely no activity, but it's a resilience/polish concern rather than the primary value driver.

**Independent Test**: Can be tested independently by loading the report for an account with zero opportunities (or a date range with none created/closed) and confirming the page loads successfully with empty/zero states instead of failing.

**Acceptance Scenarios**:

1. **Given** an account with no opportunities at all, **When** the manager opens the Funnel report, **Then** all 7 charts render with empty/zero states and no error is shown.
2. **Given** an account with open opportunities but none created or closed in the selected period, **When** the manager opens the Funnel report, **Then** pipeline-value-by-stage and average-time-in-stage still show data while the 5 period-scoped charts show empty states.

### Edge Cases

- What happens when an opportunity is reopened after being closed (status moves back to `open`)? It must not contribute stale closed-cycle data to win-rate or sales-cycle-time calculations for its old close event.
- How does the average-time-in-stage calculation handle an opportunity's current, still-open stage interval? That in-progress interval is excluded from the average since it has no completed duration yet.
- How does the report handle a stage with zero opportunities that have ever reached it? The conversion funnel shows 0% for that stage rather than omitting it.
- What happens to performance-by-assignee when a won opportunity has no assignee? [reasonable default: grouped under an "unassigned" bucket, consistent with existing report conventions]

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST record the point in time an opportunity is closed (`closed_at`), set automatically when an opportunity's status transitions from open to won or lost.
- **FR-002**: System MUST clear the closed timestamp if a closed opportunity is reopened (status transitions back to open), so a stale close time never affects future win-rate or sales-cycle-time calculations.
- **FR-003**: System MUST provide a report endpoint that accepts a date range (since/until) and returns the full fixed set of 7 funnel metrics for the account — no per-chart type selection or chart-builder configuration.
- **FR-004**: System MUST return all 7 metrics in a single response, each already computed and shaped for direct rendering, so the frontend performs no client-side metric calculation.
- **FR-005**: System MUST compute a conversion funnel showing, per pipeline stage in stage order, the percentage of opportunities created in the selected period that reached that stage or later.
- **FR-006**: System MUST compute a win rate showing the count of won vs. lost opportunities closed in the selected period.
- **FR-007**: System MUST compute pipeline value by stage as the sum of value for all currently-open opportunities grouped by their current stage, independent of the selected date range.
- **FR-008**: System MUST compute average time in stage as a lifetime average (not scoped to the selected date range) of completed stage durations, excluding an opportunity's current still-open stage interval.
- **FR-009**: System MUST compute a trend of new opportunities created in the selected period, bucketed by day.
- **FR-010**: System MUST compute average sales cycle time as the average elapsed time between creation and closing, for won opportunities closed in the selected period.
- **FR-011**: System MUST compute performance by assignee as the count and total value of won opportunities closed in the selected period, grouped by assignee and ranked from highest to lowest value.
- **FR-012**: System MUST return a non-error empty/zero-data response for each metric when there is no matching data in the account or selected period, rather than failing the request.
- **FR-013**: System MUST present the report as a new page within the existing Reports section of the product, reachable through the existing reports navigation, and MUST include the existing date-range filter control used by other report pages.
- **FR-014**: System MUST render all 7 metrics together on the report page: a conversion funnel, a win-rate breakdown with a headline percentage, pipeline value by stage, average time in stage, a new-opportunities trend over time, average sales cycle time as a headline figure, and performance by assignee.

### Key Entities *(include if feature involves data)*

- **Opportunity**: A sales deal being tracked through the pipeline. Gains a closed-at timestamp marking when it was won or lost; already has a status, value, current stage, assignee, and creation time.
- **Opportunity Stage Change**: A historical record of an opportunity moving into a pipeline stage at a point in time; used to compute conversion-funnel reach and time spent per stage.
- **Pipeline Stage**: An ordered step in the sales pipeline that opportunities pass through; used to order the conversion funnel and group pipeline value.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A sales manager can view pipeline health, win rate, and team performance for a selected period on a single page without exporting data or building a custom report.
- **SC-002**: All 7 report charts load and render correctly for an account with a realistic volume of opportunity data (hundreds of opportunities across multiple stages) within the same time expectations as other existing report pages.
- **SC-003**: Changing the date-range filter updates the 5 period-scoped charts while the 2 lifetime/current-state charts remain stable, with no incorrect cross-contamination between the two cohort types.
- **SC-004**: An account with no opportunities, or no opportunities in the selected period, sees a fully-loaded page with empty states rather than an error, in 100% of such cases.

## Assumptions

- This phase depends on stage dwell-time tracking (`OpportunityStageChange` history) already being in place; the funnel and time-in-stage calculations read from that existing transition history.
- The report page has a fixed, non-configurable set of 7 charts by product decision — no chart type/group-by selector, unlike the rest of the Reports module.
- The conversion funnel renders as a horizontal bar chart with decreasing bar lengths for this phase; a true graphical (trapezoid) funnel visual is an out-of-scope future enhancement with no impact on the underlying data or calculations.
- Multi-pipeline filtering, per-chart drilldown/export, and any alerting/digest derived from these metrics are out of scope for this phase.
- An assignee-less won opportunity is grouped under an "unassigned" bucket in performance-by-assignee, consistent with existing reporting conventions elsewhere in the product.
- **Post-launch scope additions** (requested and approved after initial implementation, not part of the original FR set above): a value/quantity toggle lets the manager switch the pipeline-value-by-stage and new-opportunities-trend charts between summed value and raw count; each of the 7 charts also surfaces its own consolidated headline number (in addition to the win-rate and sales-cycle-time headlines already required by FR-014); monetary values use compact notation (e.g. "1.2M") in headlines. These are additive UI/UX refinements on top of the existing metrics — they do not change any FR's underlying data contract.
