# Feature Specification: Ad Campaign Performance Report

**Feature Branch**: `044-campaign-performance-report`

**Created**: 2026-09-02

**Status**: Draft

**Input**: User description: "@docs/kanban/ciclo 11/08-campaign-performance-funnel-reports/spec84.md"

## Clarifications

### Session 2026-09-02

- Q: Should the campaign/ad-set/ad breakdown table let users re-sort it by clicking other columns (Won, Lost, milestone rate), or does it always stay sorted by Leads descending only? → A: Fixed order — the table always sorts by Leads descending; no interactive column sorting.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View ad campaign performance summary (Priority: P1)

A sales or marketing manager opens a new "Campanhas de Anúncios" (Ad Campaign Performance) report
under Reports to understand, for a chosen date range, how many leads came from paid ad campaigns,
how many reached a key milestone in the sales process, and how many were ultimately won or lost.

**Why this priority**: This is the core value of the feature — a single-glance summary of paid-ad
lead performance. Without it, managers have no way to judge whether ad spend is producing leads
that progress and convert, short of manually cross-referencing the Kanban board.

**Independent Test**: Can be fully tested by opening the report with an account that has resolved
ad campaign leads and confirming the summary numbers (leads, milestone reach, won, lost, and
distinct campaign/ad-set/ad counts) match the underlying opportunity data for the selected range.

**Acceptance Scenarios**:

1. **Given** an account with paid-ad-attributed opportunities in the selected date range, **When**
   the manager opens the report, **Then** they see total leads, won count/rate, lost count/rate,
   and counts of distinct campaigns, ad sets, and ads.
2. **Given** a pipeline stage has been designated as the report's milestone, **When** the report
   loads, **Then** an additional card shows how many leads reached that stage (or a later one) and
   what percentage of total leads that represents.
3. **Given** no pipeline stage has been designated as the milestone, **When** the report loads,
   **Then** the milestone card is simply absent and no error is shown.
4. **Given** the manager changes the date range filter, **When** the new range is applied, **Then**
   every figure on the page updates to reflect only leads created within that range.

---

### User Story 2 - Drill into performance by campaign, ad set, and ad (Priority: P2)

The manager switches between "Campanhas", "Conjuntos", and "Criativos" tabs below the summary to
see the same lead/milestone/won/lost figures broken down by campaign, then by ad set, then by
individual ad, in order to spot which specific campaigns or creatives are driving results.

**Why this priority**: The summary alone answers "how are ads doing overall," but acting on that
insight (pausing an underperforming ad, scaling a winning campaign) requires the breakdown. It
depends on User Story 1's data but is a distinct, separately valuable capability.

**Independent Test**: Can be fully tested by loading the report for an account with multiple
campaigns/ad sets/ads and confirming each tab shows a table grouped at the right level, sorted by
lead count, without triggering a new page load when switching tabs.

**Acceptance Scenarios**:

1. **Given** the report has loaded, **When** the manager selects the "Campanhas" tab, **Then** a
   table shows one row per campaign with its leads, won, lost counts (and milestone reach/rate when
   configured), sorted by leads descending by default.
2. **Given** the same loaded report, **When** the manager switches to "Conjuntos" or "Criativos",
   **Then** the table re-groups to the ad-set or ad level using already-loaded data, with no
   additional request to the server.
3. **Given** a lead's campaign, ad set, or ad name has not yet been resolved (or is otherwise
   missing), **When** it appears in a breakdown row, **Then** it is labeled "Não identificado" and
   still contributes to that row's leads/won/lost/milestone counts, but is excluded from the
   distinct campaign/ad-set/ad counts shown in the summary.

---

### User Story 3 - Designate the funnel milestone stage (Priority: P3)

A pipeline administrator, while managing the Kanban's pipeline stages, marks one stage as the
milestone tracked by the Ad Campaign Performance report (e.g., the stage representing a scheduled
meeting), so the report can show how many paid-ad leads progress that far.

**Why this priority**: This configuration step unlocks the milestone card/column described in User
Story 1 and 2, but the report is still useful without it (a leaner summary and table). It's
independently valuable and testable as a standalone administrative action.

**Independent Test**: Can be fully tested by marking a stage as the milestone in the pipeline stage
management screen, confirming it is reflected as designated, then marking a different stage and
confirming the first one is automatically un-designated.

**Acceptance Scenarios**:

1. **Given** the administrator is editing a pipeline stage, **When** they mark it as the report's
   milestone stage, **Then** it becomes the account's designated milestone stage.
2. **Given** a stage is already designated as the milestone, **When** the administrator designates
   a different stage instead, **Then** the previous stage is automatically un-designated — at most
   one stage per account can be the milestone at any time.

---

### Edge Cases

- What happens when ad campaign attribution is not enabled for the account, or is enabled but no
  opportunity has finished attribution resolution yet? The "Campanhas de Anúncios" entry does not
  appear under Reports at all.
