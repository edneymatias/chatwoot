# Data Model: Scout Follow-Up Nudges and Rescue Handoff

No new tables. Two additive columns on the existing `ichatr_scouts` table; all other entities
below are existing models read or written by the new job, unchanged in shape.

## Scout (`ichatr_scouts`, `Scout` model) — extended

| Field | Type | Notes |
|---|---|---|
| `rescue_stage_id` *(new)* | `bigint`, nullable, FK → `ichatr_pipeline_stages`, `on_delete: :nullify`, indexed | Same pattern as `qualified_stage_id`/`unqualified_stage_id`. `NULL` (the default for existing rows) means this automation is disabled for the account — the job skips it entirely. |
| `follow_up_delays_hours` *(new)* | `jsonb`, `not null`, `default: [2, 12, 24]` | Ordered array of exactly 3 hour offsets since `last_activity_at`. Position 0 and 1 are the two re-engagement thresholds; position 2 is the rescue-handoff threshold. |

**New association**: `belongs_to :rescue_stage, class_name: 'PipelineStage', optional: true`

**New validation**: `follow_up_delays_hours` must be an array of exactly 3 strictly ascending,
unique, positive integers. Rationale: the job indexes into this array by attempt count and compares
consecutive thresholds — a non-ascending or non-positive sequence would either fire steps out of
order or never fire at all; the fixed length of 3 keeps the attempt count locked at "2 nudges then
handoff" (FR-004) so it can't drift by an account simply adding or removing array entries
(FR-005) — see `research.md` for why this needed an explicit length check.

**Unchanged**: `enabled` (existing boolean) still gates whether the Scout automation runs at all;
`FollowUpJob` only processes `Scout.where(enabled: true)`.

## Conversation — read-only for this feature

No schema changes. The job reads, **in this order, for both the nudge and the rescue-handoff
path — not just the final handoff**:
1. `scout.rescue_stage_id.blank?` — skip the whole Scout (no nudges, no handoff) if unset (FR-007).
2. Whether an open `Opportunity` is linked to the conversation — skip the conversation entirely if not (FR-010).
3. `status` (existing enum `open/resolved/pending/snoozed`) — only `pending` conversations are candidates, and `pending?` is re-checked immediately before any send to guard against a reply/takeover racing the scan.
4. `last_activity_at` — the silence clock; compared against `scout.follow_up_delays_hours[attempts]`.
5. `inbox` → `out_of_office?` (via the core `OutOfOffisable` concern) — business-hours guard.
6. `messages` — trailing outgoing/non-private messages since the last incoming one, to derive attempt count (see below).

## Message — read/write, no schema changes

- **Written** by a nudge: `message_type: outgoing`, `private: false`, `content_attributes: { scout_follow_up: true }`. This flag is the sole signal used to count attempts; it piggybacks on the existing JSON `content_attributes` column (no new column).
- **Read** to derive attempt count: walking from most recent to oldest, stop at the first `incoming?` message, and count how many of the outgoing messages in that trailing run carry `scout_follow_up: true`.

## Opportunity — read/write

- **Read**: the open opportunity (`status: open`) linked to the conversation via `opportunity_conversations`, most recently updated first. If none is open (e.g. only a `won`/`lost` record is linked), the conversation is skipped — the automation never touches a closed deal.
- **Written** at rescue handoff only: `pipeline_stage_id` is set to `scout.rescue_stage_id`. `Opportunity#status` is never written by this job (per spec Decision 3 / FR: only a human decides `won`/`lost`).
- **New derived field** (not persisted): `scout_engaged?` — `true` when *any* conversation linked to the opportunity via `opportunity_conversations` (not just `active_conversation`) is `pending?` on an inbox with an `enabled?` Scout attached. Exposed via `as_json['scout_engaged']` for the Kanban card badge. Recomputed on every read; no new column, no invalidation logic needed since it's a live derivation. Deliberately checks the full `conversations` association rather than `active_conversation`/`origin_conversation` alone: `active_conversation_id` is only promoted when a conversation is linked while `open?` (`attach_conversation!`, `custom/app/models/custom/concerns/opportunity_conversation_management.rb`) and is left `NULL` by the historical backfill migration for any opportunity whose origin conversation was already non-`open` at migration time — so for real pre-existing data, a currently-`pending` conversation is often linked to the deal without being its `active_conversation`.
- **New method**: `broadcast_scout_badge_refresh` — pushes a fresh `opportunity_updated` payload straight to `ActionCableBroadcastJob`, bypassing `broadcast_opportunity_updated`'s `dispatch_event`/Wisper bus on purpose (that bus is also what `Custom::AutomationRuleListener` subscribes to for "opportunity updated" automation rules; reusing it would spuriously re-trigger those rules on every conversation status change). Called from `Custom::Concerns::Conversation`'s `after_commit :refresh_linked_opportunities_scout_badge, on: :update, if: :saved_change_to_status?` for every opportunity linked to that conversation, since a conversation-only status change (e.g. handoff to a human) never itself touches the Opportunity record — without this, the Kanban card's badge would only catch up to the conversation's real status on a manual page reload.

## PipelineStage — read-only for this feature

No schema changes. `rescue_stage_id` on `Scout` simply points at an existing `PipelineStage` row belonging to the same account (same integrity pattern as `qualified_stage`/`unqualified_stage`); deleting that stage nullifies the FK rather than blocking the delete or cascading.

## State flow (per conversation, per silent period)

```
pending, silent ≥ delays[0] ──► nudge 1 sent (content_attributes.scout_follow_up = true)
        │
        ▼ still pending, silent ≥ delays[1]
        nudge 2 sent
        │
        ▼ still pending, silent ≥ delays[last]
        rescue handoff:
          - opportunity.pipeline_stage_id = scout.rescue_stage_id
          - HandoffService#perform (dedicated public message + private note + bot_handoff!)
        │
        ▼
        conversation no longer pending → sequence ends
```

At any point, a contact reply or human takeover flips `status` away from `pending`, and the very
next check on that conversation finds `conversation_pending?` false and takes no action — no
explicit "cancel" step is needed since the whole flow is a per-run derivation off current state,
never off stored intent.
