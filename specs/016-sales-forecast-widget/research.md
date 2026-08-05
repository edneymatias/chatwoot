# Research: Sales Forecast Widget (Preview)

## Decision 1: Where the forecast is computed

**Decision**: Add a `sales_forecast` private method to the existing
`Reports::OpportunityFunnelBuilder` (`custom/app/services/reports/opportunity_funnel_builder.rb`)
and include its result under a new `sales_forecast` key in `#build`'s
returned hash. No new service class, controller action, or route.

**Rationale**: The endpoint (`Api::V1::Accounts::OpportunityFunnelReportsController#index`)
already returns one JSON payload assembled entirely by this one builder; the
spec explicitly frames this as an 8th card on the same report, computed by
"the same `Reports::OpportunityFunnelBuilder` service" (source doc,
`FR-001`). Adding a key is the smallest change (Constitution Principle II)
and keeps the single-request, single-builder shape every other metric
already follows.

**Alternatives considered**: A separate `Reports::SalesForecastBuilder`
service composed into the funnel builder — rejected as unnecessary
indirection for one additional computed hash that reuses the funnel
builder's own stage/duration data internally (see Decision 2).

## Decision 2: Reusing existing stage-duration and stage-reach data

**Decision**: The forecast reuses two pieces of data the builder already
computes for other metrics:
- `build_stage_durations` (existing private method) — per-stage completed
  interval durations, already used by `avg_time_in_stage`. The forecast's
  `expected_close_date` offset for a stage reuses the same per-stage
  average (in days), summed across the opportunity's current stage and
  every later stage by `position`.
- A new lifetime (non-period-scoped) stage-reach calculation, structurally
  similar to the existing `max_stage_positions_reached` helper used by
  `conversion_funnel`, but run over **all** of the account's opportunities
  (not `period_created_opportunities`) since stage win-probability is
  explicitly defined as lifetime, not period-scoped (FR-002).

**Rationale**: Avoids recomputing stage-transition data twice from
`OpportunityStageChange`; `build_stage_durations` already derives
consecutive-interval durations per stage from every stage change,
independent of any date range, so it is fetched once and shared between
`avg_time_in_stage` and the forecast's expected-close-date calculation. The
existing `max_stage_positions_reached` pattern is proven and just needs a
different (unscoped) input opportunity set.

**Alternatives considered**: A dedicated SQL aggregate per forecast field —
rejected; the existing per-stage duration/reach data already answers what's
needed, and a second query pass would duplicate logic without saving
queries (both approaches are O(number of stage changes) once).

## Decision 3: Stage win probability calculation

**Decision**: For each pipeline stage, count opportunities (lifetime,
whole account) whose stage-change history shows they reached that stage
(`max position reached >= stage.position`, reusing Decision 2's lifetime
reach set) and are currently closed (`won` or `lost`). Win probability =
`won_count / (won_count + lost_count)`, memoized once per `build` call as a
`stage_id => Float` hash (0.0–1.0). Currently-open opportunities that
reached a stage do not count toward that stage's probability (per source
doc: "closed `won` ÷ closed `won` + closed `lost`").

**Rationale**: Directly matches FR-002's stated formula; memoizing avoids
recomputing the reach set once per open opportunity.

**Alternatives considered**: Per-current-stage-only reach (ignoring stages
passed through earlier) — rejected, contradicts the source doc's explicit
"opportunities that have passed through the opportunity's current stage"
definition, which is a reach-or-later concept identical to the existing
conversion-funnel semantics.

## Decision 4: Data-sufficiency gate

**Decision**: The forecast activates only when, for every pipeline stage
(`account.pipeline_stages`), the durations hash from Decision 2 has at
least one recorded duration, **and** the account has at least one `won`
and at least one `lost` opportunity overall
(`account.opportunities.won.exists?` / `.lost.exists?`). If any part fails,
`sales_forecast` is `{ status: "insufficient_data" }`; otherwise it's
`{ status: "ok", total_weighted_value:, buckets: {...} }`.

**Rationale**: Matches FR-003/FR-006 exactly (all-or-nothing across the
whole pipeline). Checking `durations_by_stage[stage.id].present?` (not
`stage_avg_days == 0.0`) correctly distinguishes "no completed transitions
yet" from "completed transitions that happened to average to a
near-zero/rounds-to-zero duration."

