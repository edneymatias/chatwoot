# Data Model: WhatsApp Campaign Reply Tracking

## Entity: `Custom::CampaignRecipient` (new)

Table: `ichatr_campaign_recipients` (new, fork-owned). One row per contact targeted by one WhatsApp
one-off campaign send.

| Field | Type | Notes |
|---|---|---|
| `account_id` | `bigint`, `null: false`, FK (`on_delete: :cascade`) | |
| `campaign_id` | `bigint`, `null: false`, FK (`on_delete: :cascade`) | |
| `contact_id` | `bigint`, `null: false`, FK (`on_delete: :cascade`) | |
| `inbox_id` | `bigint`, `null: false`, FK (`on_delete: :cascade`) | |
| `source_id` | `string`, nullable | wamid of the outbound template message. Unique when present. |
| `status` | `integer`, `null: false`, default `0` | enum, see State transitions below. |
| `error_code` / `error_title` / `error_message` | `string`/`string`/`text`, nullable | populated on `mark_failed!`. |
| `message_content` | `text`, nullable | rendered template body — context backfill source + analytics table display. |
| `sent_at` / `delivered_at` / `read_at` / `replied_at` / `failed_at` | `datetime`, nullable | lifecycle timestamps, each set once by the corresponding `mark_*!`/`update_from_whatsapp_status!` transition. |
| `reply_source_id` | `string`, nullable | wamid of the inbound message that triggered correlation. Unique when present. |
| `reply_type` | `integer`, nullable | enum: `quick_reply` / `free_text`. |
| `reply_label` | `string`, nullable | button title, only when `reply_type == quick_reply`. |
| `campaign_message_id` | `bigint`, nullable | id of the backfilled outgoing `Message` — set once, guards the "backfill only once" rule. |

**Indexes**:
- `[account_id, campaign_id]`
- `[campaign_id, status]`
- `[campaign_id, contact_id]` unique — one recipient row per contact per campaign send.
- `source_id` unique where not null.
- `reply_source_id` unique where not null.

**Associations**: `belongs_to :account`, `:campaign`, `:contact`, `:inbox`.

**Validations**: `validates :contact_id, uniqueness: { scope: :campaign_id }` (redundant with the DB
unique index, matching the Enterprise model's own belt-and-suspenders style — verified present
there); `validates :source_id, uniqueness: true, allow_blank: true`; `validates :reply_source_id,
uniqueness: true, allow_blank: true`.

**State transitions** (`status` enum):

```
queued(0) → skipped(1)
queued(0) → sent(2) → delivered(3) → read(4) → replied(5)
                                    ↘        ↘
                                     failed(6) ← (from sent/delivered/read/replied, via webhook error)
```

No-downgrade rule (mirrors `enterprise/app/models/campaign_recipient.rb#status_downgrade?`,
extended by one rank for `replied`): a status update is applied only if the new status's enum rank
is `>=` the current rank, with `failed` always applied regardless of current status *except* when
already `delivered` or `read` and the incoming update is a `delivered`-after-`read` race (handled
identically to the Enterprise model: a `delivered` webhook arriving after `read` is already set
back-fills `delivered_at` without changing `status`, never regresses it). `replied` is set only by
the reply-correlation flow (`Custom::Whatsapp::IncomingMessageBaseService`), never by
`update_from_whatsapp_status!` (which only ever receives `delivered`/`read`/`failed` from WhatsApp
status webhooks).

