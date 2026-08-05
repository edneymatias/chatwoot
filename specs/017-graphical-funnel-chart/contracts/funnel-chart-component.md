# Component Contract: `FunnelChart.vue`

Location: `app/javascript/shared/components/charts/FunnelChart.vue`

Follows the same `<script setup>` + prop-driven convention as sibling chart components
(`BarChart.vue`, `DonutChart.vue`, `LineChart.vue`) in the same directory.

## Props

| Prop     | Type    | Required | Default | Description |
|----------|---------|----------|---------|-------------|
| `points` | `Array<{ label: string, percentage: number, count: number, color: string }>` | No | `[]` | Ordered list of funnel bands, first-to-last. Empty array renders an empty state (no bands), matching the sibling charts' `collection`-empty behavior. |
| `valueLabel` | `String` | No | `''` | Optional accessible label for the chart region (e.g. `"Conversion Funnel"`), mirrors how the page already titles each chart section — passed through for `aria-label`, not rendered as visible text (the page already renders its own `<h3>` title above the chart). |

No `chartOptions`/`clickable` props are carried over from `BarChart.vue` — this component has no
click-through interaction in its initial scope (spec has no requirement for it); only hover is
required (FR-006).

## Emits

None. Unlike `BarChart.vue`'s `elementClick`, the funnel chart has no spec requirement to notify
its parent of interactions — hover tooltips are fully self-contained within the component.

## Rendering contract

- Renders one `<path>` (or `<svg>` group) per `points` entry, in array order, each tapering from
  the previous band's ending width to a width proportional to `percentage` (relative to the first
  point's `percentage`, matching the reference visual where the first band is 100%).
- Adjacent bands share a smooth Bézier-curved boundary — no hard rectangular seams between bands.
- Each band's `fill` is bound to that point's `color`.
- Each band shows, inline when space allows: `label`, a badge-styled `percentage`, and `count`.
- Hovering any band shows a tooltip with that band's full detail (`label`, `count`, `percentage`),
  positioned near the pointer/band, hidden on `mouseleave`.
- A `points` array of length 0 renders an empty container (no error, no placeholder text
  required — the parent page already has its own empty-state handling for the whole report).
- A `points` array of length 1 renders a single band without error.

## Non-goals (explicitly out of scope for this contract)

- No click/selection emit.
- No animation/transition contract beyond what's needed for a static render (per spec
  Assumptions).
- No responsibility for sorting/ordering `points` — the caller supplies them pre-ordered.
