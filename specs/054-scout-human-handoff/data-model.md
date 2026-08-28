# Data Model: Scout Human Handoff on Manual Intervention

No new tables, columns, or migrations are introduced by this feature (confirmed in Scope: "nenhum
novo campo de banco"). This document records the existing entities and the state transition this
feature relies on — it does not define new schema.

## Entities involved (all pre-existing)

### Conversation
- Relevant existing field: `status` (enum-like state; relevant states here are `pending` and
  `open`).
- Relevant existing association: `belongs_to :inbox`.
- **State transition this feature triggers**: `pending → open`, via the existing `conversation.open!`
  method, invoked synchronously from within `Message`'s `after_create_commit` callback chain.
  No new states are introduced.

### Message
- Relevant existing fields/methods used (not modified): `sender_type`, `private`, `outgoing?`,
  `human_response?`, `captain_pending_conversation?` (existing core hook point, chained via
  `super`).
- **New behavior** (in a new prepended module, not a new field): after calling `super`, evaluate a
  Scout-specific condition and call `conversation.open!` when it holds.

### Scout (existing, `custom/app/models/scout.rb`, table `ichatr_scouts`)
- Relevant existing field: `enabled` (boolean, default `true`) — the sole gate for whether Scout is
  "on" for its associated inbox(es).
- Relevant existing association: `has_many :scout_inboxes` / `has_many :inboxes, through:
  scout_inboxes`.

### ScoutInbox (existing, `custom/app/models/scout_inbox.rb`, table `ichatr_scout_inboxes`)
- Join table between `Scout` and `Inbox`; unique index on `inbox_id` (one Scout per inbox).
- Exposed on `Inbox` via `custom/app/models/custom/concerns/inbox.rb`:
  `has_one :scout_inbox` / `has_one :scout, through: :scout_inbox`.

## Derived condition (not a new field — computed at evaluation time)

"Scout is effectively enabled and pending-blocking for this conversation" is computed, not stored:

```
conversation.pending? && conversation.inbox&.scout&.enabled?
```

This mirrors the existing `captain_pending_conversation?` pattern
(`conversation.pending? && CaptainInbox.exists?(inbox_id: conversation.inbox_id)`) and the
existing Scout gate idiom used in `custom/app/listeners/custom/scout_listener.rb` and
`custom/app/jobs/custom/scout/process_message_job.rb` (`inbox.scout&.enabled?`).

## State transition diagram

```
Conversation.status: pending
        │
        │  human agent creates a Message where:
        │    sender_type == 'User'
        │    outgoing? == true (public reply)
        │    private? == false
        │    conversation.inbox.scout&.enabled? == true
        ▼
  Message#after_create_commit
   → mark_pending_conversation_as_open_for_human_response (Custom::Message, prepended)
       → super  (existing Captain check — unchanged)
       → Scout check: conversation.pending? && inbox.scout&.enabled?
           → conversation.open!
        ▼
Conversation.status: open
```

No other entity's data shape changes as a result of this feature.