**Methods** (mirroring the Enterprise model's shape exactly, extended for reply correlation):
- `mark_sent!(source_id)`, `mark_skipped!(message)`, `mark_failed!(error = {})` — identical
  contracts to Enterprise's.
- `update_from_whatsapp_status!(status)` — identical contract, same `with_lock` +
  `status_downgrade?` guard, extended enum range.
- `mark_replied!(reply_source_id:, reply_type:, reply_label: nil)` — new. Sets `status: :replied`
  (respecting no-downgrade — a no-op on `status` if already `replied` or `failed`, but always sets
  `replied_at ||= Time.current`, `reply_source_id`, `reply_type`, `reply_label` idempotently even
  when `status` itself doesn't move, so a second webhook redelivery for the same reply doesn't lose
  data).

## Entity: `Campaign` (existing — extended via extension point)

Table: `campaigns` (existing, core, unchanged schema). Gains one association via
`Custom::Campaign` (`custom/app/models/custom/campaign.rb`, wired through the already-existing
`Campaign.include_mod_with('Campaign')` call at the bottom of `app/models/campaign.rb`):

```ruby
has_many :ichatr_campaign_recipients, class_name: 'Custom::CampaignRecipient', dependent: :destroy
```

No column changes. No core file edited.

## Entity: `Conversation` (existing — read/write, no schema change)

Table: `conversations` (existing, core, unchanged schema). `campaign_id` (already present,
`belongs_to :campaign, optional: true`) is set by `Custom::Whatsapp::IncomingMessageBaseService#set_conversation`
exactly once, only at the moment a **new** conversation row is created via correlation — never
updated afterward by later campaign activity for that same contact (FR-004). No other column is
touched by this feature.

## Entity: `Message` (existing — new row created, no schema change)

The context-backfill message is a normal outgoing `Message` row (no new columns, no new type) built
via the conversation's existing `messages.build`/`create!` path, with:
- `content: recipient.message_content`
- `sender: campaign.sender`
- `source_id: recipient.source_id` (the original template wamid — reused, not duplicated, so this
  message *is* the record of that outbound send in the conversation's timeline)
- `created_at: recipient.sent_at` (backdated to when the campaign was actually sent, so the
  conversation timeline reads correctly even though the message row is created later, at reply
  time)
- `content_attributes: { campaign_context: true }` — a marker flag, not used for any query in this
  feature, but present for future UI treatment (e.g., a distinct visual style) without requiring a
  schema change later.

## Value object: Recipient metrics response (`GET .../recipients/metrics`)

Not persisted — computed in `Api::V1::Accounts::Campaigns::RecipientsController#delivery_metrics`,
same shape as the Enterprise `analytics/metrics` response plus one new field:

```text
{
  audience, sent, delivered, read, failed, skipped,   # unchanged shape/semantics vs. Enterprise's version
  replied,                                              # new: count of recipients with replied_at present
  status_counts: { queued, skipped, sent, delivered, read, replied, failed }  # one more key than Enterprise's (adds replied)
}
```

Documented in full in [contracts/campaign-recipients-api.md](./contracts/campaign-recipients-api.md).

## Value object: Reply breakdown response (`GET .../recipients/reply_breakdown`)

Not persisted — computed in `#reply_breakdown`, grouping `Custom::CampaignRecipient` rows by
`reply_label` where `reply_type: :quick_reply`, plus one synthetic aggregate row:

```text
[
  { label: "Sim, quero agendar", total_clicks: 42, click_rate: 0.31 },
  { label: "Falar com atendente", total_clicks: 18, click_rate: 0.13 },
  { label: "other", total_clicks: 9, click_rate: 0.07 }   # aggregates reply_type: :free_text — machine key, not display text; see contracts/campaign-recipients-api.md
]
```

`click_rate = total_clicks / sent_count` where `sent_count` is the campaign's total `sent` count
(same denominator as the `metrics` endpoint's `sent` field — recipients with a non-null
`source_id`), matching WhatsApp Manager's own metric convention (per source design) rather than a
rate over unique repliers. Rows ordered by `total_clicks` desc; the `"other"` row is always last
regardless of its count. The backend returns the literal string `"other"` for that row's `label` —
not a display string in any language — so the frontend can render it via i18n
(`t('CAMPAIGN.WHATSAPP.ANALYTICS.REPLY_BREAKDOWN.OTHER_REPLIES')`) exactly like every other label on
the page, instead of hardcoding "Outras respostas" server-side.
