# Feature Specification: Opportunity Attribute Report

**Feature Branch**: `018-opportunity-attribute-report`

**Created**: 2026-08-05

**Status**: Draft

**Input**: User description: "Phase 25: Opportunity Attribute Report — a new standalone Reports page (menu entry 'Oportunidades') where the user picks one list-type opportunity custom attribute and a date range, and sees a table with one row per possible value of that attribute plus a 'no value' row, each showing aggregate opportunity metrics (count, total value, won, lost, average time to close). Modeled on the existing Label Reports pattern applied to opportunities instead of conversations. Depends on Phase 1 (opportunity custom attributes) and Phase 21 (Opportunity Funnel Report, for period-cohort conventions and closed_at)."

## Clarifications

### Session 2026-08-05

- Q: When a manager first opens the report page, should it auto-select a default list-type attribute (and a default date range) and load results immediately, or start with nothing selected until the manager picks an attribute? → A: Auto-select the first available list-type attribute in alphabetical order, and the account's default report date range (last 7 days, matching Chatwoot's standard default); load the report immediately on page open.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Manager breaks down pipeline by a custom attribute (Priority: P1)

A sales manager wants to know how opportunities are distributed across the values of a category they track with a custom attribute (e.g. "Interesse": implantes, próteses, ortodontia, alinhadores, outros). They open the new report page, pick that attribute and a date range, and see one row per possible value with how many opportunities are open in that value, their combined value, how many closed won or lost in the period, and the average time to close.

**Why this priority**: This is the entire purpose of the feature — without it there is no report to view. Every other behavior exists to support this core view.

**Independent Test**: Can be fully tested by selecting a list-type opportunity custom attribute with existing opportunities tagged across its values, and confirming the table shows one correctly-aggregated row per value.

**Acceptance Scenarios**:

1. **Given** an account with a list-type opportunity attribute and opportunities tagged with several of its values, **When** the manager selects that attribute and a date range, **Then** the table shows one row per defined value, each with the count and total value of currently-open opportunities carrying that value (independent of the date range), plus won/lost counts and average time to close scoped to opportunities closed within the selected date range.
2. **Given** opportunities that have no value set for the selected attribute, **When** the report is generated, **Then** those opportunities are aggregated into a single "no value" row shown last, using the same metrics as the named-value rows.
3. **Given** an account with zero opportunities for a particular attribute value, **When** the report is generated, **Then** that value still appears as a row with all metrics at zero, rather than being omitted.
4. **Given** an account with at least one list-type opportunity attribute, **When** the manager opens the report page for the first time in a session, **Then** the first attribute in alphabetical order is auto-selected, the date range defaults to the account's standard last-7-days range, and the table loads immediately without requiring any manual selection.

---

### User Story 2 - Manager changes the attribute or date range (Priority: P2)

Having viewed the breakdown for one attribute, the manager switches to a different list-type attribute, or narrows/widens the date range, to compare distributions or periods.

**Why this priority**: Comparing across attributes and periods is a natural follow-up to the core view, but the report already delivers value with a single attribute and default range (covered by P1).

**Independent Test**: Can be tested independently by changing the attribute selector or date-range filter on an already-loaded report and confirming the table refreshes with a loading indicator and updated data, without leaving the page.

**Acceptance Scenarios**:

1. **Given** the report is displaying data for one attribute, **When** the manager selects a different list-type opportunity attribute, **Then** the table reloads to show rows for the newly selected attribute's values.
2. **Given** the report is displaying data for one date range, **When** the manager selects a different date range, **Then** the won/lost counts and average time to close update for the new range, while the row set and open-opportunity counts follow the selected attribute (not the date range).

---

### User Story 3 - Account has no eligible attribute to report on (Priority: P3)

A manager on an account that hasn't yet defined a list-type opportunity custom attribute opens the report page.

**Why this priority**: Necessary for a clean first-run/edge experience, but only relevant to accounts that haven't configured this kind of attribute yet — a smaller slice of the overall audience.

**Independent Test**: Can be tested independently by loading the report page on an account with no list-type opportunity custom attributes defined and confirming a helpful empty state is shown instead of a broken or empty table.

**Acceptance Scenarios**:

1. **Given** an account with no list-type opportunity custom attributes defined, **When** the manager opens the report page, **Then** the attribute selector is empty and the page shows guidance directing them to create such an attribute, instead of showing an empty or broken table.

### Edge Cases

