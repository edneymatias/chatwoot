# Quickstart: Validate Kanban Unread Message Indicator (Post-Handoff Only)

Validates the feature end-to-end against the acceptance scenarios in [spec.md](./spec.md). Assumes
the container stack is already running (`docker compose up -d`; see project `CLAUDE.md` for the
full container workflow).

## Prerequisites

- An account with at least one Scout-enabled inbox and at least one non-Scout inbox, each with an
  opportunity linked to a conversation. `Seeders::AccountSeeder`
  (`docker compose exec rails bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"`)
  or the standard `db:seed` can provide this; otherwise create manually via the Kanban board UI.
- Two browser sessions (or one + the Rails console) so you can trigger backend state changes while
  watching the board update live.

## Backend validation (model/concern behavior)

Run the targeted spec files this feature adds/extends (see plan.md's Project Structure for exact
paths):

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/models/opportunity_spec.rb \
  custom/spec/models/custom/concerns/conversation_spec.rb \
  custom/spec/models/custom/concerns/message_spec.rb
```

Expected: all examples pass, including cases asserting `has_unread_messages?` is `false` whenever
`scout_engaged?` is `true`, regardless of unread message count (Story 1, Scenario 3).

## Frontend validation (component behavior)

```bash
docker compose exec vite pnpm test -- KanbanCard
```

Expected: dot renders only when `opportunity.has_unread_messages` is `true`; absent for
`false`/`undefined`.

## End-to-end manual validation (real-time behavior)

1. Open the Kanban board for the seeded account in the browser.
2. **Scout-engaged card stays clean (Story 1, Scenario 3)**: find/create an opportunity whose
   conversation is pending on a Scout-enabled inbox; send an incoming customer message to it (e.g.
   via the inbox's test channel or `docker compose exec rails bundle exec rails runner` creating an
   incoming `Message`). Confirm the card shows the "Scout" badge and does **not** show the unread
   dot.
3. **Handoff reveals the dot (Story 1, Scenarios 1–2; Story 3)**: hand that conversation off to a
   human (change its status away from `pending`, e.g. assign it) while it still has the unread
   message from step 2. Confirm — without reloading the board — the "Scout" badge disappears and
   the unread dot appears within 5 seconds (SC-003).
4. **Reading clears the dot (Story 2)**: open the conversation and read it (updates
   `agent_last_seen_at`). Confirm — without reloading the board — the dot disappears within 5
   seconds (SC-003).
5. **New message on a visible, already-handed-off card (Story 3)**: with the board still open,
   send a new incoming message on that same (already handed-off) conversation. Confirm the dot
   reappears within 5 seconds (SC-003).
6. **Never-Scout-engaged opportunity (Story 1, Scenario 2)**: on an opportunity whose conversation
   was never on a Scout-enabled inbox, send an incoming message. Confirm the dot appears with no
   "Scout" badge involved at any point.
7. **Re-engagement hides it again (Story 4)**, if applicable to your test data: cause the
   conversation to become `pending` again on a Scout-enabled inbox. Confirm the dot disappears in
   real time even though the message is still technically unread.

## Full local pre-merge check

Per the repo's standard workflow (`CLAUDE.md`), before considering the feature done:

```bash
docker compose exec vite pnpm eslint
docker compose exec vite pnpm test
docker compose exec rails bundle exec rubocop
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec
```
