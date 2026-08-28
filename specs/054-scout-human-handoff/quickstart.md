# Quickstart: Validating Scout Human Handoff on Manual Intervention

This is a backend-only behavioral change with no new UI or endpoint (see `data-model.md` /
`research.md`). Validation is done via the Rails console / test suite against the existing stack.

## Prerequisites

- Stack running: `docker compose up -d`
- A seeded account with:
  - An inbox with an **enabled** `Scout` attached (`ScoutInbox` linking them).
  - A `Conversation` in that inbox with `status: pending`.
  - A `User` (human agent) who can author a message.

You can use `docker compose exec rails bundle exec rails db:seed` or the richer
`Seeders::AccountSeeder` flow (see `CLAUDE.md`) to get a Scout-enabled inbox/account, or set one up
directly in the Rails console (see below).

## Scenario 1 — Human public reply reopens a pending, Scout-enabled conversation (P1)

```ruby
# docker compose exec rails bundle exec rails console
conversation = Conversation.find(<id>)               # status: pending, inbox has enabled Scout
conversation.pending!
conversation.inbox.scout.update!(enabled: true)

agent = conversation.account.users.first
conversation.messages.create!(
  account_id: conversation.account_id,
  inbox_id: conversation.inbox_id,
  message_type: :outgoing,
  private: false,
  sender: agent,
  content: 'Hey, I can help you with that.'
)

conversation.reload.status # => "open"
```

**Expected outcome**: `conversation.status` is `"open"` immediately after the message is created
(no delay, no background job to wait on) — matching FR-002/FR-003/SC-004.

## Scenario 2 — Private note does not trigger reopening (P2)

```ruby
conversation.pending!
conversation.messages.create!(
  account_id: conversation.account_id,
  inbox_id: conversation.inbox_id,
  message_type: :outgoing,
  private: true,
  sender: agent,
  content: 'Internal note for teammate'
)

conversation.reload.status # => "pending" (unchanged)
```

**Expected outcome**: status remains `pending` — matching FR-004.

## Scenario 3 — Conversations without Scout are unaffected (P3)

```ruby
conversation_no_scout = Conversation.find(<id in inbox without Scout>)
conversation_no_scout.pending!
conversation_no_scout.messages.create!(
  account_id: conversation_no_scout.account_id,
  inbox_id: conversation_no_scout.inbox_id,
  message_type: :outgoing,
  private: false,
  sender: agent,
  content: 'Reply as usual'
)

conversation_no_scout.reload.status # => same as current (pre-feature) behavior
```

**Expected outcome**: no change from current production behavior — matching FR-005.

## Automated verification

Run the targeted spec suite once implemented:

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/models/custom/message_spec.rb
```

Also re-run the fork's standard targeted suite (per `CLAUDE.md`) to confirm no regression to
Kanban/Opportunity or existing Message/Captain specs:

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/ spec/models/message_spec.rb spec/models/opportunity_spec.rb
```

## Out of scope for this quickstart

No frontend flow to click through — this phase adds no UI (badge, Kanban link, comparison
indicator, pause/resume control). Those are covered by Phase 15's own validation guide when built.
