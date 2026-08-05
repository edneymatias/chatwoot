# Phase 24: Opportunity Assignment Rules

**Status**: placeholder — pending brainstorm session
**Depends on**: Phase 1 (backend core — `Opportunity.assignee_id` already
exists), Phase 12 (opportunity-triggered automations, if auto-assignment
ends up expressed as an automation action rather than a built-in rule)

## Quick Preview

`Opportunity` already has `belongs_to :assignee, class_name: 'User',
optional: true`, and `assignee_id` is already a permitted param on both
create and update (`opportunities_controller.rb`). So this isn't a schema
gap — it's two separate product gaps on top of an already-supported
field:

1. **No assignment happens at creation time.** Opportunities today are
   created with `assignee_id: nil` regardless of path (manual creation,
   `create_opportunity` automation action, backfill). There's no rule
   deciding who gets it — not round-robin, not inherited from the origin
   conversation's assignee, not based on pipeline/stage/team.
2. **No UI to view-and-change it after creation.** `KanbanCard.vue`
   renders the assignee name/avatar read-only (no dropdown). The
   creation modal (`OpportunityCreateModal.vue`) has no assignee field
   at all. There's no way today for a user to assign or reassign an
   opportunity from the UI — only possible via direct API call.

Open questions for the brainstorm:
- What's the default assignment rule? Candidates: inherit
  `origin_conversation.assignee_id` when present (opportunity created
  from a conversation via automation), round-robin within a team, or
  leave unassigned by default and only support manual/UI assignment
  first (simplest, ships fastest, no rule engine needed).
- Does reassignment need permission checks (e.g., only admins/team
  leads can reassign, or any agent can self-assign/hand off)?
- Where does the UI live — kanban card dropdown only, or also the
  contact panel opportunities section (Phase 5) and a dedicated
  opportunity detail view?
- Should reassignment fire a notification to the new assignee (existing
  Chatwoot conversation-assignment notification pattern could be
  reused)?
- Is this in scope for Phase 12's automation actions too (e.g. an
  "assign opportunity" automation action), or purely a manual/rule-based
  feature for this phase, with automation-triggered assignment deferred?
