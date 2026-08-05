# Feature Specification: Graphical Funnel Chart

**Feature Branch**: `017-graphical-funnel-chart`

**Created**: 2026-08-05

**Status**: Draft

**Input**: User description: "Replace the bar-chart rendering of the conversion funnel on the Opportunity Funnel Report with a real funnel-shaped visualization: one continuous, curved-edge band per pipeline stage, narrowing proportionally to each stage's share of the period's total, styled with each stage's existing accent color, labeled with stage name/count/percentage, with hover detail — matching the reference funnel-chart pattern (see `docs/kanban/ciclo 4/08-graphical-funnel-chart/spec22.md` and the attached reference screenshot)."

## Clarifications

### Session 2026-08-05

- Q: When a pipeline stage has no `accent_color` set, what color should its funnel band use? → A: Fall back to the same default color the current bar chart already uses for uncolored stages (visual consistency with today)
- Q: Since the funnel report's backend doesn't currently expose a raw per-stage opportunity count (only percentages), should this feature include adding that count field to the backend, or stay frontend-only? → A: Include the backend change here — add a per-stage opportunity count field to the funnel report response as part of this feature

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View pipeline drop-off as a proportional funnel (Priority: P1)

A sales manager opens the Opportunity Funnel Report to understand how opportunities move through pipeline stages. Instead of a bar chart, they see a single continuous funnel shape: one band per stage, each narrower than the previous in proportion to how many opportunities remain at that stage, colored to match the stage's color elsewhere in the product (e.g. the kanban board).

**Why this priority**: This is the core value of the feature — replacing an abstract bar comparison with a shape that visually communicates drop-off and proportion at a glance. Without this, the feature doesn't exist.

**Independent Test**: Load the funnel report for an account with multiple pipeline stages and opportunity data; confirm a single tapered funnel shape renders in place of the bar chart, with band widths visibly proportional to each stage's share of the total.

**Acceptance Scenarios**:

1. **Given** an account with 5 pipeline stages and opportunity counts that decrease at each stage, **When** the manager opens the funnel report, **Then** they see 5 connected bands forming one continuous funnel, each narrower than the one before it, in stage order.
2. **Given** two stages have very different counts (e.g. one stage's count is a small fraction of the first stage's), **When** the funnel renders, **Then** the smaller stage's band renders proportionally thin rather than being hidden or clamped to a minimum size.
3. **Given** the same underlying data previously shown as a bar chart, **When** the funnel renders, **Then** the totals, percentages, and counts shown match exactly what the bar chart showed (no change to the underlying figures).

---

### User Story 2 - Read exact stage detail via hover (Priority: P2)

A user viewing the funnel wants the precise stage name, opportunity count, and percentage for a band that's too narrow to comfortably show all of that text inline.

**Why this priority**: Necessary for usability once bands get narrow (common with steep drop-offs), but the funnel is still useful without it since wider bands already show labels inline.

**Independent Test**: Render a funnel with at least one narrow band; hover over it and confirm a tooltip appears showing that stage's name, count, and percentage.

**Acceptance Scenarios**:

1. **Given** a funnel is rendered, **When** the user hovers over any band, **Then** a tooltip appears showing that band's stage name, opportunity count, and percentage of the period total.
2. **Given** the user moves the pointer away from a band, **When** the pointer leaves the band's area, **Then** the tooltip disappears.

---

### User Story 3 - Recognize stages by consistent color (Priority: P3)

A user who is already familiar with each pipeline stage's color from the kanban board wants to recognize the same stages in the funnel without relearning a new color scheme.

**Why this priority**: A nice-to-have consistency win; the funnel is functional even with a generic palette, but reusing the existing stage colors reduces cognitive load for returning users.

**Independent Test**: Compare the color of each funnel band against that stage's color on the kanban board for the same account; confirm they match.

**Acceptance Scenarios**:

1. **Given** a pipeline stage has a color assigned on the kanban board, **When** that stage's band renders in the funnel, **Then** the band uses that same color.

