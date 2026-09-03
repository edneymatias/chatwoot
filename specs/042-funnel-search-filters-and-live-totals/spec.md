# Feature Specification: Funnel Search Filters and Live Totals

**Feature Branch**: `042-funnel-search-filters-and-live-totals`

**Created**: 2026-09-02

**Status**: Draft

**Input**: User description: "docs/kanban/ciclo 11/14-funnel-search-filters-and-live-totals/spec82.md" — Three related gaps in the Kanban funnel's top bar (search input + filter modal + totals badges): (1) free-text search doesn't match campaign attribution fields (campaign name, ad group, ad, platform) already stored on the opportunity; (2) the advanced filter builder doesn't expose campaign fields or opportunity `created_at`/`updated_at` as filterable attributes; (3) the header totals and per-column Kanban badges are fetched once on mount with a hardcoded "open" status and never react to search, filters, or a status change to Won/Lost/All.

## Clarifications

### Session 2026-09-02

- Q: What response-time target should the expanded search, new campaign/date filters, and the live totals refresh meet at real production data volumes? → A: Under 1 second — typical interactive search/filter norm; matches today's existing search feel.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Find opportunities by campaign via search (Priority: P1)

A sales operator remembers a lead came from a specific Facebook ad or campaign but doesn't remember the contact's name or the deal title. They type the campaign name, ad group, ad name, or platform into the Kanban search box and expect matching opportunities to appear, the same way searching by title or contact name already works today.

**Why this priority**: This is the most frequently hit gap in real usage — attribution data already exists on every opportunity created via Meta referral/CTWA, but today it's invisible to search, forcing operators to scroll the whole board manually.

**Independent Test**: Can be fully tested by creating an opportunity with known campaign attribution values, typing a fragment of one of those values into the funnel's search box, and confirming the opportunity appears in results — independent of any filter or totals change.

**Acceptance Scenarios**:

1. **Given** an opportunity whose `campaign_name` is "Black Friday Leads", **When** the operator types "black friday" into the Kanban search box, **Then** that opportunity appears in the results, matched case-insensitively on a partial value.
2. **Given** an opportunity attributed to platform "facebook", **When** the operator types "facebook" into the search box, **Then** that opportunity appears alongside any others matching by title or contact name.
3. **Given** an opportunity with no campaign attribution data, **When** the operator searches by that opportunity's title, **Then** it still appears (no regression to today's title/contact-name search).

---

### User Story 2 - Filter opportunities by campaign attribution and date (Priority: P2)

An operator building a report or narrowing the board wants to see only opportunities from a given ad group, exclude a specific platform, or bound the board to opportunities created or last updated within a date range — using the same advanced filter modal already used elsewhere in the product.

