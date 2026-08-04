# Phase 0 Research: Opportunity Funnel Report

No `NEEDS CLARIFICATION` markers remain in the Technical Context — all
technical decisions follow directly from established patterns already in
this fork's `custom/` tree and the existing core Reports module. This
document records those decisions for traceability.

## Decision: `DonutChart.vue`/`LineChart.vue` — exact Chart.js v4 registration and defaults

**Verification performed**: confirmed `chart.js` is pinned to `~4.4.4` and
`vue-chartjs` to `5.3.1` in `package.json`; confirmed against the live
`chatwoot/chatwoot` `develop` branch (via `gh_grep`) that `BarChart.vue` is
still the **only** chart.js component upstream — no `DoughnutChart`/`LineChart`
wrapper exists anywhere in Chatwoot core to diverge from or copy; confirmed
exact v4/v5 registration requirements against the official `vue-chartjs`
v5.3.3 docs (Context7) and cross-checked against real-world `Doughnut`/`Line`
usages in other Vue 3 + chart.js v4 codebases (`gh_grep`, e.g.
`ChartJS.register(ArcElement, Tooltip, Legend)` for doughnut charts).

**Decision**:
- `DonutChart.vue` registers `ArcElement`, `Tooltip`, `Legend` and wraps
  vue-chartjs's typed `Doughnut` component. **`DoughnutController` is
  registered automatically by the typed `Doughnut` import itself** — it does
  *not* need (and must not get) an explicit `ChartJS.register(DoughnutController)`
  call. (Spec FR-008's "registers `ArcElement`/`DoughnutController`" describes
  the chart *capability* being added, not a literal 1:1 list of `register()`
  arguments — vue-chartjs v4+'s tree-shakable typed components register their
  own controller automatically; this is the one place the implementation
  necessarily departs from the spec's literal phrasing, and does so to match
  the actual, current vue-chartjs API rather than an older version's.)
- `LineChart.vue` registers `LineElement`, `PointElement`, `CategoryScale`,
  `LinearScale`, `Tooltip` and wraps the typed `Line` component (`LineController`
  auto-registered the same way). `CategoryScale`/`LinearScale`/`Tooltip` are
  already registered by `BarChart.vue` when both are mounted on the same
  page; chart.js's registry is idempotent (`ChartJS.register` keys by
  component id), so re-registering them in `LineChart.vue` is safe and keeps
  the component independently usable/testable without relying on load order.
