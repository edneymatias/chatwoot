# Quickstart: Hide Closed Opportunities by Default, and Fix Win/Loss Drag-and-Drop Bug

## Prerequisites

- Stack running: `docker compose up -d`
- An account with the `opportunities` feature enabled and the Kanban module set up (pipeline
  stages present)
- At least one open, one won, and one lost opportunity in the account (create via UI, or via
  `docker compose exec rails bundle exec rails runner "..."` using `Opportunity.create!`)

## Validate: default scoping (User Stories 1–3)

1. Open the Kanban board (`/app/accounts/:id/opportunities`) with no filters applied.
   - **Expected**: only the open opportunity's card is visible; the won/lost opportunities are
     absent, and no visual indicator marks a filter as active.
2. Switch to the List view with no filters applied.
   - **Expected**: same — only the open opportunity's row is visible.
3. Open the existing status filter and select "won".
   - **Expected**: only the won opportunity appears.
4. Repeat with "lost", then with all three statuses selected.
   - **Expected**: matching opportunities appear each time; selecting all statuses shows all
     three.
5. Open the contact profile panel for a contact that has open, won, and lost opportunities.
   - **Expected**: all three are listed, regardless of the board's default.

See [contracts/opportunities-index.md](./contracts/opportunities-index.md) for the underlying
request/response contract this behavior relies on.

## Validate: drag-and-drop fix (User Story 4)

1. On the Kanban board, start dragging a card from any pipeline stage column.
   - **Expected**: the won/lost drop zone appears in its own reserved layout space, not floating
     on top of the columns.
2. Drop the card on the "Won" zone.
   - **Expected**: the card disappears from the board (now closed, hidden by the new default); the
     opportunity's `status` becomes `won`.
3. Filter the board to show `won` opportunities and confirm the card's pipeline stage matches
   whatever stage it was in immediately before the drop (check via the opportunity's detail view
   or API response `pipeline_stage_id`).
4. Repeat steps 1–3 dropping on "Lost" instead.
5. Repeat from several different pipeline stage columns (first, middle, last) to confirm the fix
   holds regardless of which column's bounding rect is nearest the drop zone.

See [data-model.md](./data-model.md#state-transitions) for the invariant being verified
(`status` changes; `pipeline_stage_id` does not).

## Backend spec check

```
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  spec/requests/api/v1/accounts/opportunities_controller_spec.rb
```