---

### Edge Cases

- What happens when a stage has zero opportunities? The band should still render (as a zero/near-zero-width segment) rather than being omitted, so the stage sequence stays visually intact.
- What happens when there is only one pipeline stage? The funnel should render a single band without erroring, rather than requiring at least two stages.
- How does the funnel behave when many stages exist (e.g. 8+)? Each band should remain individually visible and hoverable, even if inline labels no longer fit and rely on the hover tooltip.
- How does the chart handle a stage whose value is identical to the previous stage's (no drop-off)? The band width should remain visually equal to the previous band's, not artificially narrowed.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The funnel report MUST display the conversion funnel as a single continuous tapering shape (one band per pipeline stage), replacing the previous bar-chart rendering, everywhere the conversion funnel currently appears on the report.
- **FR-002**: Bands MUST appear in pipeline stage order, each stage's band width proportional to that stage's share of the period's total opportunity count, using the exact same underlying figures already served by the funnel report (no recalculation).
- **FR-003**: Adjacent bands MUST connect with smoothly curved transitions rather than abrupt, disconnected rectangles, preserving the funnel's single continuous silhouette.
- **FR-004**: Each band MUST be colored using that pipeline stage's existing accent color (the same color already used to identify the stage on the kanban board). For a stage with no accent color set, the band MUST fall back to the same default color the current bar chart already uses for uncolored stages.
- **FR-005**: Each band MUST display its stage name, opportunity count, and percentage of the period total; the percentage MUST be visually set apart (e.g. a distinct badge-style treatment) from the count.
- **FR-006**: Hovering any band MUST show a tooltip with that stage's full detail (name, count, percentage), so the detail remains available even when a band is too narrow to show all labels inline.
- **FR-007**: The feature MUST NOT alter the conversion funnel's existing calculation or filtering, or affect the report's other charts — only the conversion funnel chart's rendering, plus the one additive data field in FR-008, changes.
- **FR-008**: The funnel report's backend response MUST be extended with a raw per-stage opportunity count (alongside the existing percentage figure already served), so FR-005's count display is backed by real data rather than being omitted; this is an additive field only — no existing field is renamed, removed, or recalculated.

### Key Entities

- **Pipeline Stage**: An ordered stage within a sales pipeline (e.g. "Lead", "Qualified", "Won"), already carrying a display color and a position/order. Represented in the funnel as one band.
- **Conversion Funnel Data Point**: For a given period, each pipeline stage's opportunity count and its percentage of the period's total created count. The percentage is existing data already powering the current bar-chart rendering; the raw opportunity count is a new field added by this feature (FR-008).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can visually identify which pipeline stage has the steepest drop-off within 5 seconds of viewing the funnel, without needing to read exact numbers.
- **SC-002**: 100% of pipeline stages with nonzero data render as a visible, hoverable band, regardless of how small their share of the total is.
- **SC-003**: The figures (counts, percentages) shown in the new funnel visualization match the figures previously shown in the bar chart for the same data, with zero discrepancies.
- **SC-004**: Users can retrieve exact stage detail (name, count, percentage) for any band — including bands too narrow for inline text — within one hover interaction.

## Assumptions

- This feature is primarily presentation-only: it reuses the `conversion_funnel` data already served by the Opportunity Funnel Report (shipped in the prior "Opportunity Funnel Report" phase) with no change to existing calculation or filtering. The one exception is FR-008: the backend response gains an additive raw-count field it doesn't currently expose, needed to satisfy FR-005.
- "Accent color" refers to the pipeline stage color already used for kanban lane styling; no new color scheme is introduced.
- The reference visual pattern (continuous curved-edge tapering bands, inline labels, badge-styled percentage, hover tooltip) follows the attached reference screenshot and the linked external funnel-chart component pattern; exact pixel-level styling is left to design/implementation, not prescribed here.
- Only the conversion funnel chart on the funnel report page is affected; no other chart on that page changes.
- Animations/transitions beyond what's needed for a static funnel render are out of scope.