- **Both wrappers keep `BarChart.vue`'s exact prop/structure pattern**
  (`collection`, `chartOptions`, `clickable`, `elementClick` emit,
  `handleClick`/`handleHover` cursor logic, same `fontFamily` constant) per
  FR-008 — but each defines its **own** `defaultChartOptions`, not a literal
  copy of `BarChart.vue`'s. `BarChart.vue`'s defaults include a cartesian
  `scales: { x, y }` block that is meaningless (and would be silently
  ignored, but is misleading dead config) for a doughnut chart, which has no
  axes. `DonutChart.vue`'s defaults instead set
  `plugins: { legend: { display: true, position: 'bottom' } }` — doughnut
  slices need a legend to identify categories (won/lost), unlike bar/line
  charts here which already label categories via the x-axis. `LineChart.vue`'s
  defaults keep the same `scales` shape as `BarChart.vue` (still a cartesian
  chart, x = day buckets, y = count) and, like `BarChart.vue`, does not
  register or need a legend.

  **Finding — `BarChart.vue`'s top-level `legend` key is dead config, not a
  real "hidden" precedent.** Cross-checked against Context7's `vue-chartjs`/
  chart.js docs: as of Chart.js v3+ (this fork pins v4.4.4), legend options
  live under the namespaced path `options.plugins.legend`, not a top-level
  `options.legend` key. `BarChart.vue`'s `defaultChartOptions.legend.display: false`
  (`app/javascript/shared/components/charts/BarChart.vue:38-43`) is therefore
  never read by chart.js at all — it is inert v2-era config left over in the
  upstream file, not something this feature should treat as "the pattern" for
  suppressing a legend. The actual reason `BarChart.vue`'s charts render with
  no legend is that its `ChartJS.register(...)` call
  (`BarChart.vue:30`) never includes `Legend` — chart.js v4's tree-shakable
  plugin system means an unregistered plugin simply never runs, regardless of
  what `options` says about it. Implication for this feature: `LineChart.vue`
  must follow the *real* mechanism, not the inert one — omit `Legend` from
  its own `ChartJS.register(...)` call (already the plan above; no
  `plugins.legend` key needed in its `defaultChartOptions` at all, though
  including `plugins: { legend: { display: false } }` defensively is
  harmless). `DonutChart.vue`, conversely, needs the legend to actually
  render, so it must both register `Legend` *and* place its config under the
  correct `plugins.legend` path — copying `BarChart.vue`'s top-level `legend`
  key into either new component would silently produce no legend control at
  all (relying entirely on chart.js's own default, which is `display: true`),
  not the intended behavior.
- Colors: this fork's existing chart configuration
  (`app/javascript/dashboard/routes/dashboard/settings/reports/constants.js`)
  hardcodes chart colors as literal hex/rgb strings
  (`DEFAULT_BAR_CHART.backgroundColor: 'rgb(31, 147, 255)'`,
  `DEFAULT_LINE_CHART.borderColor: '#779BBB'`) rather than referencing
  Tailwind/CSS-custom-property design tokens — chart.js canvas rendering
  cannot read Tailwind utility classes directly (canvas `fillStyle` needs a
  resolved color string), so this is the established, correct pattern to
  preserve look-and-feel, not a shortcut to fix. The new charts follow the
  same approach with colors chosen to match, not invent: `win_rate`'s two
  donut segments use the literal hex equivalents of the same design tokens
  `KanbanCard.vue` already uses for the `won`/`lost` status badges
  (`bg-n-teal-3 text-n-teal-11` for won, `bg-n-ruby-3 text-n-ruby-11` for
  lost — confirmed in `KanbanCard.vue`'s `statusBadgeClasses`), not an
  unrelated green/red pair — resolving the exact hex value for each token is
  a Phase 2 implementation detail (read from the generated Radix-color CSS
  custom properties at build time, or hold the resolved hex as a literal
  constant the same way `constants.js` already does for `DEFAULT_BAR_CHART`).
- **Per-stage bar coloring** (`conversion_funnel`, `pipeline_value_by_stage`,
  `avg_time_in_stage` — all keyed by pipeline stage): each stage's bar uses
  that stage's own `accent_color` (already a `matias_pipeline_stages` column,
  already rendered on the kanban board itself per Phase 15/`KanbanColumn.vue`'s
  `borderBottomColor: stage.accent_color`) as its `backgroundColor`, when
  present, falling back to the existing default bar color otherwise.
  `accent_color` is stored as a plain hex string (`db/migrate/20260804024740_add_total_display_mode_and_accent_color_to_matias_pipeline_stages.rb`,
  `t.string "accent_color"`) written via `EditPipelineStage.vue`'s
  `ColorPicker.vue` — unlike the won/lost design-token colors above, it is
  already a canvas-ready CSS color string with no hex-resolution step needed;
  the frontend can pass it straight through as `backgroundColor`. This is
  the strongest available lever for "the report should look like it belongs
  next to the kanban board it reports on" — the same per-stage color already
  means "this stage" to the user from the board itself. This is a rendering
  detail only; it changes no field in the API contract (`contracts/opportunity_funnel_report.md`
  already returns `labels` per stage in stage order — the frontend maps
  `label → stage → accent_color` using the already-loaded `pipelineStages`
  Vuex store, the same store the kanban board itself reads from, requiring
  no new API field).

**Alternatives considered**: Registering `chart.js/auto` (registers every
component) instead of explicit imports — rejected, contradicts `BarChart.vue`'s
existing tree-shakable pattern and vue-chartjs's own migration guidance.
Copying `BarChart.vue`'s `defaultChartOptions` object verbatim into both new
wrappers — rejected once verified against Chart.js's actual `DoughnutControllerChartOptions`
type (no `scales` key exists for doughnut) since it would ship dead/misleading
config. A generic, shared `defaultChartOptions` factory parameterized by
chart type — rejected as premature abstraction for two call sites (Principle
II); three near-identical small files (`Bar`/`Donut`/`Line`) is simpler than
one configurable one, and matches the "thin wrapper mirroring `BarChart.vue`"
framing in the spec itself.

## Decision: `closed_at` migration and callback location

**Decision**: An additive migration under `db/migrate/` adds a nullable
`closed_at` datetime column to the existing `matias_opportunities` table.
The `before_save` callback that sets/clears it lives directly on
`custom/app/models/opportunity.rb` (already a fork-owned file).

**Rationale**: `db/migrate/` is the one constitution-sanctioned exception to
"isolate everything in `custom/`" — this change is purely additive (new
nullable column on an already fork-owned table) and doesn't touch any
upstream table. `Opportunity` already carries stage-change and closing-
requirement callbacks in this same style (`validate_closing_requirements`,
`record_subsequent_stage_change`), so this is a consistent extension, not a
new pattern.

**Alternatives considered**: Deriving "closed" timing from the most recent
`OpportunityStageChange` row instead of a dedicated column — rejected
because stage changes only capture pipeline-stage movement, not status
(`won`/`lost`) transitions; an opportunity can be marked `lost` without a
stage change, so there is no reliable proxy for `closed_at` in the existing
transition log.

## Decision: Single builder service, placed under `custom/app/services/reports/`

**Decision**: `Reports::OpportunityFunnelBuilder` — one plain Ruby service
object (`pattr_initialize :account, :params` style, matching
`V2::Reports::Timeseries::BaseTimeseriesBuilder`), physically located at
`custom/app/services/reports/opportunity_funnel_builder.rb`.

**Rationale**: `custom/app/**` is already wired into `config/application.rb`
eager/autoload paths via a wildcard glob (`Dir["#{Rails.root}/custom/app/**"]`),
so a file placed there that reopens the existing core `Reports` module
resolves correctly under Zeitwerk without any additional wiring — the
"smallest possible edit to core config" bar is already met (zero new lines
needed). Physically isolating the file in `custom/` while nominally
participating in the core `Reports` namespace satisfies both "new
fork-specific features live in an isolated tree" (Personalization
Boundaries) and "reuse existing extension points over hard forks" (Principle
I) — no core file is edited or duplicated.

