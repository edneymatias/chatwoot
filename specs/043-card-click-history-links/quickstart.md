# Quickstart: Validating Unified Card Click & History Links

## Prerequisites

- Stack running: `docker compose up -d` (see `CLAUDE.md`).
- An account with the Kanban module enabled, seeded with opportunities in a variety of states.
  `docker compose exec rails bundle exec rails db:seed` gives minimal coverage; for richer data
  (multiple conversations per opportunity, transfers, detachments) use the account seeder:
  `docker compose exec rails bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"`.
- At least one opportunity with **no** `active_conversation_id` and a history containing all four
  conversation-related event types (`conversation_opened`, `conversation_transferred_in`,
  `conversation_transferred_out`, `conversation_detached`) — check via
  `docker compose exec rails bundle exec rails runner "pp Opportunity.find(<id>).activities.pluck(:event_type)"`.
- Two agent users with different inbox/team access, to validate the permission-based link
  disabling (FR-006a/FR-010).

## Scenario 1 — Card click always opens something (User Story 1)

1. Open the Kanban board.
2. Click a card with an active conversation → drawer opens on the conversation tab (unchanged
   behavior).
3. Click a card with **no** active conversation → drawer opens on the history/activity tab
   (previously a no-op). Confirm the card had no grayscale/dashed styling before the click.
4. On a card without an active conversation, click the "+" control → only the start/link flow
   fires; the drawer does not also open on click-through.
5. Repeat steps 2–3 in list view (`Opportunities` list route) clicking a row instead of a card.

**Expected**: no click on any card/row is ever a no-op; the "+" control still works in isolation.

## Scenario 2 — History entries link to their conversation (User Story 2)

1. Open the history/activity tab for an opportunity with conversation-related events.
2. Confirm each `conversation_opened` / `_transferred_in` / `_transferred_out` / `_detached` entry
   renders as a link, with a status badge (open/pending/resolved) next to it.
3. Click a link for a **resolved** conversation → drawer switches to the conversation tab showing
   it, and `?opportunityId=` in the URL is unchanged.
4. Click a link for a `conversation_detached` entry (conversation no longer linked to this
   opportunity) → it still opens; opportunity context in the drawer stays the one whose history was
   being viewed, not the conversation's current opportunity (if any).
5. Confirm non-conversation entries (stage changes, won/lost/reopened) are still plain text.

**Expected**: every conversation-related entry is reachable in one click, regardless of the
referenced conversation's current status or linkage.

## Scenario 3 — Access-restricted and unresolvable conversations (FR-006a, FR-010)

1. As Agent A (has access to inbox X), confirm a history entry referencing a conversation in inbox
   X shows a status badge and a working link.
2. As Agent B (no access to inbox X, not on its team), open the same opportunity's history →
   confirm that same entry renders as **plain text**, no link, no status badge.
3. (If feasible) delete/soft-remove a referenced conversation and confirm its entry also renders as
   plain text with no badge, same as step 2.

**Expected**: Agent B can never reach a conversation they aren't authorized to view through this
feature, and a nonexistent conversation degrades the same way an unauthorized one does.

## Automated checks

- `docker compose exec vite pnpm eslint`
- `docker compose exec vite pnpm test -- KanbanCard OpportunityConversationDrawer OpportunityActivityLog`
- `docker compose exec rails bundle exec rubocop`
- `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/controllers/api/v1/accounts/opportunities/activities_controller_spec.rb`
  (or the closest existing spec covering this controller/action)