**Why this priority**: Filtering is the natural next step after search for the same underlying gap (attribution data not exposed to the funnel's discovery tools), but it's a smaller share of real usage than free-text search, and depends on the same field set already covered conceptually by User Story 1.

**Independent Test**: Can be fully tested by opening the filter modal, selecting a campaign or date attribute with an operator (e.g. "contains", "is greater than"), applying it, and confirming the result set matches the expected subset — independent of search box behavior or totals refresh.

**Acceptance Scenarios**:

1. **Given** opportunities with varying `campaign_adset_name` values, **When** the operator applies a filter "Ad group contains 'summer'", **Then** only opportunities whose ad group name contains "summer" (case-insensitive, partial match) are shown.
2. **Given** opportunities attributed to both "facebook" and "instagram", **When** the operator applies a filter "Platform equals Facebook", **Then** only Facebook-attributed opportunities are shown, selectable from a fixed two-option dropdown (Facebook/Instagram).
3. **Given** opportunities created on different dates, **When** the operator applies a filter "Created at is greater than [date]", **Then** only opportunities created after that date are shown, using the same date-filter behavior already available for other date fields in this filter (e.g. "is less than", "days before").
4. **Given** the filter modal is opened in either supported language, **When** the operator looks at the attribute list, **Then** the new campaign and date attributes are labeled in that language (English or Brazilian Portuguese).

---

### User Story 3 - Totals stay accurate as search, filters, and status change (Priority: P1)

An operator searches, filters, or switches the board's status view (e.g. from "Open" to "Won", "Lost", or "All") and expects the header's total count/value and each column's own badge to immediately reflect what's actually visible — not a stale, always-"open" number computed once when the board first loaded.

**Why this priority**: This is a correctness bug affecting every existing use of the board today, not just the new campaign/date capabilities — totals are actively misleading whenever an operator changes status or filters, which happens constantly. It ties for top priority with User Story 1 because it's the most visible and most reported issue.

**Independent Test**: Can be fully tested by loading the board (confirming today's default "open" totals are unchanged), then applying a search term, a filter, and separately switching status to Won/Lost/All, confirming the header and column totals update each time without a page reload.

**Acceptance Scenarios**:

1. **Given** the board has just loaded with no search/filter applied, **When** the operator views the header totals and column badges, **Then** they match exactly what was shown before this feature (open-only counts/values) — no regression to the default view.
2. **Given** the operator types a search term, **When** results narrow to a subset of opportunities, **Then** the header total count/value and every visible column's badge update to reflect only the matching subset, without reloading the page.
3. **Given** the operator applies an advanced filter, **When** the filtered result set changes, **Then** totals update the same way as in the search scenario.
4. **Given** the operator switches the status view to "Won", "Lost", or "All", **When** the view changes, **Then** totals recompute to reflect that status scope instead of remaining stuck on open-only numbers.
5. **Given** the operator clears all search/filter input, **When** the board returns to its default view, **Then** totals return to matching the default open-only numbers from scenario 1.

---

### Edge Cases

- What happens when a search term or filter value matches zero opportunities? Totals (header and every column) MUST show zero/empty rather than stale or error values.
- What happens when a campaign attribution field is blank on a given opportunity (e.g. it wasn't created via Meta referral/CTWA)? That opportunity simply doesn't match a search/filter against those fields, but remains matchable via title/contact name/other filters as normal.
- What happens if a new campaign platform value appears in the data beyond "facebook"/"instagram" (the only two the attribution extractor currently produces)? Out of scope for this feature — the fixed dropdown only needs to be revisited if and when a real third value appears in production.
- What happens when search/filter/status changes fire in rapid succession (e.g. fast typing)? Each change triggers its own totals refresh, consistent with how the card list itself already behaves today — no new debouncing is introduced or expected here.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The Kanban funnel's free-text search MUST match opportunities whose campaign name, ad group name, ad name, or platform contains the search term (case-insensitive, partial match), in addition to the existing title and contact-name matches.
- **FR-002**: Free-text search on the expanded field set, the new campaign/date filters, and the totals refresh MUST each return results in under 1 second at production data volumes — the same interactive feel as today's existing title/contact-name search.
- **FR-003**: The advanced filter builder MUST offer campaign name, ad group name, and ad name as filterable text attributes, each supporting "contains" and "does not contain" partial-match operators.
- **FR-004**: The advanced filter builder MUST offer platform as a filterable attribute with a fixed set of selectable values (Facebook, Instagram), supporting "equals" and "not equal to" operators.
- **FR-005**: The advanced filter builder MUST offer the opportunity's creation date and last-updated date as filterable attributes, supporting the same date comparison operators already available for existing date attributes elsewhere in this filter (e.g. "is greater than", "is less than", "days before").
- **FR-006**: All new filter attribute labels MUST be presented in the user's active language, with both English and Brazilian Portuguese translations available.
- **FR-007**: The header totals (count and value) and each Kanban column's own badge MUST recompute whenever the search term changes, whenever an advanced filter is applied or cleared, and whenever the status view changes.
- **FR-008**: Totals MUST honor the currently selected status scope (Open, Won, Lost, or All) rather than always computing against "open" opportunities regardless of what the operator is viewing.
- **FR-009**: When no search, filter, or non-default status is active, totals MUST match today's existing default behavior (open-only counts/values) exactly — no regression to the unfiltered view.
- **FR-010**: Totals MUST reflect only the current, live filtered/searched view — no historical trend or point-in-time snapshot is in scope.

### Key Entities

- **Opportunity**: A sales lead/deal tracked on the Kanban funnel. Relevant existing attributes for this feature: title, associated contact, pipeline stage, status (open/won/lost), value, creation and last-updated timestamps, and campaign attribution fields (campaign name, ad group name, ad name, platform) populated when the opportunity originates from a Meta referral/click-to-WhatsApp ad.
- **Pipeline Stage Totals**: A per-stage and board-wide aggregate (count of opportunities, sum of their value) shown in the header and on each Kanban column, scoped to whatever combination of search term, filter, and status is currently active.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An operator can locate an opportunity by any of its campaign attribution values (campaign, ad group, ad, or platform) using the same search box already used for title/contact-name lookups, with no separate search mode to learn.
- **SC-002**: 100% of header and column totals reflect the currently visible (searched/filtered/status-scoped) set of opportunities at all times, with zero instances of stale "open-only" numbers persisting after a search, filter, or status change.
- **SC-003**: Search, filter application, and totals refresh each complete in under 1 second at current production data volumes, matching today's existing search's perceived responsiveness.
- **SC-004**: The default (no search/filter, open status) view's totals are byte-for-byte identical to pre-feature behavior, confirmed with zero regressions.
- **SC-005**: All new filter attributes are usable and correctly labeled in both languages the product supports (English and Brazilian Portuguese).

## Assumptions

- Campaign attribution fields (`campaign_name`, `campaign_adset_name`, `campaign_ad_name`, `campaign_platform`) already exist on every opportunity and are populated today for Meta referral/CTWA-originated leads; this feature only makes existing data discoverable, it does not change how that data is captured.
- Platform values are limited to "Facebook" and "Instagram" for the lifetime of this feature; support for additional platforms is an explicit non-goal, to be handled as a small follow-up if it ever becomes necessary.
- No debouncing exists today for search-as-you-type or filter application in this view, and this feature does not introduce any — each keystroke/filter/status change is expected to trigger its own refresh, consistent with existing behavior.
- This feature covers only the *current* live filtered/searched view's totals; historical trends or point-in-time snapshots of totals over time are a separate, already-tracked area of work and are out of scope here.
- The row count shown elsewhere in the product's list view of opportunities (outside the Kanban board) is unaffected, since it already receives the active filters through its own existing data flow.
- Full-text search remains a simple partial-match (case-insensitive "contains") search; no relevance ranking or scoring is introduced.
