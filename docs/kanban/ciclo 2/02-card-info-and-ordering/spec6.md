# Phase 6: Card Info Enrichment & Lane Ordering

**Depends on**: Phase 5 (conversation drawer)
**Feeds**: nothing yet

## Context

`Opportunity#as_json` currently only merges `origin_conversation_display_id`
onto the default attributes. `contact` and `assignee` are **not** actually
serialized (Rails' `as_json` does not include associations by default), so
`KanbanCard.vue`'s references to `opportunity.contact.name` and
`opportunity.assignee.name` are silently `undefined` today, despite reading
as if they work.

Separately, `OpportunitiesController#index` has no `ORDER BY`. Cards appear
newest-first today only as an artifact of `PREPEND_ID_TO_STAGE` on local
creation; a page refresh does not preserve that order.

This phase fixes both issues and adds a contact avatar and creation date to
the card. The "link to origin conversation" item from the original
placeholder is dropped: the whole card is already clickable to open the
conversation drawer (Phase 5), so a separate link would be redundant.

## Functional Requirements

**FR-001**: `Opportunity#as_json` MUST merge a `contact` hash
(`id`, `name`, `email`, `avatar_url`) and an `assignee` hash (`id`, `name`,
`avatar_url`, `nil` if unassigned), following the same inline-merge pattern
already used for `origin_conversation_display_id`. No new serializer class
is introduced.

**FR-002**: `OpportunitiesController#index` MUST order results by
`created_at: :desc`. "Newest" means creation time, not `updated_at` or last
stage transition. This is a backend-only change; no frontend sort is added.
Moving a card between stages (`MOVE_CARD_OPTIMISTIC`) MUST NOT reorder it
within the destination lane — ordering by creation time is preserved as-is.

**FR-003**: `KanbanCard.vue` MUST render the contact's avatar (reusing
`components-next/avatar/Avatar.vue`, size `sm`, using `contact.avatar_url`
and `contact.name` for initials fallback) next to the contact name.

**FR-004**: `KanbanCard.vue` MUST render the opportunity's creation date
(`created_at`), formatted with the existing `dynamicTime`/`shortTimestamp`
helpers from `shared/helpers/timeHelper` (same pattern as
`ConversationCard.vue`).

**FR-005**: No separate "link to conversation" element is added to the
card. The whole-card click behavior from Phase 5 already covers this.

## Out of Scope (this phase)

- Any change to `MOVE_CARD_OPTIMISTIC`/`REVERT_MOVE_CARD` mutation
  semantics — this phase only fixes initial-fetch ordering.
- Reordering by `updated_at` or last-stage-move time.
- A dedicated serializer class for `Opportunity` — the inline `as_json`
  merge pattern is kept for consistency with the existing code and the
  small size of the added payload.
- Any assignee-avatar-specific UI beyond what already exists for contact
  (assignee name display is unchanged; no assignee avatar was requested).

## Completion Criteria

Verify inside the `rails`/`vite` containers as appropriate.

1. `GET /api/v1/accounts/:account_id/opportunities` returns `contact` and
   `assignee` objects (with `avatar_url`) on each opportunity.
2. Opportunities in a stage are returned newest-`created_at`-first on page 1
   of `index`, and this order is reflected on board load (not just on local
   create).
3. `KanbanCard.vue` shows the contact's avatar next to their name, and the
   opportunity's creation date, for every card with a contact.
4. Moving a card to another stage does not change its position relative to
   creation order once persisted/refetched.
5. `pnpm eslint` and `bundle exec rubocop` pass for touched files.
