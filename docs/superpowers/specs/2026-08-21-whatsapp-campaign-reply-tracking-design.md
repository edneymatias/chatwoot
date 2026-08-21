# WhatsApp Campaign Reply Tracking — Design

**Date**: 2026-08-21
**Branch context**: designed against `ichatr-main` (post upstream v4.17.0 sync); to be implemented
after `ichatr-scout` merges into `ichatr-main`.

## Problem

`Whatsapp::OneoffCampaignService` sends broadcast template messages straight through
`channel.send_template(...)` without ever persisting a `Message`/`Conversation`. When a contact
replies (free text or by tapping a quick-reply button), Chatwoot creates a brand-new conversation
with zero context — the agent sees only the reply ("tenho interesse", "quero agendar") with no
idea which campaign, which message, or which offer prompted it. There is also no way to route or
report on that response.

Upstream (merged into `ichatr-main` via the v4.17.0 sync) ships an Enterprise-licensed answer to
half of this: `enterprise/app/models/campaign_recipient.rb` tracks per-recipient delivery/read
status (sent/delivered/read/failed) for analytics. But:

- It never correlates an *inbound* reply back to the campaign — it only listens to delivery-receipt
  webhooks, not message webhooks. The gap this design closes was never touched by it.
- Production use of `enterprise/` code requires a valid Chatwoot Enterprise subscription
  (`enterprise/LICENSE`). This fork has no such subscription, so we cannot build on it or leave it
  running.

This design covers three phases, agreed on in order:

1. **Contexto** — correlate an inbound reply to the campaign that prompted it, attach `campaign_id`
   to the new conversation, and backfill the original campaign message into the conversation so
   agents aren't starting from zero.