- What happens when the selected date range contains zero paid-ad-attributed leads? The report
  loads with all counts at zero and empty breakdown tables, without an error.
- How does the report treat organic (non-paid) or otherwise non-attributed opportunities? They are
  excluded entirely from every figure on this report.
- How does the report treat opportunities whose attribution is still pending resolution? They are
  included in leads/won/lost/milestone totals (as real paid leads), but their campaign/ad-set/ad
  name renders as "Não identificado" and they don't count toward the distinct campaign/ad-set/ad
  totals.
- What happens to opportunities created before ad campaign attribution existed? They simply have no
  attribution data and are excluded from this report, the same as any other non-attributed lead.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow an authorized user to designate exactly one pipeline stage per
  account as the report's milestone stage; designating a different stage MUST automatically remove
  the designation from whichever stage previously held it.
- **FR-002**: System MUST show a "Campanhas de Anúncios" entry in the Reports navigation only when
  ad campaign attribution is enabled for the account AND at least one opportunity has completed
  attribution resolution.
- **FR-003**: The report MUST let users filter its data by date range, using the account's standard
  date-range filter convention, positioned above the results.
- **FR-004**: For the selected date range, the report MUST show the total number of paid-ad-
  attributed leads, excluding organic and non-attributed opportunities.
- **FR-005**: When a milestone stage is designated, the report MUST show how many of those leads
  reached that stage (or any later stage) at any point in their history, and what percentage of
  total leads that represents. When no stage is designated, this figure MUST be omitted entirely
  rather than shown as zero or an error.
- **FR-006**: The report MUST show the count and percentage of leads marked Won, and separately the
  count and percentage marked Lost.
- **FR-007**: The report MUST show the count of distinct campaigns, distinct ad sets, and distinct
  ads represented among the leads in the selected range.
- **FR-008**: The report MUST provide a breakdown of the same leads/won/lost (and milestone, when
  configured) figures grouped by campaign, by campaign + ad set, and by campaign + ad set + ad,
  switchable by the user without a new data fetch per switch.
- **FR-009**: Each breakdown table MUST always be sorted by lead count descending; the sort order is fixed and not user-adjustable.
- **FR-010**: Leads whose campaign, ad set, or ad name is unresolved or missing MUST be grouped and
  labeled as "Não identificado" in the breakdown, and MUST still count toward that group's
  leads/won/lost/milestone figures, but MUST NOT count toward the distinct campaign/ad-set/ad
  counts in the summary.
- **FR-011**: Changing the date range filter MUST refresh every figure on the page — summary cards
  and all three breakdown groupings — to reflect only leads created within the new range.

### Key Entities

- **Ad Campaign Performance Report**: A read-only, date-range-scoped view summarizing how paid-ad
  leads move through the funnel — total volume, milestone reach, and won/lost outcomes — plus a
  breakdown by campaign, ad set, and ad.
- **Milestone Stage**: A single pipeline stage per account, designated by an administrator, that
  represents the funnel checkpoint this report tracks (e.g., "reached a scheduled meeting"). At
  most one stage per account can hold this designation at a time.
- **Campaign / Ad Set / Ad**: The three levels of paid-ad attribution already captured on an
  opportunity, used here purely as grouping dimensions for the report's breakdown.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A manager can determine total paid-ad lead volume and won/lost outcomes for any
  chosen date range from a single page, without exporting data or requesting it from engineering.
- **SC-002**: A manager can identify the top campaign, ad set, or ad by lead volume within two
  clicks (opening the report, switching a tab), with no added wait time between tab switches.
- **SC-003**: 100% of totals shown (leads, milestone, won, lost) reflect only opportunities with
  genuine paid-ad attribution — organic and non-attributed opportunities never appear in any figure.
- **SC-004**: Accounts without ad campaign attribution enabled, or without any resolved campaign
  data yet, never see the report entry, and never encounter a broken or empty report page from it.
- **SC-005**: An administrator can change which pipeline stage is tracked as the milestone, and see
  that change reflected in the report on its next load, without any other configuration step.

## Assumptions

- Ad campaign attribution data (campaign/ad-set/ad names, resolution status) is already captured by
  the existing Meta referral attribution capability; this feature only reads and reports on it, and
  does not add new attribution capture.
- "Reached the milestone stage" reuses the same historical stage-progression logic already used by
  the existing Opportunity Funnel Report — a lead counts as having reached the milestone if it was
  ever at that stage or a later one, regardless of its current stage.
- Ad spend and cost-per-lead figures are not available in this phase and are not part of this
  report.
- The report does not auto-refresh; data updates only when the user changes the date range or
  reloads the page, consistent with the account's other report pages.
- An account's existing AI-agent (Scout) qualified/unqualified stage configuration is independent
  of the milestone stage designation introduced here — the two are not required to match.
- Only users with existing report-viewing permissions can access this report; no new permission
  level is introduced.
