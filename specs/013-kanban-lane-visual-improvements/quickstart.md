# Quickstart: Kanban Lane Visual Improvements

Validate end-to-end inside the `rails`/`vite` containers per `CLAUDE.md`.

## Prerequisites

```bash
docker compose up -d
docker compose exec rails bundle exec rails db:migrate
```

Ensure a test account has: an active Kanban feature flag (`opportunities`), at least one pipeline
stage, and several opportunities across `open`/`won`/`lost` statuses in that stage — use
`docker compose exec rails bundle exec rails db:seed` or the `Seeders::AccountSeeder` path
documented in `CLAUDE.md` if no data exists yet.

## Scenario 1: Accurate lane total (value mode, default)

1. Open the Kanban board for an account whose lane has more open opportunities than fit on the
   first page of cards (or seed enough to exceed pagination).
2. Confirm the lane header shows a compact-formatted sum of **all** open opportunities' `value` in
   that lane — not just the loaded/scrolled-into-view ones.
3. Move a card into or out of the lane, create a new card in it, mark a card won/lost, or edit a
   card's value.
4. Confirm the lane header total updates after the action completes, without a full page reload,
   and without a visible loading indicator on the header itself.

## Scenario 2: Count mode

1. As an admin, edit a pipeline stage and switch its lane header display from "Total value" to
   "Count".
2. Confirm the lane header now shows the number of open opportunities in that lane (not a value),
   and never both at once.

## Scenario 3: Lane color accent

1. As an admin, edit a pipeline stage and set a color via the color picker.
2. Save, and confirm that lane's header shows the chosen color as its bottom border.
3. Confirm no other part of the lane — including individual deal cards — changed appearance.
4. Clear the color and confirm the header returns to the default, unaccented border.

## Scenario 4: Zero-state and exclusion of closed deals

1. View a lane with zero open opportunities (but possibly some won/lost ones still visible,
   soft-disabled). Confirm the header shows `0` (count mode) or a zero value (value mode) — not
   blank.
2. Confirm won/lost opportunities never affect the lane total in either mode.

## Verification commands

```bash
docker compose exec vite pnpm eslint
docker compose exec rails bundle exec rubocop -a
```

Both must pass with no new violations in touched files.