**Alternatives considered**: A generic, configurable builder mirroring
`Reports::DrilldownBuilder` — explicitly rejected per spec FR-005, since the
metric set is fixed by product decision, not user-configurable. Placing the
new file physically under `app/services/reports/` (core tree) — rejected
because it would interleave a fork-specific domain feature into upstream's
own directory, increasing future merge-conflict risk for no benefit (the
`custom/` glob already makes this unnecessary).

## Decision: New controller under `custom/app/controllers/api/v1/accounts/`, `Api::V1` namespace

**Decision**: `Api::V1::Accounts::OpportunityFunnelReportsController`,
alongside the other kanban/opportunity controllers already in that
directory (`OpportunitiesController`, `PipelineStagesController`, etc.).
One line added to `config/routes.rb` (`resources :opportunity_funnel_reports,
only: [:index]`) in the same account-scoped block as the sibling
`opportunities`/`pipeline_stages` routes.

**Rationale**: Matches this fork's already-established convention: every
kanban/CRM endpoint lives under `Api::V1::Accounts` in `custom/app/controllers`,
not `Api::V2` (which is reserved for core conversation reports). The single
`resources ... only: [:index]` line matches how every prior kanban route was
added (Phase 1) — the smallest possible core-file edit.

**Alternatives considered**: `Api::V2::Accounts::OpportunityFunnelReportsController`
alongside the core reports controller — rejected because it would place a
fork-specific domain controller inside the `Api::V2` core reports namespace
convention used by upstream, and it would break consistency with every
other kanban endpoint in this fork, which are all `V1`.