2. **Analytics** — extend the campaign analytics screen with a reply-rate metric and a per-button
   click breakdown (modeled after WhatsApp Manager's own "Desempenho" panel).
3. **Encadeamento** — let automation rules condition on which campaign a conversation came from, so
   flows can be routed without hardcoding message text.

## Decision: replace the Enterprise recipient tracking, don't build alongside it

Two services fully own the WhatsApp campaign lifecycle upstream:
`Whatsapp::OneoffCampaignService` (send) and `Whatsapp::IncomingMessageBaseService` (inbound
webhook processing). Both are prepended by Enterprise modules
(`Enterprise::Whatsapp::OneoffCampaignService`, `Enterprise::Whatsapp::IncomingMessageBaseService`)
that create/update `CampaignRecipient` rows.

We considered leaving the Enterprise tracking active alongside our own (`custom/`) tracking and
just not reading its output. This doesn't hold up:

- `Enterprise::Whatsapp::OneoffCampaignService#perform` fully replaces the OSS `perform` (no
  `super`) — it is not an additive hook, it's the entire send flow. Leaving it prepended means it
  keeps writing to `campaign_recipients` (Enterprise table) on every campaign send in production,
  which is exactly the "Enterprise code running in production without a subscription" situation we
  are trying to get away from. Silently storing data nobody reads doesn't remove that exposure.
- Getting our own tracking to run *at all* while the Enterprise module stays prepended in front of
  the class would require either stacking a second prepend in a load-order-dependent way, or fully
  duplicating the send flow's method bodies to intercept it — at which point "leave Enterprise
  untouched" has no benefit left.

Instead we exploit the fork's own extension-priority order. `ChatwootApp.extensions` returns
`['enterprise', 'custom']` (both directories exist in this fork), and `prepend_mod_with` prepends
modules for every extension that has a matching module, in that order. Since `prepend` always
inserts at the front of the ancestor chain, a module prepended later is checked *first* — so a
`Custom::Whatsapp::OneoffCampaignService` module lands ahead of the Enterprise one in the MRO. If
our module defines the same method without calling `super`, the Enterprise module never executes —
it becomes dead code, the same way the original OSS methods already go dead today when Enterprise
prepends over them. This is the same pattern already used in this fork for
`custom/app/services/custom/automation_rules/action_service.rb` (`Custom::AutomationRules::ActionService`
prepending over core `AutomationRules::ActionService`).

**Net effect: `enterprise/` is never edited.** It stays byte-for-byte upstream, which keeps future
`upstream/develop` tag syncs low-friction (no textual merge conflicts inside `enterprise/`). The
trade-off, stated plainly: our `Custom::Whatsapp::IncomingMessageBaseService#process_statuses`
override has to duplicate a handful of lines from the OSS method to bypass the Enterprise module
in that one spot (Enterprise *does* call `super` there, so simply calling `super` from our module
would still route through it). This is small, stable code, but it's the place where upstream
behavior changes could silently drift out of sync with our copy across a future sync — mitigated by
specs asserting the duplicated behavior, not just our additions, so a spec-suite run (already
mandatory pre-release per `CLAUDE.md`) catches drift.

No table or model from Enterprise is reused. `campaign_recipients` (Enterprise's table) stays in
the schema, unused and empty. We introduce our own table and model from scratch (see Data model).

### Naming collision constraint

`enterprise/app/models/campaign_recipient.rb` defines a top-level `CampaignRecipient` constant.
Since that file stays in place, our model **cannot** also be a top-level `CampaignRecipient` —
Zeitwerk would find two files defining the same constant across autoload paths and fail at boot.
Same problem applies to the analytics controller: `enterprise/app/controllers/api/v1/accounts/campaigns/analytics_controller.rb`
defines `Api::V1::Accounts::Campaigns::AnalyticsController`, so our controller must use a different
constant name, not reuse that route path under a new file. Both are namespaced under `Custom::`
(model) or given a distinct name (controller) to avoid this — see Data model / Phase 2 below.

## Phase 1 — Contexto

### Data model

New table `ichatr_campaign_recipients`, model `Custom::CampaignRecipient`
(`custom/app/models/custom/campaign_recipient.rb`):

```ruby
create_table :ichatr_campaign_recipients do |t|
  t.references :account,  null: false, foreign_key: { on_delete: :cascade }
  t.references :campaign, null: false, foreign_key: { on_delete: :cascade }
  t.references :contact,  null: false, foreign_key: { on_delete: :cascade }
  t.references :inbox,    null: false, foreign_key: { on_delete: :cascade }

  t.string :source_id                # wamid of the outbound template message
  t.integer :status, null: false, default: 0
  t.string :error_code
  t.string :error_title
  t.text   :error_message
  t.text   :message_content          # rendered template, for context backfill + analytics table

  t.datetime :sent_at
  t.datetime :delivered_at
  t.datetime :read_at
  t.datetime :replied_at
  t.datetime :failed_at

  t.string  :reply_source_id         # wamid of the inbound message that triggered correlation
  t.integer :reply_type              # quick_reply / free_text
  t.string  :reply_label             # button title, when reply_type == quick_reply
  t.bigint  :campaign_message_id     # backfilled outgoing Message id (see below)

  t.timestamps
end

add_index :ichatr_campaign_recipients, [:account_id, :campaign_id]
add_index :ichatr_campaign_recipients, [:campaign_id, :status]
add_index :ichatr_campaign_recipients, [:campaign_id, :contact_id], unique: true
add_index :ichatr_campaign_recipients, :source_id, unique: true, where: 'source_id IS NOT NULL'
add_index :ichatr_campaign_recipients, :reply_source_id, unique: true, where: 'reply_source_id IS NOT NULL'
```

`status` enum: `queued, skipped, sent, delivered, read, replied, failed` — same shape and
no-downgrade semantics as the Enterprise model (`replied` ranks above `read`, below the terminal
`failed`), written independently.

`Campaign` (core, small direct edit): replace nothing (there was never an Enterprise association on
`ichatr-scout`), add `has_many :ichatr_campaign_recipients, class_name: 'Custom::CampaignRecipient'`.

### Send path — `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb`

`module Custom::Whatsapp::OneoffCampaignService`, prepended over `Whatsapp::OneoffCampaignService`.
Rewrites `perform` (no `super`) to mirror the audience/liquid-processing flow already in the OSS
class, but per-contact: `find_or_create_by!` an `Custom::CampaignRecipient`, render+send the
template, and record the outcome (`mark_sent!(wamid)` / `mark_skipped!(reason)` /
`mark_failed!(error)`) instead of just logging.

### Inbound path — `custom/app/services/custom/whatsapp/incoming_message_base_service.rb`

`module Custom::Whatsapp::IncomingMessageBaseService`, prepended over
`Whatsapp::IncomingMessageBaseService`. Two independent responsibilities:

- **`process_statuses`** (delivery/read/failed webhooks): reimplemented without `super` (bypasses
  the Enterprise module entirely), calling `find_message_by_source_id` /
  `update_whatsapp_identifiers_from_status` / `update_message_with_status` directly — same as the
  OSS body — then updates our `Custom::CampaignRecipient` (`source_id` match) instead of Enterprise's.
- **Reply correlation** (new inbound message webhooks): hooked into `process_messages`/
  `set_conversation`, calling `super` normally (Enterprise doesn't touch this path, nothing to
  bypass). Runs **only when a brand-new `Conversation` is about to be created** — an existing open
  conversation for the contact is never retroactively re-tagged with a `campaign_id`, even if a
  campaign happens to have been sent to that contact. This avoids mislabeling an unrelated,
  already-in-progress conversation.

Correlation algorithm, run once per new conversation, before it's persisted:

1. Read `context_id = message['context']&.[]('id')` from the raw webhook payload.
2. **Exact match**: if `context_id` present, `Custom::CampaignRecipient.find_by(account_id:,
   inbox_id:, source_id: context_id)`.
3. **Fallback (no `context_id`)**: only when it can't be ambiguous. Look for
   `Custom::CampaignRecipient` rows for that `contact_id`/`inbox_id`, status in
   `[sent, delivered, read]`, `replied_at: nil`, `sent_at` within a lookback window (72h constant
   for v1). If **exactly one** candidate exists, use it. If zero or more than one, **do not
   attribute** — never guess between concurrent campaigns (explicitly agreed: a wrong attribution
   here would misroute Phase 3 automation, which is worse than no attribution).
4. If a recipient is resolved: set `conversation.campaign_id = recipient.campaign_id`; update the
   recipient (`status: :replied` respecting no-downgrade, `replied_at ||= Time.current`,
   `reply_source_id`, and `reply_type`/`reply_label` derived from
   `message.dig(:interactive, :button_reply, :title)` or `message.dig(:button, :text)` when present,
   else `reply_type: :free_text` with `reply_label: nil`).
5. **Context backfill**, only once per recipient (`campaign_message_id.blank?`): create a real
   outgoing `Message` in the new conversation — `content: recipient.message_content`,
   `sender: campaign.sender`, `source_id: recipient.source_id`, `created_at: recipient.sent_at`,
   `content_attributes: { campaign_context: true }` — before the inbound reply message is created,
   so it's the first thing the agent sees in the thread. Store its id on
   `recipient.campaign_message_id`.

Conversations are still only created lazily, on first reply — we do **not** eagerly create a
conversation/message for every campaign recipient at send time (would flood the inbox for
broadcasts with large audiences). The campaign message only becomes a real `Message` for contacts
who actually reply.

## Phase 2 — Analytics

### API

New controller (distinct name — see Naming collision constraint), e.g.
`custom/app/controllers/api/v1/accounts/campaigns/recipients_controller.rb` →
`Api::V1::Accounts::Campaigns::RecipientsController`, mounted at a **new, unconditional** route
(not gated by `ChatwootApp.enterprise?` — this is now a base fork feature):

- `GET /campaigns/:campaign_id/recipients/metrics` — same shape as the Enterprise version
  (`audience, sent, delivered, read, failed, skipped, status_counts`) plus `replied` (count of
  recipients with `replied_at` present).
- `GET /campaigns/:campaign_id/recipients/contacts` — same per-contact delivery table as before,
  sourced from `Custom::CampaignRecipient`.
- `GET /campaigns/:campaign_id/recipients/reply_breakdown` — grouped by `reply_label` where
  `reply_type: :quick_reply`, each row `{ label, total_clicks, click_rate }` with
  `click_rate = total_clicks / sent_count` (confirmed: computed over total **sent**, matching
  WhatsApp Manager's own metric, not over unique repliers) — ordered by `total_clicks` desc, plus a
  trailing synthetic "Outras respostas" row aggregating `reply_type: :free_text`.

The old Enterprise route (`campaigns/:campaign_id/analytics/*`, still gated behind
`if ChatwootApp.enterprise?` in `config/routes.rb`) is left exactly as-is — untouched, still
routing to the Enterprise controller. It becomes unreachable in normal operation once the frontend
stops calling it, without us deleting or editing anything under `enterprise/`.

### UI

`WhatsAppCampaignAnalyticsPage.vue` and children are reused (the Enterprise-authored layout is
fine, it's plain MIT-licensed Vue under `app/javascript/`, not gated) — only the data source
changes:

- `dashboard/api/campaigns.js`: point existing `analyticsMetrics`/`analyticsContacts` calls at the
  new `recipients/*` endpoints; add `analyticsReplyBreakdown`.
- `CampaignMetricCard` grid gains a **"Respostas únicas"** card (count of recipients with
  `replied_at` present).
- New component `CampaignReplyBreakdown.vue`, injected between `CampaignDeliveryBreakdown`
  (existing deliverability block) and `CampaignDeliveryTable` (existing per-contact table) — a
  table of `Rótulo / Total de cliques / Taxa de cliques` plus the "Outras respostas" row, modeled
  after the reference screenshot's "Cliques no botão" panel.
- No trend/line chart (explicitly out of scope, confirmed).

## Phase 3 — Encadeamento

No changes to `AutomationRule` or `AutomationRules::ConditionsFilterService` — `campaign_id` reuses
the exact same generic conversation-attribute filter path already used for `team_id`/`inbox_id`,
because `conversations.campaign_id` already exists as a plain column (`belongs_to :campaign,
optional: true`, present since before this design).

- `lib/filters/filter_keys.yml`: add under `conversations:`
  ```yaml
  campaign_id:
    attribute_type: "standard"
    data_type: "number"
    filter_operators:
      - "equal_to"
      - "not_equal_to"
      - "is_present"
      - "is_not_present"
  ```
  `is_present`/`is_not_present` cover "veio de campanha"; `equal_to` (with a campaign selector)
  covers "campanha é X" — one condition, not two.
- `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js`: add a
  `campaign_id` condition entry (`inputType: 'search_select'`, `filterOperators: OPERATOR_TYPES_3`,
  same shape as `team_id`) to the `message_created` and `conversation_created` condition lists.
- New search-select data source resolving campaign id → title, backed by the existing
  `campaigns/getAllCampaigns` store getter (same pattern `team_id`/`assignee_id` already use for
  their own stores).
- i18n: `CAMPAIGN` condition label added to `en.json`/`pt_BR.json` automation locale files.

This composes with the existing `content` condition for free — "campanha X E resposta contém Y" is
just two conditions in the same rule, no new mechanism needed for that combination.

## Out of scope

- No automatic enforcement preventing concurrent campaigns — correlation degrades to "no
  attribution" when ambiguous, per the agreed rule, rather than restricting how campaigns are run.
- No UI to manually correct/reassign a wrong or missing `campaign_id` on a conversation.
- No historical backfill — conversations created before this ships, or replies that arrived while
  only the (now-bypassed) Enterprise tracking was active, are not retroactively attributed.
- No deletion of `enterprise/` files, the `campaign_recipients` (Enterprise) table/migration, or its
  routes/controller — left in place, inert.
- No per-account configurable correlation lookback window (fixed 72h constant for v1).
- No trend/line chart in analytics.
- No special handling of WhatsApp Flow responses (`nfm_reply`) for `reply_label` — counted under
  "Outras respostas" (`free_text`) for v1, same as any non-button reply.
- No changes to `AutomationRule`/`ConditionsFilterService` backend beyond the YAML filter entry.

## Acceptance criteria

- Sending a WhatsApp one-off campaign creates one `Custom::CampaignRecipient` per contact, with no
  row/write in the Enterprise `campaign_recipients` table.
- A contact tapping a quick-reply button: the new conversation has `campaign_id` set, the original
  campaign message appears as the first message in the conversation, and the recipient's
  `reply_type`/`reply_label`/`replied_at` are populated correctly.
- A contact replying in free text without quoting: correlates via the unambiguous-fallback rule when
  exactly one candidate exists; does not attribute when it doesn't.
- Two campaigns sent concurrently to the same contact, followed by an unquoted free-text reply:
  conversation is created with no `campaign_id` (never guesses).
- An agent already mid-conversation with a contact who separately receives a campaign send: that
  conversation's `campaign_id` is not touched.
- Campaign analytics page shows "Respostas únicas" and a button-click breakdown table with rates
  computed over messages sent, with a working "Outras respostas" bucket for free-text replies.
- An automation rule with a `campaign_id` condition (`equal_to` a specific campaign, or
  `is_present`) fires correctly on `message_created`/`conversation_created` for conversations
  attributed to that campaign, and does not fire for unattributed conversations.
- Full spec/lint suite (RuboCop, ESLint, RSpec, Jest) passes with the Enterprise-specific specs for
  `CampaignRecipient`/`Campaigns::AnalyticsController` untouched and still green (since those files
  aren't modified).
