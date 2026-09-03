# Research: Ad Campaign Performance Report

All decisions below were resolved by reading the existing codebase, since the source design
document (`docs/kanban/ciclo 11/08-campaign-performance-funnel-reports/spec84.md`) already carries
an approved design; this phase's job was to verify that design against current code and resolve
the few places where the doc's assumptions didn't quite match what's actually there.

## 1. Shared "reached stage X" computation

**Decision**: Extract the `OpportunityStageChange` pluck-and-reduce join (opportunity → max stage
position reached) into a small shared helper, `Reports::StageReachCalculator`, and have both
`Reports::OpportunityFunnelBuilder` and the new `Reports::CampaignPerformanceBuilder` call it.

**Rationale**: `spec84.md` states the new builder "reuses that exact mechanism" from
`Reports::OpportunityFunnelBuilder#conversion_funnel`, but its own sample code
(`reached_milestone_count`, and the omitted `milestone_counts_by_group`) re-implements the same
`stage_position_by_id` + `pluck(:opportunity_id, :to_stage_id)` + `each_with_object(Hash.new(0))`
join independently — a real ~15-line block, not "three similar lines." Reading
`custom/app/services/reports/opportunity_funnel_builder.rb:36-47`
(`max_stage_positions_reached`) confirms this is the exact same computation already implemented
there. Duplicating it a third time (summary count + per-group count) would mean three independent
copies of account-scoped stage-position logic to keep in sync. Extracting one small class that
takes `(account:, opportunity_ids:, stages:)` and returns `{opportunity_id => max_position_reached}`
removes that duplication without inventing a new architectural layer — it's the same computation,
named once.

**Alternatives considered**:
- *Duplicate as shown in spec84.md*: Rejected — three copies of the same join is real duplication,
  not the "three similar lines" Constitution II protects; a bug fix or index-usage optimization
  would need to land in three places.
- *Have `CampaignPerformanceBuilder` call `OpportunityFunnelBuilder` directly and reuse its
  private methods*: Rejected — `OpportunityFunnelBuilder` computes over *all* of an account's
  period-created opportunities, while the campaign report needs the same computation scoped to a
  *subset* (paid-ad-attributed only, grouped by campaign/ad-set/ad). Coupling one builder's
  private internals to another's differently-scoped opportunity set is more fragile than a small
  shared, explicitly-scoped helper.

## 2. Where to dispatch the campaign attribution gating fetch

**Decision**: Dispatch the new `campaignAttributionSettings/get` action from
`app/javascript/dashboard/components-next/sidebar/Sidebar.vue`, in the same `onMounted` block that
already dispatches `labels/get`, `inboxes/get`, `teams/get`, `attributes/get`, and
`customViews/get` (lines 256-262).

**Rationale**: `spec84.md` says to dispatch this "same place account-wide settings like
`pipelineCurrencySetting`/`pipelineCardFieldConfigs` are fetched today," but grepping the frontend
shows those two are actually fetched **component-scoped**, on-mount, independently by every report
page and settings page that needs them (`OpportunityFunnelReport.vue`, `CardFieldConfig.vue`,
`opportunities/Index.vue`, etc.) — there is no single bootstrap dispatch for them. `Sidebar.vue`
*is*, however, already the real account-wide bootstrap location for the specific purpose this
feature needs: gating a sidebar nav entry on account-wide state, exactly like `labels/get` and
`inboxes/get` already do for their own sidebar sections. So the correct analogue isn't
`pipelineCurrencySetting`, it's the pattern `Sidebar.vue` already uses for its own gating data.

**Alternatives considered**:
- *Follow spec84.md literally and look for a shared "dashboard bootstrap" dispatch point*:
  Rejected — no such single bootstrap point exists for account-wide settings in this codebase;
  inventing one would be new architecture this feature doesn't need.
- *Fetch component-scoped inside the new report page only*: Rejected — the sidebar entry itself
  needs `resolved_data_present`/`enabled` to decide whether to render at all, before the report
  page ever mounts. A component-scoped fetch on the report page can't gate the nav entry that
  links to it.

## 3. Migration filename/timestamp

**Decision**: `db/migrate/21260903000000_add_campaign_report_milestone_to_ichatr_pipeline_stages.rb`,
using `ActiveRecord::Migration[7.1]` (matching every migration added to this table so far, e.g.
`db/migrate/21260814132145_add_description_to_ichatr_pipeline_stages.rb`), even though the
`Gemfile` currently pins `rails` to `7.2.3.1` — this fork's existing migration files consistently
target `[7.1]` regardless of the installed Rails version, and Constitution III requires following
established conventions rather than "fixing" this inconsistency incidentally.

**Rationale**: The latest existing migration in this repo is timestamped `21260902000000`; the new
one must sort after it. `add_column ... default: false, null: false` on a table with existing rows
is a standard additive, reversible migration — no `up`/`down` split or backfill needed since the
default satisfies `null: false` for existing rows.

## 4. Enterprise overlay check

**Decision**: No `enterprise/` changes needed.

**Rationale**: Searched `enterprise/` for any override of `PipelineStage`, `Opportunity`, or the
report authorization path. The only relevant enterprise files are `report_policy.rb` in both
`app/policies/` and `enterprise/app/policies/enterprise/`, which already govern the sibling
`opportunity_funnel_reports_controller.rb`'s identical `authorize :report, :view?` call — the new
`campaign_performance_reports_controller.rb` will be covered the same way with zero Enterprise-side
change, exactly matching Constitution V's requirement to check both trees before calling a change
complete.

## 5. Frontend component reuse inventory

**Decision**: Reuse `ReportHeader.vue`, `ReportFilters.vue` (date-range only —
`show-group-by="false" show-business-hours="false" show-entity-filter="false"`, matching
`spec84.md`), and `ReportMetricCard.vue` verbatim from
`app/javascript/dashboard/routes/dashboard/settings/reports/components/`. Build one new
`CampaignPerformanceTable.vue` for the tab-switched breakdown table (no existing table component
matches its 3-tab, milestone-column-conditional shape).

**Rationale**: Confirmed via `OpportunityFunnelReport.vue` that these three components already form
the standard report-page skeleton (filters at top, `ReportMetricCard` grid below) used across this
codebase's report pages — no new shared components needed for the KPI section.
