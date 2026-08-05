# Implementation Plan: Opportunity Attribute Report

**Branch**: `018-opportunity-attribute-report` | **Date**: 2026-08-05 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/018-opportunity-attribute-report/spec.md`

## Summary

Add a new standalone Reports page ("Oportunidades") where the manager picks one list-type
`opportunity_attribute` custom attribute and a date range, and sees a table with one row per
defined attribute value plus a synthetic "no value" row, each row aggregating: count/value of
currently-open opportunities carrying that value (not period-filtered), won/lost counts closed in
the period, and average time to close for won opportunities closed in the period. A new
`Api::V1::Accounts::OpportunityAttributeReportsController#index` delegates to a new
`Reports::OpportunityAttributeSummaryBuilder` service, both fork-owned additions under `custom/`,
mirroring the exact pattern already established by the Opportunity Funnel Report (015). The
frontend reuses `ReportHeader`, `ReportFilters` (last-7-days default, matching the clarified
auto-load behavior), `Table.vue`/tanstack (as used by `AssigneePerformanceTable.vue`), and
`components-next/select/Select.vue` for the attribute picker — no new shared components needed.

## Technical Context

**Language/Version**: Ruby 3.x (Rails 7.1), Vue 3 (Composition API, `<script setup>`)

**Primary Dependencies**: Rails/ActiveRecord, Pundit (`ReportPolicy`, unmodified), Vuex,
`@tanstack/vue-table` (already used by `AssigneePerformanceTable.vue`), existing
`ReportHeader.vue`/`ReportFilters.vue`/`Table.vue`/`Pagination.vue`/`components-next/select/Select.vue`

**Storage**: PostgreSQL — no schema changes; reads existing `matias_opportunities.custom_attributes`
(jsonb, Phase 1), `matias_opportunities.closed_at`/`status` (Phase 21), and core
`custom_attribute_definitions` (`attribute_model: opportunity_attribute`, `attribute_display_type:
list`, `attribute_values` jsonb array)

**Testing**: RSpec (`bundle exec rspec`) for the builder service's aggregation logic and the
controller's validation/authorization; no JS unit tests planned beyond existing lint/type checks
(per CLAUDE.md, specs are not written unless explicitly asked)

**Target Platform**: Existing Chatwoot web dashboard (Rails API + Vue SPA)

**Project Type**: Web application (Rails backend + Vue frontend); backend additions live in the
fork-owned `custom/` tree, frontend additions live directly in `app/javascript/dashboard/`
following every prior report page's placement (same convention as 015)

**Performance Goals**: N/A beyond existing report-page load expectations — one request, a small
number of grouped SQL aggregate queries per request (one query per metric group, filtered/grouped
by the jsonb attribute key), no N+1, matching the shape of `Reports::OpportunityFunnelBuilder`

**Constraints**: Must not touch upstream/core report files (`app/builders/v2/reports/**`,
`app/services/reports/data_source.rb`, `CustomAttributeDefinitionsController`, etc.) — only add new
files; reuse `ReportPolicy`/`DateRangeHelper`/the existing `custom_attribute_definitions` endpoint
unmodified; no migration needed since all underlying columns already exist

**Scale/Scope**: Single account's opportunity volume; row count is bounded by the selected
attribute's `attribute_values` length (small, human-curated list) plus one "no value" row — no
pagination needed

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Upstream Compatibility First**: PASS. No core file is edited. The new controller lives in
  `custom/app/controllers/api/v1/accounts/`, matching every sibling kanban controller (e.g.
  `opportunity_funnel_reports_controller.rb`). The new `Reports::OpportunityAttributeSummaryBuilder`
  service is physically isolated under `custom/app/services/reports/`, resolved by the existing
  `custom/app/**` eager-load glob with zero new wiring — it reopens the core `Reports` module
  nominally but edits no core file, mirroring `Reports::OpportunityFunnelBuilder`. `config/routes.rb`
  gets one new `resources :opportunity_attribute_reports, only: [:index]` line directly beside the
  existing `opportunity_funnel_reports` line. `ReportPolicy`, `DateRangeHelper`, and the existing
  `custom_attribute_definitions` endpoint (core) are consumed unmodified.