**Alternatives considered**: Treating `stage_avg_days` returning `0.0` as
equivalent to "no data" — rejected as a correctness bug (a genuinely fast
stage would be wrongly treated as insufficient).

## Decision 5: Bucketing and boundary rule

**Decision**: Compute `days_until_close = (expected_close_date - Date.current).to_i`
(can be negative for overdue opportunities), then bucket by:
`days_until_close <= 30` → `0_30`; `<= 60` → `31_60`; `<= 90` → `61_90`;
`> 90` → excluded entirely. This folds negative/overdue values into `0_30`
(per source doc and spec Edge Cases) and applies "day exactly on a
boundary belongs to the earlier bucket" (per `/speckit-clarify` decision)
uniformly across all three boundaries, consistent with the already-decided
"more than 90 excludes, so exactly 90 is included" upper-bound rule.

**Rationale**: A single `<=` chain is the simplest implementation of an
inclusive-lower/exclusive-upper convention and needs no special-casing for
the overdue case (negative numbers already satisfy `<= 30`).

**Alternatives considered**: Separate explicit overdue handling — rejected,
unnecessary since the `<=30` check already captures it.

## Decision 6: Frontend visualization — three-part layout reusing `ReportMetricCard.vue` and `BarChart.vue` (no donut, no new component)

**Decision**: Superseded from an earlier donut-based approach after
reviewing the actual mockup (`VENDAS EM POTENCIAL`). The forecast card is
laid out as three pieces side by side, matching the mockup and reusing
components already present on this exact page:

- **Left**: a `ReportMetricCard`-style big number for the current open
  pipeline baseline — count of currently-open opportunities feeding the
  forecast and their raw (unweighted) total value (mockup: "Agora ativo
  leads — 329 leads / R$10.000").
- **Middle**: `BarChart.vue` (`app/javascript/shared/components/charts/BarChart.vue`)
  — already imported by this page's build (same `vue-chartjs`/Chart.js
  dependency as `DonutChart.vue`/`LineChart.vue`, just not yet instantiated
  on this particular page) — one bar per bucket (`0–30`, `31–60`, `61–90`),
  a single dataset of `weighted_value`, y-axis formatted as currency.
