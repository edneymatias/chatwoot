# Implementation Plan: Graphical Funnel Chart

**Branch**: `017-graphical-funnel-chart` | **Date**: 2026-08-05 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/017-graphical-funnel-chart/spec.md`

**Note**: This template is filled in by the `/speckit-plan` command; its definition describes the execution workflow.

## Summary

Replace the bar-chart rendering of the Opportunity Funnel Report's "Conversion Funnel" chart
with a new custom `FunnelChart.vue` component: a single continuous, curved-edge SVG shape with
one tapering band per pipeline stage, colored with each stage's existing `accent_color`, labeled
inline with stage name/count/percentage (badge-styled percentage), and a hover tooltip for detail.

**Correction from the prior plan revision**: earlier research incorrectly concluded the
`conversion_funnel` backend didn't exist. It does — `Reports::OpportunityFunnelBuilder`
(`custom/app/services/reports/opportunity_funnel_builder.rb`), wired through
`Api::V1::Accounts::OpportunityFunnelReportsController` and `ReportPolicy`, already ships
`{ labels, count_data (percentage), won_rate_pct }`. It was missed because the fork places its
own domain features under `custom/app/`, not `app/`. Per FR-008 (added during `/speckit-clarify`),
this plan now includes one small additive change to that existing service — adding a `counts`
array (raw per-stage opportunity count) to its `conversion_funnel` output — alongside the
frontend chart swap.

## Technical Context

**Language/Version**: JavaScript (Vue 3, Composition API with `<script setup>`) for the frontend
chart; Ruby (matching the repo's existing Rails version, no change) for the one backend method
edit. No new language introduced on either side.

**Primary Dependencies**: Vue 3, Tailwind CSS, `vue-i18n` on the frontend — no new dependency;
Chart.js (already used by `BarChart.vue`/`DonutChart.vue`/`LineChart.vue`) is deliberately **not**
reused for this chart, since it has no native funnel/trapezoid mark type, so the shape is
hand-built as inline SVG (FR-001–FR-003). On the backend, no new gem — `Reports::OpportunityFunnelBuilder`
already exists and uses plain ActiveRecord/`pattr_initialize`; the change is additive logic inside
its existing `conversion_funnel` private method.

**Storage**: No schema change. `Opportunity`/`OpportunityStageChange`/`PipelineStage` tables
(`matias_opportunities`, `matias_opportunity_stage_changes`, `matias_pipeline_stages`) are read
via ActiveRecord exactly as `Reports::OpportunityFunnelBuilder` already does for `count_data`;
the new `counts` array reuses the same `max_stage_positions_reached` data already computed for the
percentage calculation, not a new query pattern.

**Testing**: Frontend — Vitest + `@vue/test-utils` (repo convention; see `BarChart.spec.js`), run
via `docker compose exec vite pnpm test`. Backend — RSpec request specs following the fork's
existing convention (`custom/spec/requests/api/v1/accounts/*_controller_spec.rb`), run via
`docker compose exec rails bundle exec rspec`; no builder/controller spec exists yet for this
endpoint (a pre-existing gap, not introduced by this feature, but the natural place to add
coverage for the new `counts` field per Constitution's general expectation that RSpec/`bundle
exec rspec` gates the work — see Development Workflow & Quality Gates).

**Target Platform**: Web browser — Chatwoot dashboard (Reports module) for the chart; standard
Rails API server (already running) for the builder change.

**Project Type**: Web application — a frontend change (Vue component + one page integration)
plus a small backend change (one service method), both inside this fork's existing, isolated
`custom/` + `app/javascript` trees. No new top-level module.

**Performance Goals**: Funnel renders and re-renders (e.g. on value/quantity toggle or filter
change) without perceptible jank for the typical stage counts pipelines have (2–10 stages),
consistent with the other charts already on this report page. The backend addition reuses an
already-computed in-memory hash (`reached`), so it adds no additional database query.

**Constraints**: Tailwind utility classes only for layout/typography; per-stage `fill` color is
data-driven (arbitrary hex from `pipeline_stages.accent_color`) and therefore set via an SVG
presentation attribute bound to a prop — not a Tailwind class — mirroring the same unavoidable
exception `BarChart.vue`'s `backgroundColor` already takes for the identical reason (dynamic,
per-record color that can't be expressed as a static utility class). This is not a `style=""`
inline-style attribute and does not violate the "Tailwind only" rule's intent (no custom/scoped
CSS, no static-value inline styling). The backend change must stay inside `custom/app/services/reports/opportunity_funnel_builder.rb`
— no edits to `app/` or `enterprise/` — and must not alter `labels`, `count_data`, or `won_rate_pct`'s
existing values/meaning (additive key only).

**Scale/Scope**: One new frontend component (`shared/components/charts/FunnelChart.vue`) plus its
integration into one existing page (`OpportunityFunnelReport.vue`, replacing one `<BarChart>`
usage). One backend method (`conversion_funnel` in `Reports::OpportunityFunnelBuilder`) gains one
additive return key. No other chart, report section, controller, or route is touched.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First** — PASS. `FunnelChart.vue` is a net-new, additive file
  placed alongside its sibling chart components (`shared/components/charts/`), following the
  same location/prop-naming convention as `BarChart.vue`/`DonutChart.vue`/`LineChart.vue`. The
  frontend page touched (`OpportunityFunnelReport.vue`) and the backend method touched
  (`Reports::OpportunityFunnelBuilder#conversion_funnel`) both already live in this fork's
  isolated trees (`app/javascript/dashboard/routes/...`, `custom/app/services/reports/`) — the
  backend file in particular is *already* inside the fork's dedicated `custom/` overlay (the
  same isolation convention this principle requires, mirroring `enterprise/`), so editing it
  touches zero upstream Chatwoot code. The edit there is additive (one new hash key), not a
  restructure.
- **II. Smallest Production-Ready Change** — PASS. No new npm/gem dependency, no new query
  pattern (the backend change reuses the `reached` hash `conversion_funnel` already computes for
  `count_data`), no refactor of sibling charts, controllers, or unrelated report sections. Scope
  is exactly what FR-008 (added via `/speckit-clarify`) requires: one additive array field.
- **III. Adhere to Established Conventions** — PASS. Frontend: `<script setup>` Composition API,
  PascalCase component name, Tailwind-only layout styling, i18n via existing
  `OPPORTUNITY_FUNNEL_REPORTS.CHARTS.*` keys (English-only edits per `en.json`/`en.yml` rule),
  Vitest spec colocated under `shared/components/specs/`. The one dynamic-color SVG attribute is
  addressed explicitly in Technical Context above as consistent with existing precedent, not a
  deviation. Backend: follows `Reports::OpportunityFunnelBuilder`'s existing private-method style
  and the fork's RSpec request-spec convention for any new coverage.
- **IV. Safe, Reversible Change Management** — PASS. Purely additive/local change across three
  touched files (`FunnelChart.vue` new, `OpportunityFunnelReport.vue` edited,
  `opportunity_funnel_builder.rb` edited); reversible by reverting them.
- **V. Dual-Tree Awareness (OSS + Enterprise)** — PASS (N/A). No `enterprise/` counterpart exists
  for the Reports module, `OpportunityFunnelReport.vue`, `Reports::OpportunityFunnelBuilder`, or
  any funnel/chart component (confirmed by search of `enterprise/`); no enterprise decision to
  record. This whole feature (report page + its backend builder) is fork-specific (`custom/` +
  fork-only frontend route), outside the OSS/Enterprise dual-tree entirely.

No violations — Complexity Tracking table is not needed.

## Project Structure

### Documentation (this feature)

```text
specs/017-graphical-funnel-chart/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
app/javascript/
├── shared/components/
│   ├── charts/
│   │   ├── BarChart.vue          # existing — untouched
│   │   ├── DonutChart.vue        # existing — untouched
│   │   ├── LineChart.vue         # existing — untouched
│   │   └── FunnelChart.vue       # NEW — this feature
│   └── specs/
│       ├── BarChart.spec.js      # existing — reference convention
│       └── FunnelChart.spec.js   # NEW (optional, see tasks) — no spec task generated
│                                  # by default per constitution's "avoid writing specs
│                                  # unless explicitly asked"; add only if requested
└── dashboard/routes/dashboard/settings/reports/
    └── OpportunityFunnelReport.vue  # MODIFIED — swap <BarChart> for <FunnelChart>
                                      # in the Conversion Funnel section only

custom/
├── app/
│   ├── controllers/api/v1/accounts/
│   │   └── opportunity_funnel_reports_controller.rb  # existing — untouched (renders the
│   │                                                  # builder's hash as-is; new key flows
│   │                                                  # through automatically)
│   └── services/reports/
│       └── opportunity_funnel_builder.rb             # MODIFIED — conversion_funnel gains a
│                                                       # `counts` array (FR-008)
└── spec/requests/api/v1/accounts/
    └── opportunity_funnel_reports_controller_spec.rb  # NEW (optional, see tasks) — first
                                                          # coverage for this endpoint
```

**Structure Decision**: A frontend change within the existing `app/javascript` tree —
`FunnelChart.vue` added as a new sibling in `shared/components/charts/` (the established home for
reusable chart components), with its Vitest spec colocated in the sibling `specs/` directory per
repo convention, and a one-section edit to `OpportunityFunnelReport.vue` to consume it. Paired
with a one-method backend change inside the fork's existing `custom/` overlay
(`opportunity_funnel_builder.rb`) — no new controller, route, or policy needed, since the
existing controller already renders the builder's full hash and the existing route/policy are
unchanged. No `enterprise/` counterpart needed (see Constitution Check, Principle V).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
