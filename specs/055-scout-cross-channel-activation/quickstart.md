# Quickstart: Validating Scout Cross-Channel Activation

This is a backend-only behavioral change with no new UI or endpoint (see `data-model.md` /
`research.md`). Validation is done via the Rails console / test suite against the existing stack,
plus one manual end-to-end pass through the actual Website Widget (per the spec's Acceptance
Criteria).

## Prerequisites

- Stack running: `docker compose up -d`
- A seeded account with:
  - A **non-WhatsApp** inbox (e.g. Website Widget or Email) with an **enabled** `Scout` attached
    (`ScoutInbox` linking them).
  - A second inbox with **no** Scout linked, and a third with a **disabled** Scout linked, for the
    negative scenarios.

You can use `docker compose exec rails bundle exec rails db:seed` or the richer
`Seeders::AccountSeeder` flow (see `CLAUDE.md`) to get a Scout-enabled account, or set one up
directly in the Rails console (see below).

## Scenario 1 — New conversation on a Website Widget inbox with an enabled Scout starts `pending` (P1)

```ruby
# docker compose exec rails bundle exec rails console
account = Account.find(<id>)
inbox = account.inboxes.create!(name: 'Widget', channel: Channel::WebWidget.create!(account: account))
scout = Scout.create!(account: account, name: 'Widget SDR', enabled: true)
ScoutInbox.create!(scout: scout, inbox: inbox)

contact = account.contacts.create!(name: 'Visitor')
contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
conversation = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

conversation.status # => "pending"
```

**Expected outcome**: `conversation.status` is `"pending"` immediately on creation, with no
`agent_bot_inbox`/Dialogflow configuration involved — matching FR-002.

## Scenario 2 — Incoming message on that conversation triggers the Scout pipeline (P1)

```ruby
allow(Custom::Scout::ProcessMessageJob).to receive(:enqueue_debounced) # if run inside a spec

message = conversation.messages.create!(
  account_id: account.id,
  inbox_id: inbox.id,
  message_type: :incoming,
  private: false,
  content: 'Hi, I need help'
)
```

**Expected outcome**: `Custom::Scout::ProcessMessageJob.enqueue_debounced` is invoked with
`(conversation, scout)` — matching FR-001. In a real (non-stubbed) run, the Scout responds in the
conversation shortly after, same as it already does on WhatsApp.

## Scenario 3 — Inbox with no Scout, or a disabled Scout, is unaffected (P2)

```ruby
inbox_no_scout = account.inboxes.create!(name: 'No Scout', channel: Channel::WebWidget.create!(account: account))
contact_inbox2 = ContactInbox.create!(contact: contact, inbox: inbox_no_scout, source_id: SecureRandom.uuid)
conversation_no_scout = Conversation.create!(account: account, inbox: inbox_no_scout, contact: contact, contact_inbox: contact_inbox2)
conversation_no_scout.status # => "open" (unchanged)

scout.update!(enabled: false)
conversation.reload
# Re-creating a conversation on `inbox` now (with Scout disabled) also starts "open"
```

**Expected outcome**: no change from current production behavior — matching FR-003.

## Scenario 4 — Legacy Dialogflow-active inbox still starts `pending` (P2 regression guard)

Covered by existing core/enterprise specs for `Inbox#active_bot?` and
`Conversation#determine_conversation_status` — not re-authored here; `Custom::Inbox#active_bot?`
calls `super` first, so this path is structurally unchanged (see `research.md` Decision 2/3).

## Scenario 5 — Human handoff still works on a non-WhatsApp Scout conversation (P3)

```ruby
conversation.pending!
agent = account.users.first
conversation.messages.create!(
  account_id: account.id,
  inbox_id: inbox.id,
  message_type: :outgoing,
  private: false,
  sender: agent,
  content: 'Hey, I can help you with that.'
)

conversation.reload.status # => "open"
```

**Expected outcome**: identical to the existing Phase 10 behavior
(`specs/054-scout-human-handoff/quickstart.md` Scenario 1), now exercised on a non-WhatsApp inbox
— matching FR-006 and User Story 3. No code change is required for this to pass; it is a
regression check on `custom/app/models/custom/message.rb`, whose guard
(`conversation.pending? && inbox.scout&.enabled?`) was already channel-agnostic.

## Manual end-to-end pass (required by spec Acceptance Criteria)

1. In the Chatwoot UI, connect a Scout to a Website Widget inbox.
2. Open that inbox's widget test/preview page and start a new conversation.
3. Confirm the Scout replies to the first message, the same way it already does for a WhatsApp
   test conversation.

## Automated verification

Run the targeted spec suite once implemented:

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/listeners/custom/scout_listener_spec.rb \
  custom/spec/models/custom/inbox_spec.rb
```

Also re-run the fork's standard targeted suite (per `CLAUDE.md`) to confirm no regression to
Kanban/Opportunity or existing Inbox/Conversation/Message/Captain specs:

```bash
docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec \
  custom/spec/ spec/models/inbox_spec.rb spec/models/conversation_spec.rb spec/models/opportunity_spec.rb
```

## Out of scope for this quickstart

No frontend flow beyond step 2 of the manual pass above — this phase adds no new UI. Campaign/
referral attribution (CTWA/Meta Referral) validation is unchanged and already covered by existing
specs; this quickstart does not re-verify it (spec Out of Scope / Edge Cases).
