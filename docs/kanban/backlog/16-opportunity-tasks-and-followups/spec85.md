# Phase 85: Opportunity Tasks & Follow-up Reminders

**Status**: placeholder — pending brainstorm session
**Depends on**: `custom/app/models/opportunity.rb`; `custom/app/models/opportunity_activity.rb` (audit-trail pattern to mirror); `custom/app/models/custom/automation_rule.rb` (candidate new action to auto-create tasks); `app/javascript/dashboard/components-next/Opportunities/OpportunityConversationDrawer.vue` (candidate UI host).

## Quick Preview

Identified during a market-landscape brainstorm (2026-09-04) comparing the Kanban module against
leading CRMs (Pipedrive, HubSpot, Salesforce, Zoho): task/reminder management with a due date is
the single biggest gap versus the market. Right now nothing in the product tracks "follow up on
this lead by X" — a lead can go cold with no signal anywhere. For a WhatsApp-first clinic SDR flow
(currently a single SDR, operator's own words), this is the highest-priority addition: it directly
prevents lost business from forgotten follow-ups, more than any reporting or distribution feature
would.

Open questions for the brainstorm:
- Data model: a new `Custom::OpportunityTask`-style model (own table, `custom/` namespace,
  no core model changes) — confirm this over any alternative.
- Where does it live in the UI? A card badge for overdue/due-today, a dedicated tab in
  `OpportunityConversationDrawer.vue` next to conversation/history, a global "Minhas Tarefas" view
  across opportunities, or some combination?
- Does it integrate with the automation engine — e.g. a new action like
  `create_opportunity_task` that auto-schedules a follow-up when an opportunity enters a given
  stage?
- Reminder delivery: in-app indicator only, or reuse Chatwoot's existing push-notification
  infrastructure?
- One open task at a time per opportunity, or multiple concurrent tasks?
- Completion semantics — mark done, snooze, reschedule, and whether completed tasks feed the
  existing `OpportunityActivity` audit trail as an event type.
