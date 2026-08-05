# Phase 0 Research: Graphical Funnel Chart

## Decision 1 — Rendering approach: hand-built inline SVG, not a charting library

**Decision**: Build `FunnelChart.vue` as a custom Vue component that renders inline SVG
(`<path>` elements with cubic Bézier curves for the tapering band edges), not via Chart.js/
vue-chartjs (used by the sibling `BarChart.vue`/`DonutChart.vue`/`LineChart.vue`) or any other
charting library.

**Rationale**: Chart.js has no built-in funnel/trapezoid mark type; forcing bars to approximate a
funnel (the previous rendering) can't produce the continuous, curved-edge tapering silhouette the
spec (FR-002, FR-003) and reference image require. Hand-built SVG gives full control over the
per-band curved path and keeps the bundle free of a second charting dependency. No existing custom
SVG chart component exists in this codebase to reuse (confirmed by search) — this establishes the
pattern for future custom shapes if needed, without adding one until now.

**Alternatives considered**:
- *Chart.js custom funnel plugin* — no first-party funnel chart type exists for Chart.js; would
  require a third-party plugin (new dependency, uncertain maintenance) to get curved edges.
  Rejected: adds a dependency for a shape simple enough to hand-build with SVG paths.
- *A dedicated funnel-chart npm package* (e.g. d3-funnel-style libraries) — adds a new dependency
  for a single chart, harder to theme with existing Tailwind/design tokens, and typically ships
  its own DOM/canvas rendering that doesn't compose cleanly with the report page's existing
  hover-tooltip and badge patterns. Rejected per Constitution Principle II (smallest change,
  no speculative new tooling).
- *CSS clip-path trapezoids* — could approximate straight-edged trapezoids cheaply, but cannot
  produce the smooth curved transitions FR-003 requires without significant hackery beyond a
  single band. Rejected.

## Decision 2 — `conversion_funnel` payload: backend exists in `custom/`; add `counts` additively

**Correction to an earlier research pass**: an initial search of `app/` and `enterprise/` found
no controller/service for this endpoint and concluded the backend didn't exist. That was wrong —
this fork places its own domain features under a dedicated `custom/` overlay (autoloaded via
`config/application.rb`, mirroring the `enterprise/` convention per Constitution Principle I), not
under `app/`. The real implementation is:

- `custom/app/services/reports/opportunity_funnel_builder.rb` — `Reports::OpportunityFunnelBuilder`,
  whose `#build` returns `conversion_funnel: conversion_funnel` (among six other report sections).
  `#conversion_funnel` (private) already computes, per pipeline stage in position order: `labels`
  (stage names), `count_data` (percentage 0–100 of period-created opportunities reaching that
  stage or later), and `won_rate_pct`.
- `custom/app/controllers/api/v1/accounts/opportunity_funnel_reports_controller.rb` — already
  wired to the existing route (`config/routes.rb`), already Pundit-authorized via `ReportPolicy`,
  already `render json: report` — i.e. it renders the builder's hash verbatim, so **any new key
  added to `#conversion_funnel`'s return hash flows to the frontend with no controller change**.

**Decision**: Add the raw per-stage opportunity `counts` array (the large headline number in the
reference image, alongside the percentage badge) as one additive key inside
`#conversion_funnel`'s existing return hash. The private helper `max_stage_positions_reached`
already builds a `{opp_id => max_position_reached}` hash to compute `count_data`'s percentages
(via `funnel_pct`); `counts[i]` is simply `reached.count { |_id, max_pos| max_pos >= stage.position }`
— the same count `funnel_pct` already computes internally before dividing by `total`. No new
query, no new N+1 risk: it's a pure-Ruby aggregation over data already pulled into memory.

**Alternatives considered**:
- *New dedicated field/endpoint just for counts* — rejected; the existing `conversion_funnel` key
  is exactly where the reference image's per-band figures belong, and a second round-trip/endpoint
  would be needless indirection for one array.
- *Derive counts on the frontend from `count_data` (percentage) × `total`* — the frontend doesn't
  have `total` (period-created opportunity count) available as a standalone value anywhere in the
  current payload, and reverse-deriving an integer count from a rounded percentage (`count_data`
  is `.round(1)`) would produce inaccurate, rounding-error-prone counts for large totals (e.g. the
  reference image's 2,895,099). Rejected — the backend already has the exact integer; expose it
  directly instead of asking the frontend to approximate it.

## Decision 3 — Dynamic per-stage color without a new styling escape hatch

**Decision**: `FunnelChart.vue` accepts a `color` (hex string) per point and binds it to the SVG
`fill` presentation attribute via `:fill="point.color"`, exactly mirroring how `BarChart.vue`
already receives a per-bar `backgroundColor` array computed from `accent_color`.

**Rationale**: Per-stage accent colors are arbitrary hex values from `pipeline_stages.accent_color`
(a database column), which cannot be represented as static Tailwind utility classes. This is the
same constraint the existing bar/donut/line charts already have, so it's an established,
consistent exception rather than a new one — not a `style=""` inline style, and not custom CSS.

**Alternatives considered**:
- *CSS custom properties + Tailwind arbitrary-value classes* (e.g. `class="fill-[var(--stage-color)]"`)
  — technically avoids a literal `fill=""` attribute, but adds indirection with no practical
  benefit over the direct, already-precedented attribute binding. Rejected as unnecessary
  complexity for the same outcome.

## Decision 4 — Hover tooltip: lightweight custom implementation, not a new tooltip library

**Decision**: Implement the hover tooltip (FR-006) as a small piece of local component state
(`hoveredIndex`) toggled by `@mouseenter`/`@mouseleave` on each band, rendering a simple
absolutely-positioned Tailwind-styled tooltip element — no new dependency.

**Rationale**: The report page has no existing shared tooltip component to reuse (Chart.js charts
render tooltips internally via the library, which doesn't apply here), and the interaction is
simple enough (show/hide on hover, static content) that a dependency would be disproportionate.

**Alternatives considered**:
- *Native SVG `<title>` element* — simplest option, but renders a slow, unstyleable native
  browser tooltip inconsistent with the badge/typography style the rest of the report uses.
  Rejected: doesn't meet the "full detail, styled" expectation in FR-006 and the reference image.
- *A floating-UI/popper-style positioning library* — overkill for a fixed-position tooltip
  anchored to a band directly beneath the pointer; adds a dependency for a case simple CSS
  positioning handles. Rejected per Constitution Principle II.
