# Phase 72: WhatsApp Campaign Reply Tracking (Context, Analytics, Automation Chaining)

**Status**: Design approved by the user on 2026-08-21 — ready for an implementation plan.
Full design also recorded at `docs/kanban/ciclo 12/13-whatsapp-campaign-reply-tracking/2026-08-21-whatsapp-campaign-reply-tracking-design.md`.

**Depends on**: none functionally on other backlog phases. Builds directly on top of core
`Whatsapp::OneoffCampaignService` / `Whatsapp::IncomingMessageBaseService` and the fork's
`custom/`-over-`enterprise/` prepend-priority mechanism (`config/initializers/01_inject_enterprise_edition_module.rb`,
`ChatwootApp.extensions`). Targets `ichatr-main` (after `ichatr-scout` merges into it).

## Quick Preview

Today, sending a WhatsApp broadcast campaign via `Whatsapp::OneoffCampaignService` never creates a
`Message`/`Conversation` — so when a customer replies (free text or a quick-reply button tap), the
resulting conversation starts with zero context. The agent only sees the bare reply text
("tenho interesse", "quero agendar") with no idea which campaign or which message prompted it.

Upstream (merged into `ichatr-main` via the v4.17.0 sync) ships an Enterprise-licensed answer to
half of this problem: `enterprise/app/models/campaign_recipient.rb` tracks per-recipient
delivery/read status for analytics, but never correlates an inbound reply back to the campaign,
and running it in production requires a paid Chatwoot Enterprise subscription this fork doesn't
have.

This phase covers three parts, all approved for the same implementation effort:

1. **Contexto** — correlate an inbound reply to the campaign that prompted it, attach
   `campaign_id` to the new conversation, and backfill the original campaign message into the
   conversation so agents aren't starting from zero.
2. **Analytics** — extend the existing campaign analytics screen with a "Respostas únicas" metric
   and a "Cliques no botão" breakdown table (per WhatsApp Manager's own "Desempenho" panel, minus
   the trend chart).
3. **Encadeamento** — let automation rules condition on which campaign a conversation came from.

The user does not run concurrent WhatsApp campaigns today, but the design must not silently
misattribute a reply if that ever changes — ambiguous cases attribute to nothing rather than guess.

## Foundational decision: replace the Enterprise recipient tracking entirely, under `custom/`

Two core services own the WhatsApp campaign lifecycle: `Whatsapp::OneoffCampaignService` (send)
and `Whatsapp::IncomingMessageBaseService` (inbound webhook processing). Both are currently
prepended by Enterprise modules that write to the Enterprise `campaign_recipients` table.

We are **not** building alongside that Enterprise tracking (leaving it active and just ignoring its
output) — `Enterprise::Whatsapp::OneoffCampaignService#perform` fully replaces the OSS send flow
(no `super`), so leaving it prepended means it keeps running the entire send path and writing to
`campaign_recipients` on every campaign in production — exactly the "Enterprise code running
without a subscription" exposure we need to remove, not just stop reading from.

Instead this phase relies on the fork's own extension-priority order: `ChatwootApp.extensions`
returns `['enterprise', 'custom']`, and `prepend_mod_with` prepends a module per extension found,
in that order — since `prepend` always inserts at the front of the ancestor chain, a module
prepended later (`custom`) is checked first. A `Custom::Whatsapp::OneoffCampaignService` module
therefore intercepts calls before the Enterprise module ever runs, without editing a single file
under `enterprise/`. Same pattern already used by
`custom/app/services/custom/automation_rules/action_service.rb`.

