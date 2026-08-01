# Quickstart: Card Info Enrichment & Lane Ordering

Manual validation steps for this feature. No new automated specs are required
(project convention: avoid writing specs unless explicitly asked).

## Prerequisites

- Stack running: `docker compose up -d`
- A seeded account with at least 3 opportunities, some with a `contact` avatar
  attached and some with an `assignee` set (see `Seeders::AccountSeeder` in
  `CLAUDE.md` if you need fresh sample data).

## 1. Verify the API response shape and ordering

```bash
docker compose exec rails bundle exec rails runner "
  account = Account.first
  puts Api::V1::Accounts::OpportunitiesController.new.tap { }.class
"
# Or directly via curl against a logged-in session / API token:
curl -s "http://localhost:3000/api/v1/accounts/<ACCOUNT_ID>/opportunities" \
  -H "api_access_token: <TOKEN>" | jq '.[] | {id, created_at, contact, assignee}'
```

Expected:
- `created_at` is an integer (epoch seconds), not an ISO8601 string.
- `contact` is either `null` or an object with `id`, `name`, `email`, `avatar_url`.
- `assignee` is either `null` or an object with `id`, `name`, `avatar_url`.
- Results are ordered newest-first by `created_at`.

## 2. Verify card rendering in the UI

1. Open the Kanban board in the dashboard for the seeded account.
2. Confirm each card shows the contact's avatar next to their name (falls back
   to initials/placeholder via `Avatar.vue` when no avatar is attached).
3. Confirm each card shows a human-readable relative creation date (e.g. "2
   days ago"), matching the style used on conversation cards.
4. Confirm cards within a lane are ordered newest-first.
5. Confirm clicking anywhere on a card — including directly over the new
   avatar and date — still opens the conversation drawer exactly as before,
   and that no new clickable link/button was added to the card (FR-007).

## 3. Verify stable ordering across reload

1. Drag a card from one stage to another.
2. Reload the page.
3. Confirm the card remains in its new stage and lane ordering is still
   newest-first (no cards appear out of order due to stale optimistic state).

## 4. Lint

```bash
docker compose exec rails bundle exec rubocop -a custom/app/models/opportunity.rb custom/app/controllers/api/v1/accounts/opportunities_controller.rb
docker compose exec vite pnpm eslint app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue
```
