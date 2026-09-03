# Data Model: Ad Campaign Performance Report

## Entity: PipelineStage (existing — extended)

Table: `ichatr_pipeline_stages` (existing, fork-owned).

| Field | Type | Notes |
|---|---|---|
| `campaign_report_milestone` | `boolean`, default `false`, `null: false` | **New.** Marks this stage as the account's funnel milestone tracked by the Ad Campaign Performance report. |

**Invariant**: At most one `PipelineStage` per `account_id` may have `campaign_report_milestone:
true` at any time.

**Enforcement**: A `before_save` callback, mirroring the existing `requires_deal_value`
exclusivity pattern (`ensure_single_lane_exclusivity_for_deal_value`) already on this model:

- Trigger: `if: -> { campaign_report_milestone? && campaign_report_milestone_changed? }`
- Action: for every other `PipelineStage` in the same account, set `campaign_report_milestone:
  false`.
- This is app-level exclusivity (no DB unique index), consistent with how `requires_deal_value`
  already works on this exact model — no new enforcement pattern introduced.

**Relationship to report data**: Read-only from the report's perspective — the builder looks up
`account.pipeline_stages.find_by(campaign_report_milestone: true)` to find the current milestone,
if any. No foreign key elsewhere points at this stage for milestone purposes; deleting the
milestone-flagged stage simply removes the flag along with the stage row (no dangling reference to
clean up).

## Entity: Opportunity (existing — read-only for this feature)

Table: `ichatr_opportunities` (existing). No schema changes. Fields already present and used by
this report (via `Custom::Concerns::OpportunityCampaignAttribution`):

| Field | Used for |
|---|---|
| `campaign_source_id` | Presence test for "is this a paid-ad lead at all" (base scope filter). |
| `campaign_resolution_status` | Excludes `organic_post` / `not_applicable`; `pending` is included (renders as "Não identificado"). |
| `campaign_name` | Grouping key for the "by campaign" breakdown; `nil` groups as "Não identificado". |
| `campaign_adset_name` | Grouping key for the "by ad set" breakdown (combined with `campaign_name`). |
| `campaign_ad_name` | Grouping key for the "by ad" breakdown (combined with the two above). |
| `status` (enum: `open`/`won`/`lost`) | Won/Lost KPI counts and rates. |
| `created_at` | Date-range filter and cohort basis for milestone reach (same convention as `OpportunityFunnelBuilder`). |
| `pipeline_stage_id` / stage-change history | Indirect — milestone reach is computed from `OpportunityStageChange`, not this column directly. |

## Entity: OpportunityStageChange (existing — read-only for this feature)

Table: existing, unchanged. Already the basis for `OpportunityFunnelBuilder`'s "reached this stage"
computation (`account_id`, `opportunity_id`, `to_stage_id`, `changed_at`). This feature reuses it
through the shared `Reports::StageReachCalculator` (see research.md §1) rather than adding new
columns or a new table.

## Value object: Ad Campaign Performance Report response

Not a persisted entity — the JSON shape returned by
`Reports::CampaignPerformanceBuilder#build` and consumed by the frontend. Documented in full in
[contracts/campaign-performance-reports.md](./contracts/campaign-performance-reports.md).

```text
{
  summary: {
    leads, milestone_stage_name, milestone_count, milestone_rate_pct,
    won_count, won_rate_pct, lost_count, lost_rate_pct,
    distinct_campaigns, distinct_adsets, distinct_ads
  },
  by_campaign: [ { campaign_name, leads, won_count, lost_count, milestone_count?, milestone_rate_pct? }, ... ],
  by_adset:    [ { campaign_name, campaign_adset_name, leads, won_count, lost_count, milestone_count?, milestone_rate_pct? }, ... ],
  by_ad:       [ { campaign_name, campaign_adset_name, campaign_ad_name, leads, won_count, lost_count, milestone_count?, milestone_rate_pct? }, ... ]
}
```

`milestone_count`/`milestone_rate_pct` keys (both in `summary` and in every breakdown row) are only
present when a milestone stage is designated for the account — per FR-005/FR-011, the frontend must
not render a milestone card/column when they're absent, rather than treating a missing key as zero.

## State transitions

- **Milestone designation change**: `campaign_report_milestone: false → true` on stage A while
  stage B is currently `true` → B flips to `false` in the same `before_save` callback invocation
  that saves A. No intermediate state where two stages are simultaneously `true`.
- **Report data**: Stateless/computed-on-read. No caching, no background job, no stored snapshot —
  every request recomputes from current `Opportunity`/`OpportunityStageChange` rows for the
  requested date range, same convention as every other `Reports::*Builder` in this codebase.
