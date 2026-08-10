# Phase 36: Manual Opportunity Creation, and Starting a Conversation from an Opportunity

**Depends on**: Phase 8 (List View), whose view bar reserves a disabled "add opportunity" button
wired up by this phase; existing `OpportunityCreateModal.vue` (already used by Kanban's per-column
"+" button) and `ComposeConversation.vue` (already used by `ContactHeader.vue` to start
conversations from a contact's page), both reused rather than rebuilt.

## Context

Two related gaps, addressed together because the second directly follows from the first:

1. There is no general-purpose entry point for creating an opportunity that isn't tied to a
   specific Kanban column — `OpportunitiesViewBar.vue`'s "add opportunity" button exists but is
   disabled (see Phase 8, FR-005). `OpportunityCreateModal.vue` already supports everything a
   general entry point needs (title, contact search/select, stage select, assignee, required
   fields, deal value) — it only needs to be opened without a preset stage.
2. Opportunities created this way (or otherwise) may have no associated conversation
   (`origin_conversation_id: nil`). Today there is no way to start one from the opportunity itself
   — Kanban cards and list rows without a conversation are simply non-clickable/grayed-out dead
   ends, and `opportunity_update_params` doesn't even permit setting `origin_conversation_id`
   after creation.

These two actions are kept deliberately separate at the UX level (confirmed during brainstorm):
creating an opportunity and starting a conversation are two distinct actions, not one combined
flow with a "also start a conversation" checkbox. This also makes the second action generally
useful for any conversation-less opportunity, not just newly created ones.

## Backend

- **FR-001**: Add `origin_conversation_id` to `opportunity_update_params` in
  `Api::V1::Accounts::OpportunitiesController`, so it can be set after creation (previously only
  settable at `create` time).
- **FR-002**: Add a model validation on `Opportunity` so `origin_conversation_id` can only be set
  when it is currently `nil` — once an opportunity has a conversation linked, this field becomes
  immutable via update. This prevents accidental overwrite/unlink through the new update path.

## Frontend — Manual creation

- **FR-003**: Wire `OpportunitiesViewBar.vue`'s "add opportunity" button to open
  `OpportunityCreateModal.vue` with no `defaultStageId` (the modal already handles this: the stage
  select is required and starts empty when no default is passed).
- **FR-004**: No changes to `OpportunityCreateModal.vue` itself — contact selection stays
  search-only (no inline "create new contact" option), matching its existing behavior from the
  per-column "+" button flow.

## Frontend — Start conversation from an opportunity

- **FR-005**: Add a new component (e.g. `StartOpportunityConversationButton.vue`) that wraps the
  existing `ComposeConversation.vue` unmodified, presetting its `contactId` prop with the
  opportunity's contact. `ComposeConversation.vue` is not edited (it's shared, upstream-originated
  code also used by `ContactHeader.vue`).
- **FR-006**: Before opening the compose flow, the wrapper snapshots
  `contactConversations/getAllConversationsByContactId(contactId)`. It `watch`es that getter; when
  a new conversation appears (list grows), it takes the new entry and dispatches
  `opportunities/update` with `{ id: opportunity.id, originConversationId: newConversation.id }`
  (relying on FR-001/FR-002 on the backend).
- **FR-007**: Render this action as an icon button in `KanbanCard.vue`'s existing hover "Quick
  Actions Overlay", visible only when `!opportunity.origin_conversation_id`.
- **FR-008**: Render the same action on `OpportunityListRow` (from Phase 8), visible only when
  `!opportunity.origin_conversation_id`. This is a deliberate, scoped exception to Phase 8's "list
  is read-only, no quick-action buttons" — justified because it's the only way to resolve a
  conversation-less row, not a stage/status mutation.
- **FR-009**: Once linked, the card/row immediately reflects the normal (non-grayed, clickable)
  treatment — no page reload required, since `opportunities/update` merges the change into the
  shared `state.byId` map already used by both views.

## Out of scope

- Inline "create new contact" during manual opportunity creation (FR-004) — search-only for v1.
- Any combined "create opportunity + start conversation" flow — the two actions stay separate
  (confirmed during brainstorm).
- Un-linking or re-linking an opportunity's conversation once set (FR-002 makes this immutable via
  update) — not requested, and removing the guard would need its own design pass.
- A dedicated opportunity "detail view" for conversation-less opportunities — none exists today;
  this phase only adds the start-conversation action to the existing card/row surfaces.
