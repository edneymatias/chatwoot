# Phase 84: Ad Campaign Performance Report

**Status**: Design approved by the user on 2026-09-02 — ready for an implementation plan. Replaces
the placeholder in this same folder (`spec45.md`), whose open questions are now resolved below.

**Depends on**: Phase 21 (Opportunity Funnel Report, `docs/kanban/ciclo 4/07-opportunity-funnel-report/spec21.md`)
for the report-page pattern and the `OpportunityStageChange`-based "reached this stage" computation
this phase reuses. Phase 26 (Meta referral attribution) for the campaign attribution columns on
`Opportunity` this report groups/filters by, and `CampaignAttributionSetting` for the feature gate.
Not blocked on Phase 44 (ad spend) — no cost/spend join in this phase.

## Quick Preview

A new "Campanhas de Anúncios" report under the Reports menu, showing how paid-ad leads (Meta
CTWA/referral attribution) perform through the funnel: total leads, how many reached a
operator-designated milestone stage, how many were won/lost, and a breakdown table by
Campaign/Ad-set/Ad. Modeled on a reference dashboard (Meta-style ads performance screen) the user
provided, adapted to this fork's actual generic data model instead of hardcoding business-specific
concepts.

Two decisions worth calling out, both landed after investigation during brainstorming:

1. **No dependency on Scout.** The reference image's "Agendamentos"/"Desqualificados" concepts only
   exist today as `Scout#qualified_stage_id`/`unqualified_stage_id` — AI-agent config, not a funnel
   property. An account running the Kanban fully manually (no Scout) should still get this report.
   So: "Desqualificados" is dropped in favor of the funnel's actual generic outcome
   (`Opportunity#status: won/lost`, same as every other report in this codebase), and "Agendamentos"
   becomes a new, small, generic concept — a single operator-designated **milestone stage** on
   `PipelineStage` itself, independent of Scout.
2. **Reuses the funnel report's existing computation, not a new one.** `Reports::OpportunityFunnelBuilder#conversion_funnel`
   already computes "did this opportunity reach stage X (or later) within its lifetime," cohорted by
   `created_at`, via `OpportunityStageChange`. This phase reuses that exact mechanism for the
   milestone-stage KPI, instead of inventing a second convention.

## Part 1 — New generic milestone-stage flag on `PipelineStage`

New boolean column `campaign_report_milestone` (default `false`). Exclusivity follows the **exact
existing pattern** already in this model for `requires_deal_value`
(`custom/app/models/pipeline_stage.rb:16,54-58`) — a `before_save` callback that unsets the flag on
every other stage of the account, not a DB uniqueness validation/index. No new UX pattern
introduced:

```ruby
before_save :ensure_single_campaign_milestone_exclusivity, if: -> { campaign_report_milestone? && campaign_report_milestone_changed? }

private

def ensure_single_campaign_milestone_exclusivity
  account.pipeline_stages.where.not(id: id).each do |stage|
    stage.update!(campaign_report_milestone: false)
  end
end
```

Migration:

```ruby
class AddCampaignReportMilestoneToIchatrPipelineStages < ActiveRecord::Migration[7.1]
  def change
    add_column :ichatr_pipeline_stages, :campaign_report_milestone, :boolean, default: false, null: false
  end
end
```

### UI: stage management screen

