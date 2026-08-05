# Feature Specification: Sales Forecast Widget (Preview)

**Feature Branch**: `016-sales-forecast-widget`

**Created**: 2026-08-04

**Status**: Draft

**Input**: User description: "Phase 23: Sales Forecast Widget (preview) — an 8th card on the Opportunity Funnel Report page (Phase 21), showing a probability-weighted forecast of currently-open pipeline value expected to close within the next 90 days, broken into day-0 (closing today)/1–30/31–60/61–90 day buckets. Depends on Phase 21 (reuses avg_time_in_stage)."

## Clarifications

### Session 2026-08-04

- Q: When an opportunity's expected close date lands exactly on a bucket boundary (day 30 or day 60), should it count toward the earlier bucket or the later one? → A: Day exactly on a boundary (e.g., day 30, day 60) belongs to the earlier bucket (1–30 includes day 30, 31–60 includes day 60)

### Session 2026-08-05

- Q: Should the day 0-30 window stay a single bucket, or split out same-day closings? → A: Split into a fourth, dedicated `day_0` (closing today / already overdue) bucket, separate from `1_30`, so the card shows four buckets total.
- Q: Should the card keep a separate raw/unweighted "current open pipeline" baseline figure (FR-005a) alongside the weighted total? → A: No — drop the baseline figure entirely; the card shows only the total weighted value as its headline, with the four buckets beneath it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Sales manager sees the near-term forecast total (Priority: P1)

A sales manager opens the Funnel report page and sees an 8th card showing a single probability-weighted total: how much of the currently-open pipeline is realistically expected to close within the next 90 days, distinct from raw pipeline value which doesn't account for how likely each deal is to actually close.

**Why this priority**: This is the core value of the feature — a directional "how much are we likely to close soon" signal that raw pipeline-value-by-stage doesn't provide. Without this, the card has no purpose.

**Independent Test**: Can be fully tested by opening the report page for an account with enough closed-deal and stage-transition history to qualify, and confirming the card shows a single weighted total reflecting current open pipeline.

**Acceptance Scenarios**:

1. **Given** an account with sufficient historical data (at least one completed transition for every pipeline stage, and at least one closed-won and one closed-lost opportunity overall), **When** the manager opens the Funnel report, **Then** the forecast card displays a single total weighted value for all currently-open opportunities expected to close within 90 days.
2. **Given** the forecast card is visible, **When** the manager changes the report's date-range filter, **Then** the forecast total does not change, since it always reflects current open pipeline rather than a selected period.

---

### User Story 2 - Manager sees the near-term breakdown by time window (Priority: P2)

Below the total, the manager sees the forecast split into four time buckets — closing today (day 0), 1–30, 31–60, and 61–90 days — each showing how many deals and how much weighted value fall into that window, so they can tell whether expected revenue is concentrated soon or spread out.

**Why this priority**: The breakdown adds planning value on top of the headline total (P1), but the total alone already delivers the core signal, so this is a secondary layer of detail.

**Independent Test**: Can be tested independently by confirming the four buckets sum to the card's total and that each bucket's count and value match the opportunities whose computed expected-close date falls in that window.

**Acceptance Scenarios**:

1. **Given** the forecast card is displaying a total, **When** the manager views the card, **Then** four buckets are shown below it — closing today (day 0), 1–30, 31–60, and 61–90 days — each with its own opportunity count and weighted value, and the four bucket values sum to the card's total.
2. **Given** an open opportunity whose expected close date has already passed, **When** the forecast is computed, **Then** that opportunity is counted in the day-0 bucket rather than excluded or shown separately as overdue.
3. **Given** an open opportunity whose expected close date is more than 90 days out, **When** the forecast is computed, **Then** that opportunity is excluded from the forecast total and all buckets.

---

### User Story 3 - Manager on a data-sparse account sees an explicit "not enough data" state (Priority: P3)

A manager on a new account, or one that hasn't yet closed enough deals to establish reliable win-rate and stage-duration history, opens the report and sees a clear message explaining the forecast isn't available yet, instead of a chart showing zero or a misleadingly precise number.

**Why this priority**: Important for trust and correctness — showing a fabricated or zeroed number on a low-history account could be mistaken for a real commitment — but it's a resilience/polish concern rather than the primary value driver, so it comes after the core forecast (P1) and its breakdown (P2).

**Independent Test**: Can be tested independently by loading the report for an account missing at least one required piece of history (e.g., no closed-lost opportunities, or a pipeline stage with no completed transitions yet) and confirming the card shows an explicit empty-state message rather than a donut or a zero total.

**Acceptance Scenarios**:

1. **Given** an account with no closed-won or no closed-lost opportunities at all, **When** the manager opens the Funnel report, **Then** the forecast card shows an explicit "not enough historical data" message instead of a chart.
2. **Given** an account where every pipeline stage has at least one completed transition except one, **When** the manager opens the Funnel report, **Then** the forecast card still shows the "not enough historical data" message, since the requirement applies to every stage together, not most of them.

### Edge Cases

