# Implementation Plan: Ad Campaign Performance Report

**Branch**: `044-campaign-performance-report` | **Date**: 2026-09-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/044-campaign-performance-report/spec.md`

## Summary

Add a new "Campanhas de Anúncios" report that summarizes how paid-ad-attributed opportunities
move through the funnel (leads, an operator-designated milestone-stage reach rate, won/lost), with
a Campaign / Ad set / Ad breakdown table — gated behind ad campaign attribution being enabled and
at least one resolved attribution. Backend: a new `campaign_report_milestone` boolean on
`PipelineStage` (exclusive per account, same pattern as `requires_deal_value`), a new
`Reports::CampaignPerformanceBuilder` service reusing the existing funnel report's
"reached-stage-X" `OpportunityStageChange` computation via a small shared helper (to avoid
duplicating that join three times), a new report controller/route, and one new field on the
existing campaign attribution settings response. Frontend: a new report page following the
`OpportunityFunnelReport.vue` structural pattern, a new lightweight Vuex module for campaign
attribution settings (dispatched from `Sidebar.vue`, where every other account-wide gating fetch
already lives), a new sidebar entry, and a milestone toggle added to the existing pipeline-stage
add/edit forms.

## Technical Context

**Language/Version**: Ruby 7.2.3.1 (Rails); migrations authored against `ActiveRecord::Migration[7.1]`
per the existing `db/migrate/` convention in this fork. JavaScript (ES2022+), Vue 3.4 Composition
API with `<script setup>`.

**Primary Dependencies**: Rails (`custom/` fork-tree service+controller convention), `attr_extras`
(`pattr_initialize`, already used by every `Reports::*Builder`), Pundit (`ReportPolicy`, already
governs `opportunity_funnel_reports`), Vuex 4, vue-i18n, Tailwind CSS. No chart library needed —
this report is KPI cards + a table only.

**Storage**: PostgreSQL. New column on `ichatr_pipeline_stages`; reads existing
`ichatr_opportunities` (campaign attribution columns) and `ichatr_opportunity_stage_changes`. No
new tables.

**Testing**: RSpec (`docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec
custom/spec/...`), Vitest via `docker compose exec vite pnpm test`.

**Target Platform**: Existing Chatwoot dashboard (Rails API + Vue 3 SPA), containerized dev stack
per `CLAUDE.md`.

**Project Type**: Web (single-repo Rails + Vue monolith). Fork-specific backend code is isolated
under `custom/`; frontend lives in the existing `app/javascript/dashboard/` tree alongside the
other Kanban/Opportunities report pages.

**Performance Goals**: No new target. Matches the existing, unstated-but-accepted envelope of
`Reports::OpportunityFunnelBuilder` — in-Ruby aggregation over one account's date-range-scoped
opportunities and their stage-change history, computed fresh per request with no caching.

**Constraints**: Constitution I (fork-specific logic isolated in `custom/`, `ichatr_`-prefixed
table, minimal-line wiring into `config/routes.rb`), III (RuboCop, ESLint Airbnb+Vue3, Tailwind
utilities only, Composition API, bilingual en/pt_BR i18n for every new user-facing string), V
(verified no Enterprise override exists for `PipelineStage`, `Opportunity`, or `ReportPolicy` —
`enterprise/app/policies/enterprise/report_policy.rb` already governs the sibling
`opportunity_funnel_reports` route identically, so no new Enterprise wiring is needed here).

**Scale/Scope**: 1 additive migration, 1 model callback, 1 small shared stage-reach helper + 1 new
report-builder service, 1 new controller + 2 route registrations (mirrors the existing duplicated
API-version blocks in `config/routes.rb`), 1 field added to an existing controller response, 1 new
Vuex module + 1 new API client, 1 new report page reusing existing shared report components, 2
edited pipeline-stage form components, 1 sidebar entry, i18n additions across `settings.json` and
`opportunities.json` (en + pt_BR).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Upstream Compatibility First | PASS | New backend code lives entirely in `custom/app/{models,services,controllers}`; the new column is on the fork-owned, `ichatr_`-prefixed `pipeline_stages` table (additive, reversible). Core-file edits are limited to the smallest possible wiring: 2 lines in `config/routes.rb` (mirroring the existing pattern), 1 field in an existing fork controller's response hash, and a sidebar entry — no upstream file is restructured. |
| II. Smallest Production-Ready Change | PASS (with one design decision) | Reuses the funnel report's stage-reach mechanism rather than inventing a second one. `spec84.md`'s sample code duplicates the `OpportunityStageChange` pluck+reduce join 3 times across the two builders; Phase 0 research resolves this by extracting one small shared helper instead of copy-pasting a third time — a targeted exception to "duplication over abstraction" because the duplication here is a real ~15-line join, not "three similar lines." See research.md. |
| III. Adhere to Established Conventions | PASS | Service uses `pattr_initialize`; controller mirrors `opportunity_funnel_reports_controller.rb` exactly; Vue page reuses `ReportHeader`/`ReportFilters`/`ReportMetricCard`; toggle UI mirrors `requires_deal_value` in `AddPipelineStage.vue`/`EditPipelineStage.vue`; new strings added to both `en` and `pt_BR` locale files. |
| IV. Safe, Reversible Change Management | PASS | Migration is a single additive `add_column` with a default, fully reversible; no destructive operations anywhere in scope. |
| V. Dual-Tree Awareness (OSS + Enterprise) | PASS | Confirmed no `enterprise/` override exists for `PipelineStage`, `Opportunity`, or the report authorization path — `report_policy.rb` / `enterprise/app/policies/enterprise/report_policy.rb` already apply unmodified to the sibling `opportunity_funnel_reports` route, and will apply the same way to the new route without any Enterprise-side change. |

**Post-design re-check** (after Phase 0/1 artifacts below): unchanged — all five gates still PASS.
research.md's decisions (shared `StageReachCalculator`, `Sidebar.vue` dispatch site, no Enterprise
change) were folded into the table above rather than discovered afterward as a surprise, so no gate
flipped.

## Project Structure

### Documentation (this feature)

```text
specs/044-campaign-performance-report/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── campaign-performance-reports.md   # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
# Backend — fork-owned tree (custom/), plus minimal wiring in shared config files
custom/app/models/pipeline_stage.rb                                              # edit: new column + exclusivity callback
db/migrate/<timestamp>_add_campaign_report_milestone_to_ichatr_pipeline_stages.rb # new migration
custom/app/services/reports/stage_reach_calculator.rb                            # new: shared "reached stage X" helper (see research.md)
custom/app/services/reports/opportunity_funnel_builder.rb                        # edit: delegate to the shared helper
custom/app/services/reports/campaign_performance_builder.rb                      # new
custom/app/controllers/api/v1/accounts/campaign_performance_reports_controller.rb # new
custom/app/controllers/api/v1/accounts/campaign_attribution_settings_controller.rb # edit: add resolved_data_present field
custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb              # edit: permit :campaign_report_milestone
config/routes.rb                                                                  # edit: register campaign_performance_reports (2 API-version blocks, mirrors opportunity_funnel_reports)

