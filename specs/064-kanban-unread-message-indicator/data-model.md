# Phase 1 Data Model: Kanban Unread Message Indicator (Post-Handoff Only)

No schema changes. Every field below is derived at read time from existing associations — nothing
new is persisted, matching how `scout_engaged?` already works.

## Opportunity (existing model, extended)

Fork model at `custom/app/models/opportunity.rb` (table `ichatr_opportunities`).

| Field (derived) | Type | Derivation | Notes |
|---|---|---|---|
| `has_unread_messages?` (new) | boolean | `!scout_engaged? && active_conversation&.unread_incoming_messages&.any?` (default `false` when no `active_conversation`) | Serialized as `has_unread_messages` in `as_json`. The `!scout_engaged?` gate is the addendum this feature exists to add — a card is only eligible for the dot once Scout is no longer engaged. |
| `scout_engaged?` (existing, unchanged) | boolean | `conversations.pending.any? { \|conv\| conv.inbox&.scout&.enabled? }` | Not modified by this feature; reused as the eligibility gate for the new field. Already serialized as `scout_engaged`. |

**Validation rules**: None — both are read-only derived booleans, not user input.

**State transitions** (of the derived `has_unread_messages?` value, driven by underlying
`Conversation`/`Message` state — see below):

```text
[not eligible: scout_engaged? = true]
        │
        │ conversation handed off (status change makes scout_engaged? false)
        ▼
[eligible, no unread] ──── new incoming, non-private message arrives ────▶ [eligible, unread → dot shown]
        ▲                                                                          │
        │                                                                          │ agent_last_seen_at updated (conversation read)
        └──────────────────────────────────────────────────────────────────────────┘
        │
        │ conversation becomes scout_engaged? again (re-engagement)
        ▼
[not eligible: dot hidden regardless of unread state]
```

**Renamed methods** (Phase 22 → this feature; behavior unchanged, only scope/name):

| Before (Phase 22) | After (this feature) |
|---|---|
| `Opportunity#broadcast_scout_badge_refresh` | `Opportunity#broadcast_kanban_badges_refresh` |
| `Custom::Concerns::Conversation#refresh_linked_opportunities_scout_badge` | `Custom::Concerns::Conversation#refresh_linked_opportunities_kanban_badges` |

## Conversation (existing core model, extended trigger only)

No new derived field on `Conversation` itself. It remains the source of two existing signals this
feature reads through `Opportunity`:

| Field (existing, unchanged) | Type | Purpose here |
|---|---|---|
| `agent_last_seen_at` | timestamp | When it changes (conversation read), `has_unread_messages?` flips false; now also triggers the Kanban broadcast (previously only `status` changes did). |
| `unread_incoming_messages` (method) | Array\<Message\> | Reused as-is (`.last(10)`, non-private incoming messages) to determine unread presence. |
| `status` | enum | Existing trigger condition, unchanged; drives `scout_engaged?` via the `pending` scope. |

**New trigger**: `after_commit` on `update`, condition widened from `saved_change_to_status?` to
`saved_change_to_status? || saved_change_to_agent_last_seen_at?`.

## Message (existing core model, new fork concern)

No new field. A new fork concern (`custom/app/models/custom/concerns/message.rb`, first use of the
existing-but-previously-empty `Message.include_mod_with('Concerns::Message')` hook) adds:

**New trigger**: `after_commit` on `create`, condition `incoming? && !private?` — pushes a
broadcast for every `Opportunity` linked to the message's conversation.

## Relationships (unchanged)

`Opportunity` ↔ `Conversation` via `OpportunityConversation` (existing join model, `conversations`
association) and the existing `active_conversation` belongs_to — both reused as-is; this feature
adds no new association.