- What happens when someone requests the report with an attribute that isn't a list-type opportunity attribute (e.g. text attribute, or a conversation/contact attribute)? The request is rejected with a clear error rather than returning a misleading empty or partial report.
- How does the report handle an opportunity whose recorded attribute value no longer matches any of the attribute's currently-defined values (e.g. the value was renamed or removed after the opportunity was tagged)? It falls into the "no value" row automatically, with no manual migration needed.
- How does the report handle a currently-open opportunity with a value, when computing won/lost counts and average time to close? Open opportunities never count toward won/lost or time-to-close — those are computed only from opportunities closed within the selected period.
- How does average time to close handle opportunities that closed as lost? Lost opportunities are excluded from the average time-to-close figure; only won opportunities that closed within the period count.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a report page where the user selects exactly one list-type opportunity custom attribute and a date range to generate a report; on first load, the page MUST auto-select the first available list-type opportunity attribute (alphabetical by name) and the account's default report date range (last 7 days), and load the report immediately without requiring manual selection.
- **FR-002**: System MUST reject a report request whose selected attribute is not a list-type opportunity custom attribute belonging to the account, with a clear error rather than a silently empty or misleading result.
- **FR-003**: System MUST compute, for each value defined on the selected attribute plus one synthetic "no value" bucket for opportunities missing that attribute or with a value no longer defined on the attribute: the count and combined value of currently-open opportunities carrying that value, independent of the selected date range.
- **FR-004**: System MUST compute, for the same set of values, the count and combined value of opportunities that closed as won within the selected date range, and the count and combined value of opportunities that closed as lost within the selected date range.
- **FR-005**: System MUST compute, for the same set of values, the average time to close (from creation to closing) across only won opportunities that closed within the selected date range.
- **FR-006**: System MUST order the report rows to match the order the values are defined on the attribute, with the "no value" row always shown last.
- **FR-007**: System MUST return a zeroed row (not an omitted row, and not an error) for any value with no matching opportunities in the account or selected period.
- **FR-008**: System MUST let the user pick the attribute only from list-type opportunity custom attributes defined on the account — attributes of other data types or scopes MUST NOT be selectable.
- **FR-009**: System MUST present the report as a page reachable from the existing Reports navigation, using the account's existing date-range filter control.
- **FR-010**: System MUST re-generate and display the report whenever the user changes the selected attribute or the date range, showing a loading indicator during the refresh and keeping the user on the same page.
- **FR-011**: System MUST show an inline empty state, guiding the user to create a list-type opportunity custom attribute, when the account has none available to select — instead of showing an empty or broken table.
- **FR-012**: System MUST display each row's monetary total using the account's standard currency formatting, consistent with how opportunity values are formatted elsewhere in the product.
- **FR-013**: The report MUST be read-only; it MUST NOT allow editing an opportunity's attribute value from the report page.

### Key Entities *(include if feature involves data)*

- **Opportunity**: A sales deal tracked through the pipeline; already has a status (open/won/lost), value, creation time, and closing time. Carries custom attribute values, including the list-type attribute this report groups by.
- **Opportunity Custom Attribute Definition**: An account-defined field on opportunities, scoped to opportunities, with a data type (e.g. list) and — for list-type — an ordered set of allowed values. The report only supports definitions of the list-type, opportunity-scoped kind.
- **Attribute Value Row**: One aggregation bucket in the report, corresponding to one defined value of the selected attribute, or the synthetic "no value" bucket, holding the count and total value of open opportunities plus won/lost counts and average time to close for the selected period.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A sales manager can see how their open pipeline and recent win/loss outcomes break down across a custom category (e.g. treatment interest) on a single page, without exporting data or building a custom report.
- **SC-002**: The report loads and renders correctly for an account with a realistic volume of opportunities (hundreds, spread across all attribute values) within the same time expectations as other existing report pages.
- **SC-003**: Every possible value of the selected attribute is represented by exactly one row, including values with no matching opportunities, in 100% of report loads.
- **SC-004**: Switching the selected attribute or date range updates the visible table without navigating away from the page, in all cases.
- **SC-005**: An account with no list-type opportunity custom attributes sees actionable guidance instead of an empty or broken report, in 100% of such cases.

## Assumptions

- This phase depends on opportunity custom attributes and the funnel report's period-cohort conventions (open/currently-active data is not period-filtered; won/lost/closing-time data is period-filtered by closing date) already being in place.
- List-type opportunity custom attributes hold a single value per opportunity (not multiple simultaneous values), even though the value-picker UI may visually resemble a multi-select.
- Only list-type, opportunity-scoped custom attributes are supported by this report; attributes on conversations, contacts, or companies, and non-list opportunity attributes, are out of scope for this phase but could reuse the same underlying aggregation approach later if needed.
- The report is table-only for this phase; charts or visual breakdowns beyond the table are out of scope.
- Exporting the report (e.g. to CSV) is out of scope for this phase unless requested later.
- When an opportunity's recorded value no longer matches any value currently defined on the attribute (renamed/removed value), it is treated the same as a missing value and grouped under "no value" — no backfill or migration is performed.
