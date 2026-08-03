# Quickstart: Validating Drag-to-Close Status Bar

## Prerequisites

- Stack running: `docker compose up -d` (see project `CLAUDE.md`)
- Logged into an account with at least one pipeline that has two or more open opportunities across different stages (seed with `bundle exec rails db:seed` or the Account Seeder if needed)
- Optionally, for the closing-required-fields interaction: an account with at least one required custom attribute configured for "won" or "lost" (see `specs/010-closing-required-fields`). Scenario 5 only applies once that feature is implemented and deployed — if it isn't yet, skip Scenario 5.

## Scenario 1 — Close an opportunity as Won by dragging

1. Open the Opportunities kanban board.
2. Pick up an open opportunity card and start dragging it.
3. **Expect**: a status bar with "Won" and "Lost" zones appears (e.g. at the bottom of the board).
4. Drag the card over the "Won" zone.
5. **Expect**: the zone shows a visual highlight.
6. Drop the card on the "Won" zone.
7. **Expect**: the card's status becomes "won" (status badge updates), and the card remains in its original lane/column and position area (not moved into some other stage).

## Scenario 2 — Close an opportunity as Lost by dragging

Repeat Scenario 1, dropping on the "Lost" zone instead — expect status becomes "lost", card stays in its lane.

## Scenario 3 — Drop outside a valid zone is a no-op for status

1. Drag an open opportunity card.
2. Drop it somewhere that is not the "Won"/"Lost" zone and not a valid lane position (e.g. release outside the board).
3. **Expect**: status is unchanged; status bar disappears once the drag ends.

## Scenario 4 — Buttons are gone, reopen still works

1. Inspect an open opportunity card's hover actions.
2. **Expect**: no "Mark as Won"/"Mark as Lost" buttons are present.
3. Close an opportunity (Scenario 1 or 2), then click its "Reopen" button.
4. **Expect**: status returns to "open" without any drag interaction, and no status bar was involved.

## Scenario 5 — Closing-required-fields blocks the drag-drop close (if configured)

Requires an account with a required custom attribute configured for "won" or "lost" (`010-closing-required-fields`).

1. Drag an opportunity that is missing that required attribute onto the corresponding zone.
2. **Expect**: the status change is rejected, the card's status is unchanged, and the existing missing-fields modal (`ClosingRequirementsModal.vue`) opens prompting for the missing value(s).
3. Fill in the missing value and resubmit via the modal.
4. **Expect**: the status change completes as in Scenario 1/2.

## Scenario 6 — Already-closed cards are not draggable onto the status bar

1. Locate a card with status "won" or "lost" (or produce one via Scenario 1/2).
2. Attempt to pick it up and drag it.
3. **Expect**: the card cannot be dragged onto the "Won"/"Lost" zones (e.g. no drag starts for it, or the status bar's zones do not accept it) — the opportunity's status remains unchanged. The card's "Reopen" button (Scenario 4) remains the only way to change its status.

## Automated checks

- `docker compose exec vite pnpm eslint` — lint the changed Vue files
- `docker compose exec vite pnpm test` — run existing frontend test suite (no new specs are added per project convention unless explicitly requested)
