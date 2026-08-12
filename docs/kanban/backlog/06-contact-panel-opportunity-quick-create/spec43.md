# Phase 43: Create Opportunity Directly From the Open Conversation (Contact Panel)

**Depends on**: existing Contact Panel Opportunities section (`ContactOpportunities.vue`,
`ContactOpportunityCard.vue`); existing `OpportunityCreateModal.vue` (already supports
`originConversationId`, reused rather than rebuilt).

## Context

The Contact Panel's Opportunities section (`ContactOpportunities.vue`) lists a contact's
opportunities but has no entry point to create one from the conversation currently open — this
was missed when the section was originally built. Two gaps are addressed together because both
touch the same list:

1. No button to create an opportunity directly from the open conversation.
2. The list's ordering doesn't surface the opportunity tied to the current conversation (today:
   simple most-recent-to-oldest, unchanged from the raw backend order).

Only one opportunity is allowed per conversation, enforced today at both the DB level (unique
index on `origin_conversation_id` in `ichatr_opportunities`) and the model level
(`validate_origin_conversation_id_immutability` in `custom/app/models/opportunity.rb`, which makes
`origin_conversation_id` immutable once set). The new button must respect this constraint.

## Frontend — Button

- **FR-001**: Add a header row to `ContactOpportunities.vue` with an "Add opportunity" action,
  styled identically to the existing "add note" action in `ContactNotes.vue`
  (`Button variant="link" color="blue" size="sm" class="hover:no-underline"`) — a subtle,
  link-like action, not a prominent CTA.
- **FR-002**: The button is disabled when the currently open conversation
  (`useMapGetter('getSelectedChat')`, matched by `currentChat.id`, following the same pattern
  already used in `ContactConversations.vue`) already has a related opportunity — i.e.
  `opportunities.value.some(o => o.origin_conversation_id === currentChat.value.id)`. This mirrors
  the one-opportunity-per-conversation rule confirmed above.
- **FR-003**: Clicking the button opens `OpportunityCreateModal.vue` with
  `originConversationId={currentChat.id}` and a new `initialContact` prop set to the current
  contact (`{ id, name, email }`, matching the shape already returned by contact search).

## Frontend — Modal: locked contact when launched from a conversation

- **FR-004**: `OpportunityCreateModal.vue` gains an optional `initialContact` prop. When present:
  - `selectedContact` initializes to it.
  - The contact section renders as a read-only chip (existing selected-contact display) with no
    "Clear" button and no search input — the contact is fixed to the conversation's contact for
    this flow, since changing it would contradict the conversation-first entry point.
  - When absent (all other existing call sites — Kanban's per-column "+", the List view's "add
    opportunity" button), behavior is unchanged: search-and-select as today.

## Frontend — Ordering and highlight

- **FR-005**: In `ContactOpportunities.vue`, the list is derived from a computed that partitions
  the existing `cardsForContact` result into "the opportunity whose `origin_conversation_id`
  matches `currentChat.id`" (if any) and the rest, placing the match first and leaving the
  remaining opportunities in their existing (most-recent-to-oldest) order. No backend/getter
  changes — this is a client-side reorder of already-fetched data.
- **FR-006**: `ContactOpportunityCard.vue` accepts a new boolean prop (e.g.
  `isCurrentConversation`) that swaps its bottom divider border color to a distinguishing accent
  (e.g. `border-n-brand-solid-9`) instead of the default `border-n-slate-3`, applied only to the
  top card when it's the conversation match.

## Frontend — List updates immediately after creation

- **FR-007**: Today, `opportunities/create` (`app/javascript/dashboard/store/modules/
  opportunities/actions.js:136-173`) commits `ADD_OPPORTUNITY` and `PREPEND_ID_TO_STAGE`, but never
  updates `state.idsByContact` — a newly created opportunity doesn't appear in
  `cardsForContact` until a refetch. Add a `PREPEND_ID_TO_CONTACT` mutation (mirroring the existing
  `PREPEND_ID_TO_STAGE` pattern) and commit it in the `create` action using the created
  opportunity's `contact_id`, guarded to only touch `state.idsByContact[contactId]` when that
  contact's list has already been fetched (i.e. the key exists), avoiding creating a partial/wrong
  list for contacts never loaded into this view. This benefits every opportunity-creation entry
  point, not just this one, but is scoped in here because this phase is what surfaces the gap.
- **FR-008**: Once FR-007 lands, the reorder in FR-005 naturally places the freshly created
  opportunity at the top of the Contact Panel list (it matches `currentChat.id`) without any
  additional wiring.

## Out of scope

- Any change to the one-opportunity-per-conversation constraint itself (DB index, model
  validation) — this phase only surfaces/respects it in the UI.
- Allowing the contact to be changed after `initialContact` is set (FR-004) — the flow is
  conversation-first and the contact is fixed for its duration.
- Any change to Kanban or List view creation flows, or to `StartOpportunityConversationButton.vue`
  (the inverse flow: starting a conversation from an opportunity) — untouched.
- Persisting the reorder/highlight preference, or applying it to any other opportunities surface
  (Kanban, List view) — scoped to the Contact Panel section only.