`AddPipelineStage.vue`/`EditPipelineStage.vue` (same forms touched by Phase 18's UI hint, and by
Phase 09's required-fields UI) gain a new toggle — "Usar como marco no Relatório de Campanhas de
Anúncios" (`PIPELINE_STAGES_MGMT.FORM.CAMPAIGN_MILESTONE`, `en`/`pt_BR`) — a single checkbox per
stage, understood by the operator as exclusive (selecting it on one stage silently clears it from
whichever stage had it before, mirroring how `requires_deal_value`'s toggle already behaves in this
same screen — no new interaction pattern to learn).

## Part 2 — Backend: `Reports::CampaignPerformanceBuilder`

New service, `custom/app/services/reports/campaign_performance_builder.rb`, same construction
convention as `Reports::OpportunityFunnelBuilder` (`pattr_initialize [:account!, :range]`):

```ruby
class Reports::CampaignPerformanceBuilder
  pattr_initialize [:account!, :range]

  def build
    {
      summary: summary,
      by_campaign: grouped_rows(%i[campaign_name]),
      by_adset: grouped_rows(%i[campaign_name campaign_adset_name]),
      by_ad: grouped_rows(%i[campaign_name campaign_adset_name campaign_ad_name])
    }
  end

  private

  # Paid-ad leads only — excludes organic posts and non-attributed opportunities.
  # Includes 'pending' (not yet resolved by the async Meta lookup): still a real
  # paid lead, just not yet named — renders as "Não identificado" in the table,
  # same convention as the reference dashboard.
  def base_scope
    return @base_scope if defined?(@base_scope)

    scope = account.opportunities.where.not(campaign_source_id: [nil, ''])
                   .where.not(campaign_resolution_status: %w[organic_post not_applicable])
    @base_scope = range ? scope.where(created_at: range) : scope
  end

  def summary
    milestone = account.pipeline_stages.find_by(campaign_report_milestone: true)
    total = base_scope.count
    milestone_count = milestone ? reached_milestone_count(milestone) : 0

    {
      leads: total,
      milestone_stage_name: milestone&.name,
      milestone_count: milestone_count,
      milestone_rate_pct: rate_pct(milestone_count, total),
      won_count: base_scope.won.count,
      won_rate_pct: rate_pct(base_scope.won.count, total),
      lost_count: base_scope.lost.count,
      lost_rate_pct: rate_pct(base_scope.lost.count, total),
      distinct_campaigns: distinct_count(:campaign_name),
      distinct_adsets: distinct_count(:campaign_adset_name),
      distinct_ads: distinct_count(:campaign_ad_name)
    }
  end

  def reached_milestone_count(milestone)
    opp_ids = base_scope.pluck(:id)
    return 0 if opp_ids.empty?

    stages = account.pipeline_stages.order(:position).to_a
    stage_position_by_id = stages.index_by(&:id).transform_values(&:position)
    reached = OpportunityStageChange
              .where(account_id: account.id, opportunity_id: opp_ids)
              .pluck(:opportunity_id, :to_stage_id)
              .each_with_object(Hash.new(0)) { |(opp_id, stage_id), h| h[opp_id] = [h[opp_id], stage_position_by_id[stage_id] || 0].max }
    reached.count { |_id, max_pos| max_pos >= milestone.position }
  end

  def distinct_count(column)
    base_scope.where.not(column => nil).distinct.count(column)
  end

  def rate_pct(count, total)
    return 0.0 if total.zero?

    ((count.to_f / total) * 100).round(1)
  end

  def grouped_rows(group_columns)
    grouped = base_scope.group(*group_columns)
    counts = grouped.count
    won_counts = base_scope.won.group(*group_columns).count
    lost_counts = base_scope.lost.group(*group_columns).count
    milestone_by_key = milestone_counts_by_group(group_columns)

    counts.map do |key, leads|
      key_array = group_columns.size == 1 ? [key] : key
      row_for(group_columns, key_array, leads, won_counts[key] || 0, lost_counts[key] || 0, milestone_by_key[key] || 0)
    end.sort_by { |r| -r[:leads] }
  end

  # ... (milestone_counts_by_group / row_for: same OpportunityStageChange join as
  # reached_milestone_count, grouped by the same columns; row hash uses
  # "Não identificado" for any nil campaign_name/campaign_adset_name/campaign_ad_name)
end
```

`row_for`/`milestone_counts_by_group` are omitted above for brevity but follow the exact same
`OpportunityStageChange` join already shown in `reached_milestone_count`, just grouped by the
relevant columns instead of a flat count — the implementation plan will spell these out in full
alongside their specs.

### Controller & route

`custom/app/controllers/api/v1/accounts/campaign_performance_reports_controller.rb`, same shape as
`opportunity_funnel_reports_controller.rb`:

```ruby
class Api::V1::Accounts::CampaignPerformanceReportsController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard
  include DateRangeHelper

  before_action :check_authorization

  def index
    render json: Reports::CampaignPerformanceBuilder.new(account: Current.account, range: range).build
  end

  private

  def check_authorization
    authorize :report, :view?
  end
end
```

Route name `campaign_performance_reports`, registered in `reports.routes.js` next to
`opportunity_funnel_reports`, same `meta` shape.

## Part 3 — Feature gate

`Api::V1::Accounts::CampaignAttributionSettingsController#response_data` gains one more field,
reusing the exact `pending_count` query pattern already in that method:

```ruby
resolved_data_present: current_account.opportunities.where(campaign_resolution_status: 'resolved').exists?
```

Frontend: no store module exists yet for campaign attribution settings (today's settings screen
fetches it locally, component-scoped). New minimal Vuex module `campaignAttributionSettings`
(`get` action → `show`), dispatched once during dashboard bootstrap (same place account-wide
settings like `pipelineCurrencySetting`/`pipelineCardFieldConfigs` are fetched today) so it's
available to `Sidebar.vue`, not just the settings page. `Sidebar.vue` gains a computed
`showCampaignPerformanceReport = enabled && resolved_data_present`, gating the new "Campanhas de
Anúncios" entry (`SIDEBAR.REPORTS_CAMPAIGN_PERFORMANCE`) inside the existing Reports group — chosen
over "Campanhas" specifically to avoid colliding with the existing top-level Campaigns sidebar
group (outreach/broadcast campaigns, unrelated feature).

## Part 4 — Frontend report page

New `app/javascript/dashboard/routes/dashboard/settings/reports/CampaignPerformanceReport.vue`,
same structural pattern as `OpportunityFunnelReport.vue`: `ReportHeader` + `ReportFilters` (date
range only — `show-group-by="false" show-business-hours="false" show-entity-filter="false"`,
positioned at the top of the page, standard Chatwoot placement — **not** inline with the table, as
in the reference image).

Below the filter: a 7-card KPI grid (reusing whatever shared metric-card component the other report
pages already use for this look), each with a large number and a smaller descriptive line —
mirroring the reference image's own per-card pattern (number + small line below), which is also how
the rate figures fold into their parent card instead of getting their own separate card:

1. **Leads** — `summary.leads`; subtitle e.g. "no período"
2. **[milestone stage name, e.g. "Agendado"]** — `summary.milestone_count`; subtitle
   `"{milestone_rate_pct}% dos leads"`. Card omitted entirely if no stage is flagged
   (`milestone_stage_name` is `nil`) — the row becomes a 6-card grid in that case, no placeholder
   card shown for "no milestone configured".
3. **Ganhos** — `summary.won_count`; subtitle `"{won_rate_pct}% dos leads"`
4. **Perdidos** — `summary.lost_count`; subtitle `"{lost_rate_pct}% dos leads"`
5. **Campanhas** — `summary.distinct_campaigns`
6. **Conjuntos** — `summary.distinct_adsets`
7. **Criativos** — `summary.distinct_ads`

Below the cards: a tab switcher (Campanhas / Conjuntos / Criativos — same three tabs as the
reference image) over a single table component, columns `Leads`, `[milestone stage name]`, `Ganho`,
`Perdido`, `Taxa de [milestone stage name]` (sortable by Leads desc by default, matching the
reference). The milestone column (and its rate) is omitted from the table too when no stage is
flagged, same as the KPI card. Rows with a `null` grouping key render literally as "Não
identificado", matching the reference image's own convention for unresolved/pending records.

## Out of scope

- Ad spend / cost-per-lead joins (Phase 44 territory, explicitly deferred there).
- Any change to `Scout#qualified_stage_id`/`unqualified_stage_id` or `SystemPromptsService` — Scout
  keeps its own independent config; this phase doesn't touch it, doesn't migrate it to the new
  `campaign_report_milestone` flag, and doesn't require the two to ever agree. (A future phase could
  reconcile them — not decided here, no evidence yet it's worth the coupling.)
- Any per-campaign/adset/ad UI beyond this one report screen (e.g. editing a resolved campaign's
  name manually) — read-only report only.
- Any account-level setting to disable just the *report* while attribution capture stays on — the
  single existing `CampaignAttributionSetting.enabled` toggle covers both.
- Real-time refresh/polling — same convention as every other report page (load on date-range
  change, no live updates).
- Historical backfill semantics beyond what already applies to `Opportunity#created_at` — no special
  handling for opportunities created before campaign attribution shipped (they simply won't match
  `base_scope`, having no `campaign_source_id`).

## Acceptance criteria

- With `CampaignAttributionSetting.enabled: false`, or `enabled: true` but zero opportunities with
  `campaign_resolution_status: 'resolved'`, the "Campanhas de Anúncios" entry does not appear under
  Reports.
- With the toggle enabled and at least one resolved opportunity, the entry appears and the page
  loads with the standard Chatwoot date-range filter at the top (not inline with the table).
- With no stage flagged `campaign_report_milestone`, the report shows 6 KPI cards (no milestone
  card) and the table has no milestone/rate columns — no error, no broken layout.
- With exactly one stage flagged, its name appears as the 2nd KPI card and as a table column;
  flagging a different stage un-flags the previous one (same UX as `requires_deal_value` today).
- Leads/Ganhos/Perdidos/milestone counts only include opportunities with real paid-ad attribution
  (`campaign_source_id` present, not `organic_post`/`not_applicable`) created within the selected
  date range.
- Rows with unresolved (`pending`) or missing campaign/adset/ad names render as "Não identificado"
  in the table, and still count toward Leads/Ganhos/Perdidos/milestone totals — just not toward the
  distinct campaign/adset/ad counts.
- Switching between the Campanhas/Conjuntos/Criativos tabs re-groups the same underlying data at
  the right hierarchy level, without re-fetching from the server (all three groupings are returned
  together by one API call).
- Changing the date range re-fetches and updates every KPI and the table.
- Full spec/lint suite (RuboCop, ESLint, RSpec, Jest) passes, including new specs for
  `Reports::CampaignPerformanceBuilder` (milestone reuse of the funnel report's stage-reached logic,
  won/lost counts, "Não identificado" grouping, distinct counts) and the
  `campaign_report_milestone` exclusivity behavior on `PipelineStage`.
