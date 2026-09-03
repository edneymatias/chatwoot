# Phase 45: Consolidated Campaign Performance Reports Across the Opportunity Funnel

**Status**: superseded by `spec84.md` (same folder) — brainstormed and approved 2026-09-02. This
file's open questions are answered there; kept here only as the original placeholder record.
**Depends on**: Phase 21 (Opportunity Funnel Report, `docs/kanban/ciclo 4/07-opportunity-funnel-report/spec21.md`); Phase 26 (WhatsApp/Meta referral attribution) for the campaign attribution columns on `Opportunity` this report groups/filters by; Phase 44 (ad spend collection) for cost data this report may eventually join against for cost-normalized metrics.

## Quick Preview

Goal: a consolidated report showing how each ad campaign performs across the opportunity
funnel — leads generated, stage-by-stage conversion, win/loss rate, average deal value — grouped
by the campaign attribution data Phase 26 adds directly to `Opportunity` (fixed columns, not
`custom_attributes`, per that phase's design).

Distinct from Phase 44: that phase collects campaign **spend**; this phase reports on campaign
**funnel outcomes**. The two are complementary and will eventually be joined (e.g. cost-per-lead,
cost-per-win) but that join is explicitly not decided here — could land as part of this phase or
as a further one, to be settled during brainstorm.

Open questions for the brainstorm:
- Report placement: a new dedicated report page, or a campaign breakdown/filter added onto the
  existing Phase 21 funnel report (`Reports::OpportunityFunnelBuilder`)?
- Grouping dimension: top-level campaign only, or does it need ad-set/ad-level breakdown to match
  Phase 44's spend granularity?
- Does this need to wait on Phase 26 actually shipping (campaign attribution columns must exist
  and be populated) before there's any data to report on, or can it be designed/scaffolded ahead
  of that?
- Time range / filtering conventions — should follow the same date-range filter pattern already
  established by the existing report pages (Phase 21/22/23) for consistency.
