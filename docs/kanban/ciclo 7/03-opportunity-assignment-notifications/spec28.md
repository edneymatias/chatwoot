# Phase 28: Opportunity Assignment Notifications

**Status**: placeholder — pending brainstorm session
**Depends on**: Phase 24 (Opportunity Assignment Rules — ships the
assignee field on the `create_opportunity` automation action and on the
opportunity create/edit modals; this phase notifies on top of those flows)

## Quick Preview

Phase 24 deliberately ships assignment/reassignment (automation-configured
or manual, via `OpportunityCreateModal.vue`/`OpportunityBackfillModal.vue`)
with **no notification** to the new assignee — that was explicitly
deferred here. Chatwoot already has an established notification pattern
for conversation assignment that this phase would extend/mirror for
opportunities.

Open questions for the brainstorm:
- Reuse the existing conversation-assignment notification pipeline
  (`Notification`/`NotificationBuilder` or equivalent) as-is with an
  opportunity-specific notification type, or does opportunity assignment
  need its own delivery path?
- Which assignment paths trigger a notification — automation-driven
  (`create_opportunity` with an assignee configured), manual reassignment
  via the edit modal, both?
- Does reassigning away from an agent (unassigning, or handing off to
  someone else) need a notification too, or only "you were assigned"?
- In-app notification only, or does this also plug into existing
  email/push notification channels for conversation assignment?