- **Right**: a second `ReportMetricCard`-style big number for the
  probability-weighted grand total — opportunity count across all three
  buckets and `total_weighted_value` (mockup: the right-side circle, "5
  leads / R$1.000.000"). Rendered as a big number using the same
  `ReportMetricCard` markup as the left card (not a literal Chart.js
  donut/ring) — the mockup's circular outline is a decorative CSS border,
  not a chart, since `ReportMetricCard.vue` already has no such visual and
  adding one is a trivial Tailwind `rounded-full border` treatment, not a
  new component.

**Rationale**: The user directed reuse of the already-implemented funnel
dashboard's own patterns instead of a from-scratch custom component:
`ReportMetricCard.vue` (`label`/`value`/`infoText` props) already renders
exactly the "big number" style the mockup's left/right stats need, and
`BarChart.vue` already renders exactly the "3 comparable magnitude bars"
style the mockup's middle section needs — both already exist and are
already used elsewhere on this same page (`ReportMetricCard` in the
"Metric Cards Row"; `BarChart`/`DonutChart`/`LineChart` siblings in the
"Charts Container"). This satisfies FR-008 ("visually represent the total
weighted value and the three time buckets... with the total distinctly
displayed as the overall headline figure") with zero new components,
consistent with Constitution Principle II and III (established
conventions).

**Alternatives considered**: (a) A segmented 3-slice `DonutChart.vue` with
a plain list below — the original approach before the mockup was supplied;
rejected as it does not match the actual intended visual. (b) A fully
custom Tailwind-only component for both the ring and the bars — rejected
per explicit user direction to reuse the existing dashboard's established
`ReportMetricCard`/`BarChart` patterns instead of inventing new markup.

## Decision 7: Bar chart dataset shape and left/right big-number sourcing

**Decision**: `BarChart.vue`'s `collection` prop is built as
`{ labels: [BUCKET_0_30, BUCKET_31_60, BUCKET_61_90 i18n labels], datasets: [{ data: [bucket weighted_values] }] }`,
mirroring the same `collection`-building pattern already used for the
page's other `BarChart`-family charts. The left `ReportMetricCard` sources
its `count`/`value` from a new `current_pipeline` aggregate (see contract
update below — the simple, non-probability-weighted count/sum of every
open opportunity feeding the forecast); the right `ReportMetricCard`
sources its count from the sum of the three buckets' `count` and its value
from `total_weighted_value` (already in the contract). No new list/table
component; no color-swatch list (superseded — the mockup has no such list,
just the three bars directly).

**Rationale**: Matches the mockup's actual three-part composition with the
smallest possible new surface: one new simple aggregate field
(`current_pipeline`) plus reuse of two already-contracted fields
(`total_weighted_value`, `buckets[*].count`) for the right card, and a
standard `BarChart.vue` collection for the middle.

**Alternatives considered**: Computing the right card's count from a
separate query — rejected, it's already derivable by summing the three
bucket counts already being computed.

## Decision 8: Empty/insufficient-data state

**Decision**: Reuse the existing `dashboard/components/widgets/EmptyState.vue`
component (already imported by `AssigneePerformanceTable.vue` on this same
page) with `title`/`message` props, in place of the donut + bucket list,
when `sales_forecast.status === 'insufficient_data'`. No icon is added —
`EmptyState.vue`'s current API doesn't expose one, and adding one would be
a component-API change beyond this feature's scope.

**Rationale**: Directly reuses an already-present, already-imported
component on the exact same page for the exact same "no data yet" concept,
satisfying FR-009 ("clearly worded explanatory message") without any new
component or component-API surface.

**Alternatives considered**: A bespoke empty-state block with an icon
(matching source doc's "icon + message" phrasing) — rejected; the feature
spec's `FR-009` only requires a clearly worded message, and introducing an
icon prop to a shared component (or a one-off bespoke block) is unjustified
extra surface for a preview card, per Constitution Principle II.

## Decision 9: "Preview" badge

**Decision**: A small inline `<span>` pill next to the card title, styled
with existing Tailwind utility classes (matching the visual weight of
similar small status/beta indicators already in the codebase, e.g.
rounded-full, small text, muted background) — no new shared `Badge`
component, since no generic reusable badge component currently exists in
this codebase to extend, and one card needing this once doesn't justify
introducing one.

**Rationale**: Smallest production-ready change; a handful of Tailwind
classes on a `<span>` fully satisfies FR-007's "visibly marked as a
preview" requirement.

**Alternatives considered**: None — no existing badge component was found
to reuse (searched `components-next` for `Badge`/`Tag` components; existing
matches are all domain-specific, e.g. `CallStatusBadge.vue`).

## Decision 10: i18n keys

**Decision**: New keys nest under the existing `OPPORTUNITY_FUNNEL_REPORTS`
namespace in `app/javascript/dashboard/i18n/locale/en/report.json`
(`en.json` per repo convention — Frontend i18n), e.g.
`OPPORTUNITY_FUNNEL_REPORTS.CHARTS.SALES_FORECAST`,
`OPPORTUNITY_FUNNEL_REPORTS.SALES_FORECAST.PREVIEW_BADGE`,
`OPPORTUNITY_FUNNEL_REPORTS.SALES_FORECAST.BUCKET_0_30` /
`BUCKET_31_60` / `BUCKET_61_90`,
`OPPORTUNITY_FUNNEL_REPORTS.SALES_FORECAST.INSUFFICIENT_DATA_TITLE` /
`INSUFFICIENT_DATA_MESSAGE`. Only `en.json` is edited (per `CLAUDE.md`
i18n rule); other locales stay Crowdin-owned, with no named exception
requested here (unlike `015-opportunity-funnel-report`'s pt-BR exception).

**Rationale**: Matches the exact nesting/casing convention already
established by Phase 21's own keys in the same file.

## Summary — no NEEDS CLARIFICATION remain

All Technical Context items are resolved by the decisions above and by
direct inspection of the existing `015-opportunity-funnel-report`
implementation (builder, controller, `DonutChart.vue`, report page,
`EmptyState.vue`). No new dependencies, migrations, routes, or shared
components are introduced.
