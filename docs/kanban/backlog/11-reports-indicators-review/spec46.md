# Phase 46: Review of Existing Opportunity Reports — Broken Indicators Audit

**Status**: placeholder — pending brainstorm session
**Depends on**: Phase 21 (Opportunity Funnel Report), Phase 22 (Graphical Funnel Chart), Phase 23 (Sales Forecast Widget), Phase 25 (Opportunity Attribute Report) — the full set of existing opportunity report surfaces this audit covers; Phase 39 (Hide Closed Opportunities by Default) as a plausible recent-change suspect worth re-checking.

## Quick Preview

Suspicion (not yet pinpointed) that some indicators across the existing Opportunities/CRM report
pages are showing incorrect or broken values. This phase is an **audit pass first** — identify
exactly which indicators are wrong and why — before any fix gets designed.

One concrete lead worth checking first: Phase 39 changed `Api::V1::Accounts::OpportunitiesController#index`
to default to `status: 'open'` when no status condition is present, but its "out of scope" section
asserts the report builders (`Reports::OpportunityFunnelBuilder`,
`Reports::OpportunityAttributeSummaryBuilder`) are unaffected because they query
`account.opportunities` directly with their own explicit status scopes, never through that
controller. That assumption should be re-verified against the current code rather than trusted
outright — it's exactly the kind of place a regression could hide.

Open questions for the brainstorm:
- Which specific indicators look wrong? Needs the user to point to concrete examples (a report
  page + metric + expected vs. observed value) to turn "I think something's broken" into
  actionable bugs — or a systematic pass diffing each report's numbers against manual DB counts.
- Full scope confirmation: does "existing reports" mean all four (funnel, graphical funnel chart,
  sales forecast widget, opportunity attribute report), or a narrower subset?
- Is this purely a bug-fix phase, or does it also cover cases where an indicator is *technically*
  correct but its definition/label is confusing enough to look "broken" (a clarity fix, not a
  logic fix)?
