# Data Model: Scout Cross-Channel Activation

No new tables, columns, or migrations are introduced by this feature. This document records the
existing entities and the state transition this feature relies on — it does not define new schema.

## Entities involved (all pre-existing)

### Inbox
- Relevant existing method: `active_bot?` — the single decision point
  `Conversation#determine_conversation_status` consults to decide whether a new conversation
  starts `pending`. Currently only aware of the legacy `agent_bot_inbox`/Dialogflow mechanism
  (core) and Captain (`Enterprise::Inbox`).
- Relevant existing association (already present, unchanged): `has_one :scout, through:
  :scout_inbox` (`custom/app/models/custom/concerns/inbox.rb`).
- **New behavior** (in a new prepended module, not a new field): `active_bot?` additionally
  returns `true` when the inbox has an enabled Scout linked, via `super || scout_active?`.
- No channel-type restriction exists or is added — `active_bot?` is evaluated identically
  regardless of `channel_type`.

### Conversation
- Relevant existing field: `status` (relevant states here: `open`, `pending`).
- Relevant existing callback: `before_create :determine_conversation_status`
  (`app/models/conversation.rb:132`), which calls `set_active_bot_conversation` (→
  `status = :pending`) only when `inbox.active_bot?` is true at *creation* time.
- **No new states, no new callback.** This feature changes what `inbox.active_bot?` evaluates to
  for Scout-linked inboxes; it does not touch `Conversation` itself.
- Because the check only ever runs `before_create`, the fix is inherently forward-only: an
  already-persisted conversation's status is never re-evaluated against the new `active_bot?`
  logic (FR-008 / Decision 4 in `research.md`).

### Message
- Relevant existing fields: `incoming?`, `private?`, `inbox`, `conversation`.
- **No changes.** `Custom::ScoutListener#message_created` already reads these fields identically
  for every channel; only the extra `inbox&.channel_type == 'Channel::Whatsapp'` guard is removed.

### Scout (existing, `custom/app/models/scout.rb`, table `ichatr_scouts`)
- Relevant existing field: `enabled` (boolean, default `true`) — the sole gate for whether Scout is
  "on" for its associated inbox(es). Unchanged by this feature.

### ScoutInbox (existing, `custom/app/models/scout_inbox.rb`, table `ichatr_scout_inboxes`)
- Join table between `Scout` and `Inbox`; unique index on `inbox_id` (one Scout per inbox).
  Unchanged by this feature. `Api::V1::Accounts::Scouts::ScoutInboxesController#create` already
  allows linking a Scout to an inbox of any `channel_type` — no channel restriction exists at the
  linking layer today, confirming FR-001/FR-002 require no controller change either.

## Derived condition (not a new field — computed at evaluation time)

"Scout is effectively active for this inbox" is computed, not stored:

```
inbox.scout&.enabled? || false
```

This mirrors the existing `Enterprise::Inbox#captain_active?` pattern
(`captain_assistant.present? && more_responses?`) and the existing Scout gate idiom already used in
`custom/app/listeners/custom/scout_listener.rb` and `custom/app/models/custom/message.rb`.

## Control flow

```
New conversation created on any inbox
        │
        ▼
Conversation#determine_conversation_status (before_create)
        │
        ▼
  inbox.active_bot?
   → Custom::Inbox#active_bot?  (prepended, runs first)
       → super  (Enterprise::Inbox#active_bot? — Captain check, unchanged)
           → super  (core Inbox#active_bot? — legacy Dialogflow check, unchanged)
       → scout_active?  (inbox.scout&.enabled?)   [only evaluated if super was false]
        ▼
  true  → conversation.status = :pending
  false → conversation.status = :open  (default, unchanged)


Incoming public message arrives on a pending conversation
        │
        ▼
Custom::ScoutListener#message_created
   → message.incoming? && !message.private?      (unchanged)
   → inbox.scout&.enabled?                        (unchanged)
   → conversation&.pending?                        (unchanged)
   → [REMOVED] inbox&.channel_type == 'Channel::Whatsapp'
        ▼
Custom::Scout::ProcessMessageJob.enqueue_debounced(conversation, scout)
```

No other entity's data shape changes as a result of this feature.