**No table or model from Enterprise is reused.** `campaign_recipients` (Enterprise's table) stays
in the schema, permanently unused and empty. This phase introduces its own table,
`ichatr_campaign_recipients`, and its own model, `Custom::CampaignRecipient` — namespaced under
`Custom::` specifically because `enterprise/app/models/campaign_recipient.rb` already defines a
top-level `CampaignRecipient` constant, and Zeitwerk will not allow two files defining the same
constant across autoload paths. The same collision constraint applies to the analytics controller
(see Part 2) — it gets a distinct name and a new route, not a same-named override.

Trade-off, stated plainly: `Custom::Whatsapp::IncomingMessageBaseService#process_statuses` has to
duplicate a handful of lines from the OSS method to bypass the Enterprise module in that one spot
(Enterprise calls `super` there, so simply calling `super` from our module would still route
through it). This is small, stable code, but it is the one place future upstream changes could
silently drift out of sync with our copy — mitigated by specs asserting the duplicated behavior,
caught by the full RSpec suite already mandatory in this fork's pre-release checklist.

## Part 1 — Contexto

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

`status` enum: `queued, skipped, sent, delivered, read, replied, failed` — `replied` ranks above
`read`, below the terminal `failed`, mirroring the no-downgrade shape of the Enterprise model
without reusing any of its code.

`Campaign` (core, direct edit): add `has_many :ichatr_campaign_recipients, class_name:
'Custom::CampaignRecipient'`.

### Send path — `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb`

`module Custom::Whatsapp::OneoffCampaignService`, prepended over `Whatsapp::OneoffCampaignService`.
Rewrites `perform` (no `super`) to mirror the audience/liquid-processing flow already in the OSS
class, but per-contact: `find_or_create_by!` a `Custom::CampaignRecipient`, render+send the
template, and record the outcome (`mark_sent!(wamid)` / `mark_skipped!(reason)` /
`mark_failed!(error)`).

### Inbound path — `custom/app/services/custom/whatsapp/incoming_message_base_service.rb`

`module Custom::Whatsapp::IncomingMessageBaseService`, prepended over
`Whatsapp::IncomingMessageBaseService`. Two independent responsibilities:

- **`process_statuses`** (delivery/read/failed webhooks): reimplemented without `super` (bypasses
  the Enterprise module entirely) — same body as OSS's `find_message_by_source_id` /
  `update_whatsapp_identifiers_from_status` / `update_message_with_status` — then updates our
  `Custom::CampaignRecipient` (`source_id` match) instead of Enterprise's.
- **Reply correlation** (new inbound message webhooks): hooked into `process_messages`/
  `set_conversation`, calling `super` normally (Enterprise doesn't touch this path). Runs **only
  when a brand-new `Conversation` is about to be created** — an existing open conversation for the
  contact is never retroactively re-tagged with a `campaign_id`, even if a campaign happens to have
  been sent to that same contact.

Correlation algorithm, run once per new conversation, before it's persisted:

1. Read `context_id = message['context']&.[]('id')` from the raw webhook payload.
2. **Exact match**: if `context_id` present, `Custom::CampaignRecipient.find_by(account_id:,
   inbox_id:, source_id: context_id)`.
3. **Fallback (no `context_id`)**: only when unambiguous. Look for `Custom::CampaignRecipient`
   rows for that `contact_id`/`inbox_id`, status in `[sent, delivered, read]`, `replied_at: nil`,
   `sent_at` within a lookback window (72h constant for v1). If **exactly one** candidate exists,
   use it. If zero or more than one, **do not attribute** — never guess between concurrent
   campaigns.
4. If a recipient is resolved: set `conversation.campaign_id = recipient.campaign_id`; update the
   recipient (`status: :replied` respecting no-downgrade, `replied_at ||= Time.current`,
   `reply_source_id`, and `reply_type`/`reply_label` derived from
   `message.dig(:interactive, :button_reply, :title)` or `message.dig(:button, :text)` when
   present, else `reply_type: :free_text` with `reply_label: nil`).
5. **Context backfill**, only once per recipient (`campaign_message_id.blank?`): create a real
   outgoing `Message` in the new conversation — `content: recipient.message_content`,
   `sender: campaign.sender`, `source_id: recipient.source_id`, `created_at: recipient.sent_at`,
   `content_attributes: { campaign_context: true }` — before the inbound reply message is created,
   so it's the first thing the agent sees. Store its id on `recipient.campaign_message_id`.

Conversations are still only created lazily, on first reply — this phase does **not** eagerly
create a conversation/message for every campaign recipient at send time (would flood the inbox for
broadcasts with large audiences).

## Part 2 — Analytics

The existing analytics UI keeps working as-is: the current "Desempenho" cards (audience, sent,
delivered, read, failed, skipped) and the per-contact delivery table are reused unchanged, only
repointed to our own `custom/` backend instead of the Enterprise one. This phase only adds new
sections on top — nothing existing is removed or changed in behavior.

### API

New controller (distinct name — see collision note above), e.g.
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
  `click_rate = total_clicks / sent_count` (computed over total **sent**, matching WhatsApp
  Manager's own metric, not over unique repliers) — ordered by `total_clicks` desc, plus a trailing
  synthetic "Outras respostas" row aggregating `reply_type: :free_text`.

The old Enterprise route (`campaigns/:campaign_id/analytics/*`, still gated behind
`if ChatwootApp.enterprise?` in `config/routes.rb`) is left exactly as-is — untouched, still
routing to the Enterprise controller, simply unreachable once the frontend stops calling it.

### UI

`WhatsAppCampaignAnalyticsPage.vue` and children are reused as-is — only the data source changes
(`dashboard/api/campaigns.js` repointed at the new `recipients/*` endpoints). New additions:

- `CampaignMetricCard` grid gains a **"Respostas únicas"** card (count of recipients with
  `replied_at` present).
- New component `CampaignReplyBreakdown.vue`, injected between `CampaignDeliveryBreakdown`
  (existing deliverability block) and `CampaignDeliveryTable` (existing per-contact table) — a
  table of `Rótulo / Total de cliques / Taxa de cliques` plus the "Outras respostas" row, modeled
  after WhatsApp Manager's own "Cliques no botão" panel.
- No trend/line chart (explicitly declined by the user).

## Part 3 — Encadeamento

No changes to `AutomationRule` or `AutomationRules::ConditionsFilterService` — `campaign_id` reuses
the exact same generic conversation-attribute filter path already used for `team_id`/`inbox_id`,
because `conversations.campaign_id` already exists as a plain column
(`belongs_to :campaign, optional: true`).

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
  `campaigns/getAllCampaigns` store getter.
- i18n: `CAMPAIGN` condition label added to `en.json`/`pt_BR.json` automation locale files.

This composes with the existing `content` condition for free — "campanha X E resposta contém Y" is
just two conditions in the same rule, no new mechanism needed for that combination.

## Out of scope

- No automatic enforcement preventing concurrent campaigns — correlation degrades to "no
  attribution" when ambiguous, per the agreed rule, rather than restricting how campaigns are run.
- No UI to manually correct/reassign a wrong or missing `campaign_id` on a conversation.
- No historical backfill — conversations created before this ships are not retroactively
  attributed.
- No deletion of `enterprise/` files, the `campaign_recipients` (Enterprise) table/migration, or
  its routes/controller — left in place, inert.
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
- A contact replying in free text without quoting: correlates via the unambiguous-fallback rule
  when exactly one candidate exists; does not attribute when it doesn't.
- Two campaigns sent concurrently to the same contact, followed by an unquoted free-text reply:
  conversation is created with no `campaign_id` (never guesses).
- An agent already mid-conversation with a contact who separately receives a campaign send: that
  conversation's `campaign_id` is not touched.
- Campaign analytics page shows the existing delivery metrics/table unchanged, plus a working
  "Respostas únicas" card and button-click breakdown table with rates computed over messages sent,
  including a working "Outras respostas" bucket for free-text replies.
- An automation rule with a `campaign_id` condition (`equal_to` a specific campaign, or
  `is_present`) fires correctly on `message_created`/`conversation_created` for conversations
  attributed to that campaign, and does not fire for unattributed conversations.
- Full spec/lint suite (RuboCop, ESLint, RSpec, Jest) passes with the Enterprise-specific specs for
  `CampaignRecipient`/`Campaigns::AnalyticsController` untouched and still green (since those files
  aren't modified).
