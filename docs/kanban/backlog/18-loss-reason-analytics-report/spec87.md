# Phase 87: Loss-Reason Analytics

**Status**: placeholder — pending brainstorm session
**Depends on**: `custom/app/services/reports/opportunity_attribute_summary_builder.rb`;
`custom/app/services/custom/automation_rules/opportunity_conditions_filter_service.rb`;
`db/schema.rb` (`ichatr_opportunities.lost_reason`).

## Quick Preview

Identified during a market-landscape brainstorm (2026-09-04): reports have no breakdown of *why*
opportunities are lost. Investigation before writing this placeholder found the situation is
narrower than "no report exists" — it's that loss reason is tracked through two disconnected
paths today:

1. A native `lost_reason` string column on `Opportunity`. It's referenced by the activity-log
   listener and rendered as a `LOST_REASON` entry in `OpportunityActivityLog.vue`, but no
   strong-params allowlist or UI component that sets it was found in either backend or frontend —
   and no report reads it. Whatever populates it today, it is invisible in aggregate.
2. A `loss_reason` **custom attribute** key. `opportunity_conditions_filter_service.rb` reads
   `custom_attributes.dig('loss_reason')` first, falling back to the native column. If an account
   defines a custom attribute of type "list" for this, `Reports::OpportunityAttributeSummaryBuilder`
   *already* produces a full open/won/lost count+value breakdown per value — for the
   custom-attribute path, the "list-type attribute report" the operator asked about is likely
   already sufficient, and no new report is needed for that case.

So the real gap isn't a missing report — it's that the native-column path has zero capture UI and
zero reporting coverage, and the two paths aren't reconciled. This needs a data-model decision
before it needs a report.

Open questions for the brainstorm:
- Retire the native `lost_reason` column in favor of always driving loss reason as a custom
  attribute (so the existing generic report just works, no new report needed) — or keep the
  native column and give it its own dedicated report treatment?
- Is there in fact no UI today for capturing `lost_reason` — does closing this gap require adding
  a capture UI (e.g. a reason picker shown when marking an opportunity Lost) as well?
- Fixed set of reasons (dropdown) vs. free text — a fixed set is what makes aggregate reporting
  useful; free text would need its own grouping strategy.