- **II. Smallest Production-Ready Change**: PASS. One service, one controller action, no migration
  (all needed columns/tables already exist from Phases 1 and 21), no new shared frontend
  components — the attribute picker reuses `components-next/select/Select.vue` and the table reuses
  `Table.vue`/`Pagination.vue` exactly as `AssigneePerformanceTable.vue` already does. No
  charts/export/backfill (explicitly out of scope per spec).
- **III. Adhere to Established Conventions**: PASS. `<script setup>` Composition API for the new
  page; i18n keys added to `en.json` only (backend adds no new user-facing strings); Tailwind-only
  styling reusing existing report page classes; GET-only read-only endpoint needs no strong params
  beyond permitting the three query params.
- **IV. Safe, Reversible Change Management**: PASS. No migration, no destructive operations, purely
  additive new files plus two single-line additions (`config/routes.rb`, `reports.routes.js`,
  `Sidebar.vue`).
- **V. Dual-Tree Awareness (OSS + Enterprise)**: PASS. `ReportPolicy` is already
  `prepend_mod_with`-wired for Enterprise; this feature calls it unmodified, so any
  Enterprise-specific report-access override automatically applies. No other OSS/Enterprise core
  surface is touched — the entire feature is either fork-owned (`custom/`) or new files in the
  existing dashboard frontend tree.

No violations — Complexity Tracking section not needed.

## Project Structure

### Documentation (this feature)

```text
specs/018-opportunity-attribute-report/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── opportunity_attribute_report.md   # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
custom/app/services/reports/
└── opportunity_attribute_summary_builder.rb          # new: Reports::OpportunityAttributeSummaryBuilder

custom/app/controllers/api/v1/accounts/
└── opportunity_attribute_reports_controller.rb        # new

config/routes.rb                                       # +1 line: opportunity_attribute_reports route

app/javascript/dashboard/api/
└── opportunityAttributeReports.js                     # new ApiClient subclass

app/javascript/dashboard/store/modules/
└── OpportunityAttributeReports.js                     # new Vuex module (get action, data/uiFlags getters)

app/javascript/dashboard/routes/dashboard/settings/reports/
├── OpportunityAttributeReport.vue                      # new page
├── components/OpportunityAttributeReportTable.vue       # new: tanstack table, mirrors AssigneePerformanceTable.vue
└── reports.routes.js                                   # +1 route entry ('opportunities')

app/javascript/dashboard/components-next/sidebar/
└── Sidebar.vue                                          # +1 nav entry under Reports ("Oportunidades")

app/javascript/dashboard/i18n/locale/en/
├── report.json                                          # new OPPORTUNITY_ATTRIBUTE_REPORTS keys
└── settings.json                                        # +1 SIDEBAR key

spec/  (only if explicitly requested — see CLAUDE.md)
├── custom/spec/services/reports/opportunity_attribute_summary_builder_spec.rb
└── custom/spec/requests/api/v1/accounts/opportunity_attribute_reports_controller_spec.rb
```

**Structure Decision**: Backend additions follow the exact convention established by the Opportunity
Funnel Report (015): new fork-specific logic lives entirely in `custom/app/**` as net-new files
(no core file edits, no migration needed here since all underlying columns already exist), and
`config/routes.rb` gets the smallest possible single-line addition beside the sibling
`opportunity_funnel_reports` route. `Reports::OpportunityAttributeSummaryBuilder` reopens the core
`Reports` Ruby namespace but is physically isolated in `custom/`, resolved by the existing autoload
glob with no new wiring. Frontend additions are all new files placed directly alongside their
nearest sibling in the existing `dashboard/routes/dashboard/settings/reports/` tree, reusing
`Table.vue`/`Pagination.vue`/`components-next/select/Select.vue` rather than introducing new shared
components. No `contracts/` artifact is needed beyond the one new endpoint's shape, documented in
`contracts/opportunity_attribute_report.md`.

## Complexity Tracking

*No constitution violations — section not applicable.*
