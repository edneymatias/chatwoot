# Phase 0 Research: Contact Panel Opportunity Quick Create

No `[NEEDS CLARIFICATION]` markers remain in the spec (one clarification was resolved during
`/speckit-clarify`: the creation flow closes automatically, discarding in-progress input, when the
agent switches conversations). This document records the implementation-pattern decisions found by
reading the existing codebase, so Phase 1 design and `/speckit-tasks` don't have to re-derive them.

## Decision: Current-conversation source of truth

**Decision**: Use `useMapGetter('getSelectedChat')` inside `ContactOpportunities.vue` to obtain the
currently open conversation — no new prop needed.

**Rationale**: `ContactOpportunities.vue` is only ever rendered inside the open conversation's
Contact Panel (`ContactPanel.vue:338`, passed only `:contact-id="contact.id"`, no conversation id).
The sibling component `ContactConversations.vue` already uses this exact getter
(`const currentChat = useMapGetter('getSelectedChat');`) for the same purpose (matching
`currentChat.id === conversation.id`). Reusing the identical pattern keeps the two Contact Panel
sections consistent.

**Alternatives considered**: Adding a `conversationId` prop threaded from `ContactPanel.vue` (like
`ContactConversations.vue` receives) — rejected as unnecessary plumbing; the getter is simpler and
already the established pattern for "is this the current conversation" checks in this exact
directory.

## Decision: Button placement and styling

**Decision**: Add a small header row above the opportunity list in `ContactOpportunities.vue`
using the existing `Button` component (`dashboard/components-next/button/Button.vue`) with
`variant="link" color="blue" size="sm" class="hover:no-underline"`.

**Rationale**: This exact prop combination is already used for a lightweight contact-panel action
in `components-next/Contacts/ContactsSidebar/ContactNotes.vue:67-76`, confirming it's the
established "subtle, link-like action" pattern for this kind of secondary CTA (as opposed to the
`ghost`/`xs`+icon pattern used by the unrelated `routes/dashboard/conversation/contact/
ContactNotes.vue`, which is a different component in a different flow).

**Alternatives considered**: The `ghost`/`xs` icon-button pattern from `routes/dashboard/
conversation/contact/ContactNotes.vue` — rejected because the spec explicitly calls for parity
with the `link`/`blue` styling, and that pattern is reserved for icon-first quick actions
elsewhere, not text-first section actions.

## Decision: Locking the contact in `OpportunityCreateModal.vue`

**Decision**: Add an `initialContact` prop (`{ id, name, email }` shape, `default: null`).
Initialize `selectedContact` from it. In the template, keep the existing read-only chip markup but
make the "Clear" button conditional on `!initialContact`, and never render the search input when
`initialContact` is set (already implied since `selectedContact` will always be truthy in that
case — the existing `v-else` branch naturally never renders).

**Rationale**: `selectedContact` already renders as a chip identical to what FR-004 requires
(`OpportunityCreateModal.vue:176-191`); the only gap is the unconditional "Clear" button. This is
the minimal-diff way to satisfy "read-only chip, no Clear button, no search input" without
introducing a second contact-display code path.

**Alternatives considered**: A separate `LockedContactChip` sub-component — rejected as
over-engineering for a two-line template conditional (Constitution II: smallest production-ready
change).

## Decision: List reorder/highlight

**Decision**: In `ContactOpportunities.vue`, derive a computed from `cardsForContact(contactId)`
that partitions on `o.origin_conversation_id === currentChat.value.id`, placing at most one match
first and leaving the rest in existing order (client-side only, no getter/backend change). Pass a
new `isCurrentConversation` boolean prop to `ContactOpportunityCard.vue`, applied only to the first
card when it's the match, swapping `border-b-n-slate-3` (line 67 today) for the existing accent
color token `border-n-brand`.

**Rationale**: Matches FR-005/FR-006 exactly; `cardsForContact` already returns the full,
already-fetched list, so no additional store/getter changes are needed — this is purely a
presentation-layer reorder.

**Alternatives considered**: Sorting in the `cardsForContact` getter itself — rejected because that
getter is shared by other potential future consumers and has no concept of "current conversation";
keeping the reorder local to `ContactOpportunities.vue` avoids leaking a UI-only concern into
shared store code.

## Decision: Immediate list update after creation (`PREPEND_ID_TO_CONTACT`)

**Decision**: Add a `PREPEND_ID_TO_CONTACT(state, { contactId, opportunityId })` mutation mirroring
the existing `PREPEND_ID_TO_STAGE` (`mutations.js:125-133`), guarded to no-op when
`state.idsByContact[contactId]` is `undefined` (contact never fetched into this view). Commit it
from the `create` action (`actions.js:136-173`) using `payload.contact_id` and `payload.id`,
alongside the existing `ADD_OPPORTUNITY`/`PREPEND_ID_TO_STAGE` commits.

**Rationale**: This is FR-007/FR-008 from the source technical doc, already scoped and justified
there — `state.idsByContact` is the only piece of `create`'s side effects currently missing,
verified by reading `actions.js:136-173` (commits `ADD_OPPORTUNITY` + `PREPEND_ID_TO_STAGE` only).
Because `cardsForContact` (`getters.js:6-9`) derives directly from `idsByContact`, this single
mutation makes the Contact Panel list, and any other current/future `cardsForContact` consumer,
update without a refetch.

**Alternatives considered**: Refetching `opportunities/fetchForContact` after creation — rejected
as an avoidable extra network round-trip when an in-memory prepend mutation is sufficient and
mirrors the codebase's existing `PREPEND_ID_TO_STAGE` convention.

## Decision: Closing the flow on conversation switch (FR-010)

**Decision**: In `ContactOpportunities.vue`, watch `() => currentChat.value.id` and close the local
create-modal state (`isCreateModalOpen.value = false`, mirroring the existing
`isBackfillModalOpen`/`backfillOpportunityId` pattern already in the file) whenever it changes.

**Rationale**: `ContactOpportunities.vue` is not destroyed/remounted on a same-route conversation
switch (only `contactId` changes trigger a distinct watch today, at line 29-36; conversation switch
between two conversations of the *same* contact would not otherwise fire it). An explicit watch on
`currentChat.value.id` is the smallest addition that guarantees the flow never stays open bound to
a conversation that's no longer on screen, matching the confirmed clarification answer and the
existing backdrop/click-outside-to-close convention for the sibling opportunity detail popup.

**Alternatives considered**: Relying solely on `woot-modal`'s existing backdrop/click-outside-close
— rejected as insufficient on its own, since it only closes on explicit user interaction with the
backdrop, not automatically on a programmatic conversation switch (e.g. clicking a different
conversation in the inbox list without touching the modal backdrop).
