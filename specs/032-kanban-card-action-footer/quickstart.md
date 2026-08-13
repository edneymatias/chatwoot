# Quickstart: Validate Kanban Card Action Footer

## Prerequisites

- Dev stack running: `docker compose up -d` (rails on :3000, vite on :3036)
- An account with the Kanban/Opportunities module enabled and at least one pipeline with stages
- Seeded opportunity data covering the three action-button conditions (see Scenarios below); use
  `docker compose exec rails bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"`
  if richer sample data is needed, or manually create/edit opportunities via the UI

## Setup

1. Open the dashboard at `http://localhost:3000` (or the configured `FRONTEND_URL`) and navigate
   to **Opportunities → Kanban board**.
2. Have on the board (or create) opportunities matching each scenario below.

## Scenarios

### 1. Open opportunity without a linked conversation (start-conversation action)

- Find/create an **open** opportunity with no `origin_conversation_id`.
- Hover the card.
- **Expected**: a subtle top divider appears above a footer row containing the "start
  conversation" button, right-aligned; no overlap with the card's text content above.

### 2. Closed/lost opportunity (reopen action)

- Find/create an opportunity with `status` set to something other than `open` (e.g. `lost`).
- Hover the card.
- **Expected**: divider + footer row appear containing the "reopen" button, right-aligned.

### 3. Open opportunity with unmet required stage fields (complete-fields action)

- Find/create an **open** opportunity in a stage with required custom attribute definitions (or
  `requires_deal_value`), leaving those fields empty.
- Hover the card.
- **Expected**: divider + footer row appear containing the "complete fields" button (or "edit" if
  requirements are met), right-aligned. If this card also lacks `origin_conversation_id`, both
  buttons appear in the same row, right-to-left in their current order.

### 4. Opportunity with no available actions (no footer)

- Find/create an **open** opportunity that already has `origin_conversation_id` set and has all
  required stage fields filled.
- Hover the card.
- **Expected**: no divider and no footer row render; card height matches the pre-change baseline
  (compare against a card from before this change, or against scenario 4 on `develop`).

## Manual regression check

- Confirm the button row's right-to-left order matches current `develop` behavior (visually
  compare against the same opportunity on the `develop` branch or a screenshot taken before the
  change).
- Confirm hover show/hide timing (opacity transition) is unchanged.

## Automated checks

- `docker compose exec vite pnpm eslint app/javascript/dashboard/components-next/Opportunities/KanbanCard.vue`
- `docker compose exec vite pnpm test` (confirms no existing suite regresses; no new spec file is
  added per project convention of not writing specs unless explicitly requested)