## Decision: Reuse core `ReportPolicy`/`report_manage` for authorization, not `OpportunityPolicy`

**Decision**: `check_authorization` in the new controller calls
`authorize(:report, :view?)`, the same unmodified core `ReportPolicy` (already
`prepend_mod_with`-wired for Enterprise) used by
`Api::V2::Accounts::ReportsController`. The controller also includes the
existing `Concerns::KanbanFeatureGuard` (403s if the account's `opportunities`
feature flag is off), matching every other kanban controller.

**Rationale**: This is a *report*, not opportunity CRUD — `OpportunityPolicy`
scopes access per-opportunity (assignee/conversation-based) for agents
working their own deals, which is the wrong shape for a pipeline-wide
aggregate report. `ReportPolicy#view?` (administrator-only) is what every
other report endpoint already uses, and reusing it costs zero new code
(no edit to the core policy file, just a call to it) while keeping the new
endpoint consistent with the rest of the Reports module's access model. The
frontend route's `meta.permissions: ['administrator', 'report_manage']`
(same as every sibling report route) mirrors this.

**Alternatives considered**: A new fork-specific `OpportunityFunnelReportPolicy`
— rejected as unnecessary indirection; the report has no fork-specific access
rule beyond "same as every other report," so introducing a new policy class
would violate Principle II (smallest production-ready change) for no gain.

## Decision: Frontend lives directly under `app/javascript/dashboard/` (no frontend `custom/` tree)

**Decision**: New page, store module, and API client are added as new files
directly inside the existing core `dashboard` tree
(`routes/dashboard/settings/reports/`, `store/modules/`, `api/`), following
the exact placement pattern of every sibling report page — not under any
isolated fork-specific directory.

**Rationale**: Unlike the Rails backend, there is no `custom/` equivalent
wired into the JS build for frontend code, and prior phases (1–14) already
established that fork-specific frontend features (the entire kanban board,
`KanbanCard.vue`, `KanbanBoard.vue`, pipeline settings pages) live directly
in `app/javascript/dashboard/`. Constitution Principle I's isolation
requirement is about not *editing* upstream file bodies to graft in
fork-specific behavior; adding wholly new files in the same directory as
their closest sibling (as every other report page already does) does not
edit any upstream file and carries the same low merge-conflict risk as
those prior phases' frontend additions.

**Alternatives considered**: A new top-level `custom/app/javascript` tree
mirroring the backend convention — rejected as unprecedented and
disproportionate: it would require new build/alias wiring not currently
present, for a benefit (isolation) that new-file-only additions already get
for free (new files don't conflict with upstream diffs the way edited files
do).

## Decision: Day-bucketing and since/until convention reused from `DateRangeHelper`

**Decision**: The new controller/service includes the existing
`DateRangeHelper` (`app/helpers/date_range_helper.rb`, core, unmodified) for
`since`/`until` unix-timestamp parsing, exactly as named in spec FR-003.
Day-bucketing for `new_opportunities_over_time` groups by `changed_at.to_date`
(Ruby `group_by`/SQL `date_trunc('day', ...)`), matching the "day" granularity
already used as the default in `V2::Reports::Timeseries::BaseTimeseriesBuilder`.

**Rationale**: Reuses an existing, unmodified core helper rather than
reimplementing date-range parsing — smallest production-ready change,
consistent with every other report endpoint's request contract.

**Alternatives considered**: Accepting ISO8601 date strings instead of unix
timestamps — rejected; spec FR-003 explicitly requires matching the existing
`Api::V2::Accounts::ReportsController` convention (unix timestamps).