- What happens when an open opportunity's computed expected close date falls exactly on a bucket boundary (e.g., day 30 or day 60)? Confirmed: it belongs to the earlier bucket (inclusive lower bucket, e.g., day 30 counts as 1–30, day 60 counts as 31–60).
- How does the forecast handle an account that meets the data-sufficiency requirement on one page load but drops below it later (e.g., after reopening the account's only closed-lost opportunity)? The forecast card must re-evaluate sufficiency on every load and fall back to the empty state if the requirement is no longer met.
- What happens to an opportunity in a pipeline stage that itself has no historical win/loss data yet, even though the account overall meets the sufficiency gate? [reasonable default: this cannot occur, since the gate requires every stage to have data before the forecast activates at all]
- How does the forecast card behave when the funnel report's other 7 charts have data but the account is brand-new with zero opportunities? The forecast card shows the same "not enough historical data" empty state as any other data-insufficient account, consistent with the all-or-nothing gate.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST include a sales forecast for currently-open pipeline in the Funnel report's data response, always reflecting current open pipeline state rather than being scoped to the report's selected date range.
- **FR-002**: System MUST compute, for each currently-open opportunity, a weighted value equal to its deal value multiplied by the historical win probability of opportunities that have reached its current pipeline stage (lifetime win rate for that stage, not limited to the selected date range).
- **FR-003**: System MUST compute an expected close date for each currently-open opportunity, derived from today's date plus the sum of average historical time spent in its current stage and every stage remaining ahead of it in the pipeline, always calculated fresh from the latest historical averages rather than stored and left to go stale.
- **FR-004**: System MUST group currently-open opportunities into four time buckets based on their computed expected close date — closing today (day 0), 1–30, 31–60, and 61–90 days from today — and exclude any opportunity whose expected close date is more than 90 days out; an opportunity whose expected close date has already passed is counted in the day-0 bucket.
- **FR-005**: System MUST report, for the forecast as a whole, a total weighted value (the sum of all four buckets) and, for each bucket, the count of opportunities and their combined weighted value.
- **FR-006**: System MUST only produce a forecast when the account has, across its entire pipeline, at least one completed stage transition for every stage and at least one closed-won and one closed-lost opportunity overall; if any part of this requirement is unmet, the system MUST indicate the forecast is unavailable rather than returning partial, zero, or default-assumption figures.
- **FR-007**: The Funnel report page MUST present the forecast as an additional card alongside its existing charts, visibly marked as a preview/first version, positioned after the existing charts.
- **FR-008**: The forecast card MUST visually represent the total weighted value and the four time buckets, with each bucket showing its label, opportunity count, and weighted value, and with the total weighted value distinctly displayed as the overall headline figure for the card.
- **FR-009**: When the forecast is unavailable (FR-006), the card MUST replace its chart and bucket list with a clearly worded explanatory message, while keeping the card's title and preview marking, so it is not mistaken for a forecast of zero value.

### Key Entities *(include if feature involves data)*

- **Sales Forecast**: A computed (not persisted) probability-weighted projection of currently-open pipeline value expected to close within 90 days; composed of a total weighted value and four time buckets, or an "unavailable" state when the account lacks sufficient history.
- **Forecast Bucket**: One of four fixed time windows (closing today / day 0, 1–30, 31–60, 61–90 days) within the Sales Forecast; holds a count of opportunities and their combined weighted value.
- **Opportunity** *(existing)*: A sales deal being tracked through the pipeline; contributes its value, current stage, and status to the forecast calculation.
- **Pipeline Stage** *(existing)*: An ordered step in the sales pipeline; supplies the historical win rate and average duration data the forecast is built from.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A sales manager can see a directional "how much is likely to close in the next 90 days" figure on the Funnel report page without leaving it or configuring anything beyond what the page already offers.
- **SC-002**: For an account with realistic pipeline and history volume, the four time buckets' combined count and value always match the card's headline total, with no discrepancy.
- **SC-003**: 100% of accounts that don't yet have a complete win/loss and stage-duration history see an explicit "not enough data" message instead of a numeric forecast.
- **SC-004**: The forecast reflects the account's latest historical performance on every page load, with no stale or out-of-date figures shown after new deals close.

## Assumptions

- This phase depends on the Opportunity Funnel Report (Phase 21) already existing as a page with 7 charts, and reuses its `avg_time_in_stage` calculation and underlying stage-transition history (itself dependent on stage dwell-time tracking).
- The four bucket widths (day 0/1–30/31–60/61–90 days) are fixed by product decision for this first version; making them configurable is out of scope.
- The data-sufficiency gate is evaluated for the whole pipeline at once (all stages, all-or-nothing); there is no partial or per-stage forecast.
- No new reusable chart component is introduced; the card reuses the same bar-chart visualization already used by other charts on the page for the bucket breakdown, and a plain headline (title + large value) for the total, matching the page's existing chart-card pattern rather than the separate metric-card baseline originally proposed.
- Per-opportunity forecast drilldown, export, and any change to how `avg_time_in_stage` itself is calculated are out of scope for this phase.