custom/spec/models/pipeline_stage_spec.rb                                         # edit: milestone exclusivity coverage
custom/spec/services/reports/campaign_performance_builder_spec.rb                 # new
custom/spec/requests/api/v1/accounts/campaign_performance_reports_controller_spec.rb # new
custom/spec/controllers/api/v1/accounts/campaign_attribution_settings_controller_spec.rb # edit: resolved_data_present coverage
spec/requests/api/v1/accounts/pipeline_stages_controller_spec.rb                  # edit: campaign_report_milestone param coverage (core spec tree, no custom/ prefix)

# Frontend — existing dashboard tree
app/javascript/dashboard/api/campaignPerformanceReports.js                        # new
app/javascript/dashboard/store/modules/CampaignPerformanceReports.js              # new
app/javascript/dashboard/store/modules/CampaignAttributionSettings.js             # new
app/javascript/dashboard/store/mutation-types.js                                  # edit: add new mutation type constants
app/javascript/dashboard/store/index.js (or module registry equivalent)           # edit: register the 2 new modules
app/javascript/dashboard/routes/dashboard/settings/reports/CampaignPerformanceReport.vue # new
app/javascript/dashboard/routes/dashboard/settings/reports/components/CampaignPerformanceTable.vue # new
app/javascript/dashboard/routes/dashboard/settings/reports/reports.routes.js      # edit: register route
app/javascript/dashboard/routes/dashboard/settings/pipelineStages/AddPipelineStage.vue  # edit: milestone toggle
app/javascript/dashboard/routes/dashboard/settings/pipelineStages/EditPipelineStage.vue # edit: milestone toggle
app/javascript/dashboard/components-next/sidebar/Sidebar.vue                      # edit: dispatch settings fetch + gated nav entry
app/javascript/dashboard/i18n/locale/en/settings.json                             # edit: SIDEBAR.REPORTS_CAMPAIGN_PERFORMANCE + report page strings
app/javascript/dashboard/i18n/locale/pt_BR/settings.json                          # edit: same, pt-BR
app/javascript/dashboard/i18n/locale/en/opportunities.json                        # edit: PIPELINE_STAGES_MGMT.FORM.CAMPAIGN_MILESTONE
app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json                     # edit: same, pt-BR
```

**Structure Decision**: No new top-level directories. This is an additive slice through the
existing fork-owned backend tree (`custom/app/**`, mirroring `Reports::OpportunityFunnelBuilder`
and `opportunity_funnel_reports_controller.rb` exactly) and the existing frontend `dashboard/`
tree (mirroring `OpportunityFunnelReport.vue` and the `OpportunityFunnelReports` Vuex module
exactly), consistent with Constitution I's isolation requirement and III's convention requirement.

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified

No unjustified violations. The one deviation worth naming (extracting `StageReachCalculator`
instead of leaving the join duplicated per `spec84.md`'s sample code) is captured as a research
decision in research.md, not a constitution violation — it *reduces* duplication rather than
adding abstraction for a hypothetical future need, so Principle II is satisfied either way; the
table below is left empty because no gate actually failed.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
