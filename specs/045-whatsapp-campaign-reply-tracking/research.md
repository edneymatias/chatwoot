# Phase 0 Research: WhatsApp Campaign Reply Tracking

All items below were pre-resolved either by the approved source design
(`docs/kanban/ciclo 12/13-whatsapp-campaign-reply-tracking/spec72.md`), by inspecting the actual
current state of the codebase (the design doc predates this plan and its file inventory was
verified, not assumed), or by the `/speckit-clarify` session recorded in `spec.md` (which found no
outstanding ambiguities). No open `NEEDS CLARIFICATION` markers remain.

## Decision: Replace, not augment, the Enterprise recipient tracking

**Decision**: `Custom::Whatsapp::OneoffCampaignService#perform` fully replaces (no `super`) the OSS
`perform`; `Custom::Whatsapp::IncomingMessageBaseService#process_statuses` fully replaces (no
`super`) the OSS `process_statuses`. Both ride `ChatwootApp.extensions` returning `['enterprise',
'custom']` — `prepend_mod_with` prepends `enterprise` first, then `custom`, and `prepend` inserts
at the front of the ancestor chain, so `custom`'s override runs first and, by never calling
`super`, prevents Enterprise's version from running at all for these two methods.

**Rationale**: `Enterprise::Whatsapp::OneoffCampaignService#perform` (verified at
`enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb`) itself calls no `super` —
it fully owns `create_recipients`/`process_recipients`/writes to the Enterprise `campaign_recipients`
table on every send. Leaving it prepended (even unread) means Enterprise code keeps running in
production with no paid subscription — exactly what this phase exists to stop. The only way to
prevent that is for a higher-priority prepend to intercept the call before Enterprise's version
runs, which requires *not* calling `super` at that method.

**Alternatives considered**: Reading Enterprise's `campaign_recipients` table directly instead of
introducing a new table — rejected per the source design's explicit constraint (this is Enterprise
functionality gated behind a paid subscription; writing to it in production is the exposure, not
just reading it). Unprepending/removing the Enterprise modules entirely — rejected; would require
editing `enterprise/` files or the injection initializer, violating Constitution Principle I far
more than a `custom/` prepend does.

## Decision: `ichatr_campaign_recipients` table + `Custom::CampaignRecipient` model shape

**Decision**: One new table, columns/indexes exactly as specified in `spec72.md` (see
`data-model.md`), modeled directly on `enterprise/app/models/campaign_recipient.rb` (verified: same
`belongs_to` set, same `mark_sent!`/`mark_skipped!`/`mark_failed!`/`update_from_whatsapp_status!`
method shapes, same `with_lock` + `status_downgrade?` no-downgrade guard), extended with:
- One more enum state, `replied`, ranked above `read` and below the terminal `failed` (mirrors the
  Enterprise `queued(0) < skipped(1) < sent(2) < delivered(3) < read(4) < failed(5)` ordering with
  `replied` inserted between `read` and `failed`: `queued(0) < skipped(1) < sent(2) < delivered(3)
  < read(4) < replied(5) < failed(6)`).
- Five reply-correlation columns (`reply_source_id`, `reply_type`, `reply_label`,
  `campaign_message_id`, `replied_at`) the Enterprise model has no equivalent of.

**Rationale**: Reusing Enterprise's exact method/lifecycle shape satisfies Constitution Principle
III (established convention — the "convention" here is this codebase's own precedent for this
exact problem, one model transaction-safe status lifecycle) while keeping the model fully
independent (no shared code, no shared table, `Custom::` namespaced to avoid the Zeitwerk constant
collision with the top-level `CampaignRecipient` Enterprise already defines).

**Alternatives considered**: Storing reply correlation as JSON on the existing `Conversation`
instead of dedicated columns — rejected; the recipient row already exists as the natural
one-row-per-contact-per-send home for this data, and dedicated typed columns keep the analytics
queries (Part 2) simple aggregations rather than JSON extraction.

## Decision: `Campaign` extension via `include_mod_with`, not a direct core edit

**Decision**: `custom/app/models/custom/campaign.rb` defines `module Custom::Campaign`,
`extend ActiveSupport::Concern`, `included do has_many :ichatr_campaign_recipients, class_name:
'Custom::CampaignRecipient', dependent: :destroy end` — mirroring the existing
`custom/app/models/custom/concerns/account.rb`/`conversation.rb` pattern. No edit to
`app/models/campaign.rb`.

**Rationale**: `app/models/campaign.rb` already ends with `Campaign.include_mod_with('Campaign')`
(verified) — an extension point the codebase already wired for this exact class, simply not yet
used by any extension. The source design's "core, direct edit" framing predates this inspection;
Constitution Principle I requires the extension point be used once confirmed to exist, so this plan
upgrades that one detail rather than following it literally. Placed at `custom/app/models/custom/campaign.rb`
(not under `custom/concerns/`) because the wiring call passes the bare constant name `'Campaign'`,
not `'Concerns::Campaign'` — matching `include_mod_with`'s lookup (`Custom::Campaign`), the same
placement pattern already used for `custom/app/models/custom/automation_rule.rb` → `Custom::AutomationRule`.

**Alternatives considered**: None materially different — this is a mechanical extension-point
placement decision with only one correct answer given the existing wiring.

## Decision: Send path — `Custom::Whatsapp::OneoffCampaignService`

**Decision**: `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb`, prepended over
`Whatsapp::OneoffCampaignService`. `perform` mirrors the OSS method's validation calls
(`validate_campaign!`) then, per contact, `campaign.ichatr_campaign_recipients.find_or_create_by!(contact:)`
(setting `account`/`inbox` on create, mirroring Enterprise's `create_recipients`), renders the
liquid template params and message content (reusing `Whatsapp::LiquidTemplateProcessorService` and
`Liquid::CampaignTemplateService` exactly as both OSS and Enterprise already do), sends via
`Whatsapp::TemplateProcessorService`/`channel.send_template`, and records the outcome via
`mark_sent!`/`mark_skipped!`/`mark_failed!` on the recipient.

**Rationale**: This is a like-for-like reimplementation of Enterprise's already-working
`perform`/`process_recipient`/`send_whatsapp_template_message` flow (verified line-by-line against
`enterprise/app/services/enterprise/whatsapp/oneoff_campaign_service.rb`), swapped onto
`Custom::CampaignRecipient` instead of the Enterprise model — there is no reason to design a
different flow when the reference implementation already handles liquid-variable-blank skips,
missing-phone skips, and provider-error failures correctly.

**Alternatives considered**: None — Enterprise's implementation is the correct reference shape;
the only change is which model it writes to.

## Decision: Inbound path — `process_statuses` duplication (documented exception)

**Decision**: `Custom::Whatsapp::IncomingMessageBaseService#process_statuses` duplicates the OSS
method's body (`find_message_by_source_id`, `update_whatsapp_identifiers_from_status`,
`update_message_with_status` — all pre-existing helper methods on the class, called, not
redefined) and, in addition, looks up `Custom::CampaignRecipient.find_by(account_id:, inbox_id:,
source_id: status[:id])` and calls `recipient.update_from_whatsapp_status!(status)` when found.

**Rationale**: See Complexity Tracking in plan.md — `Enterprise::Whatsapp::IncomingMessageBaseService#process_statuses`
calls `super`, so a `Custom` override that also calls `super` would still route through the
Enterprise module. This is the one place in the feature where full duplication (not delegation) is
required to achieve the replace-not-augment goal.

**Alternatives considered**: Calling `super` and accepting Enterprise's writes to the unused
`campaign_recipients` table as a harmless no-op — rejected per the source design's explicit
constraint that Enterprise code must not execute in production at all, not just "have its output
ignored."

## Decision: Inbound path — reply correlation hook point and query shape

**Decision**: Override `set_conversation` (private method on `Whatsapp::IncomingMessageBaseService`,
called from `process_messages` before conversation creation), calling `super` normally (Enterprise's
`IncomingMessageBaseService` module — verified — only defines `process_statuses`, never touches
`set_conversation`/`process_messages`, so `super` here reaches the OSS implementation directly).
After `super` returns, if `@conversation` was newly created (its `id` was `nil` before the call —
compared via a local flag set before invoking `super`, since `ActiveRecord::Base#new_record?`
already reflects post-save state by the time control returns), run correlation:

1. `context_id = messages_data.first['context']&.[]('id')` — the exact same extraction expression
   already used by `process_in_reply_to` (`incoming_message_service_helpers.rb:80`,
   `message['context']&.[]('id')`), read directly here because `set_conversation` runs *before*
   `process_in_reply_to` in the existing `process_messages` → `create_messages` flow (verified: `set_conversation`
   is called first inside the `ActiveRecord::Base.transaction do` block, `create_messages` — which
   calls `process_in_reply_to` — after), so the `@in_reply_to_external_id` ivar isn't populated yet
   at this point.
2. Exact match: `Custom::CampaignRecipient.find_by(account_id:, inbox_id:, source_id: context_id)`
   when `context_id` present — no time bound (matches FR-002's unbounded phrasing; a customer can
   quote-reply to an old campaign message at any time and it still correlates, deliberately, since
   the wamid match is unambiguous by construction).
3. Fallback (no `context_id`): `Custom::CampaignRecipient.where(account_id:, inbox_id:, contact_id:,
   status: [:sent, :delivered, :read], replied_at: nil).where('sent_at > ?', 72.hours.ago)` — if
   exactly one row, use it; if zero or more than one, do not attribute (FR-003).
4. On resolution: set `campaign_id` on the (still-unsaved-at-this-point, or just-saved —
   see below) conversation, update the recipient (`status: :replied` via the existing no-downgrade
   guard, `replied_at ||= Time.current`, `reply_source_id`, `reply_type`/`reply_label` derived from
   `message.dig(:interactive, :button_reply, :title) || message.dig(:button, :text)` — the same
   field paths `message_content` already reads, verified at `incoming_message_service_helpers.rb:32-34`
   — present → `quick_reply`, absent → `free_text`/`nil`).
5. Context backfill (once per recipient, `campaign_message_id.blank?`): build the outgoing
   `Message` (`content: recipient.message_content`, `sender: campaign.sender`, `source_id:
   recipient.source_id`, `created_at: recipient.sent_at`, `content_attributes: { campaign_context:
   true }`) and save it, then store its id on `recipient.campaign_message_id` — done inside
   `set_conversation`, before `super`'s caller (`process_messages`) goes on to build the actual
   inbound reply message, so it lands first.

**Rationale**: `set_conversation` is the one method that both (a) knows definitively whether a
*new* conversation is about to be created (vs. reusing an existing one — the exact FR-004
"attribution only at creation" boundary) and (b) runs early enough, inside the same transaction, to
set `campaign_id` before the conversation row is first persisted. Reusing the verified, already-existing
`context.id` and button-label extraction expressions (rather than re-deriving new parsing logic)
satisfies Constitution Principle II.

**Alternatives considered**: Hooking `create_messages`/`process_in_reply_to` instead (where
`@in_reply_to_external_id` is already populated) — rejected; by then `set_conversation` has already
run and, if it created a new conversation, that conversation is already persisted without
`campaign_id`, requiring a second `UPDATE` and losing the "backfilled message must be first" ordering
the source design explicitly requires. A separate `after_create` callback on `Conversation` — rejected;
`Conversation` has no visibility into the raw webhook payload (`context.id`, button labels), which
only exists in the service's local scope.

## Decision: Automation condition — zero `ConditionsFilterService` code change

**Decision**: Add one entry to `lib/filters/filter_keys.yml` under `conversations:`:
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
No change to `app/services/automation_rules/conditions_filter_service.rb`.

**Rationale**: Verified by inspection — `conversation_query_string`'s `'standard'` branch already
builds `" #{table_name}.#{attribute_key} #{filter_operator_value} #{query_operator} "` generically
for any `attribute_type: "standard"` entry (this is exactly how `team_id`/`inbox_id` already work,
confirmed at `lib/filters/filter_keys.yml` lines 31–46), and `conversations.campaign_id` is already
a real column. This is a materially smaller change than the precedent this fork already set for a
*different* automation condition in a prior phase (`campaign_referral_present`, added in commit
history for feature 031, which needed a special-cased branch in `message_query_string` because
`referral` is nested JSON, not a plain column) — that precedent does not apply here because
`campaign_id` needs no special-casing at all.

**Alternatives considered**: None — this is the established, already-generic path; introducing any
service-layer code here would be the actual violation of Constitution Principle II.

## Decision: Frontend automation condition wiring

**Decision**: Add one condition entry to `constants.js`'s `message_created.conditions` and
`conversation_created.conditions` arrays (`key: 'campaign_id', name: 'CAMPAIGN', inputType:
'search_select', filterOperators: OPERATOR_TYPES_3`), mirroring `team_id`'s entry exactly. Add one
entry to `automationHelper.js`'s `conditionFilterMaps`: `campaign_id: generateConditionOptions(campaigns)`.

**Rationale**: `generateConditionOptions` already exists and already understands the `Campaign`
list shape — confirmed by an existing (but currently orphaned) `campaigns:
generateConditionOptions(campaigns)` entry already present in `conditionFilterMaps` (added
upstream in commit `9eb861a3b7`, "Custom attributes in automations and refactor"), with no
`key: 'campaigns'` condition anywhere in `constants.js` that would ever select it. That entry can't
be reused as-is — `getConditionOptions` looks up the map by the condition's `key`, which must be
`'campaign_id'` to match both the backend column and the `filter_keys.yml` entry above, not
`'campaigns'` — so a new, correctly-keyed entry is added alongside it rather than renaming the
orphaned one (renaming it is out of scope: it's pre-existing upstream code this feature doesn't
own, and leaving it in place risks nothing since it's simply never selected).

**Alternatives considered**: Renaming the orphaned `campaigns:` entry to `campaign_id:` instead of
adding a new one — rejected; that entry is upstream code with no connection to this feature, and
touching it would be an unrelated, unrequested change (Constitution Principle II: don't refactor
surrounding code as a side effect).

## Decision: Analytics controller and route shape

**Decision**: `custom/app/controllers/api/v1/accounts/campaigns/recipients_controller.rb` →
`Api::V1::Accounts::Campaigns::RecipientsController`, three actions (`metrics`, `contacts`,
`reply_breakdown`), reusing `authorize @campaign, :show?` against the existing, Enterprise-independent
`CampaignPolicy` (verified: `app/policies/campaign_policy.rb`, `administrator?` gate, no Enterprise
override) — the same authorization `Enterprise::Api::V1::Accounts::Campaigns::AnalyticsController`
already uses, just against our own `Custom::CampaignRecipient` data. Routes added inside the
existing `resources :campaigns do ... end` block in `config/routes.rb`, unconditionally (no
`if ChatwootApp.enterprise?` guard, unlike the untouched sibling `analytics/*` routes right above
them).

**Rationale**: `Api::V1::Accounts::Campaigns::AnalyticsController` (Enterprise) is the exact
reference shape for this endpoint family — same `RESULTS_PER_PAGE`, same pagination response
envelope, same `filtered_recipients`/`recipient_payload` structure — reusing it satisfies
Constitution Principle III. `CampaignPolicy` has no Enterprise variant to check against (verified:
`find enterprise -iname` for a campaign policy override returns nothing), so no Dual-Tree Awareness
concern here.

**Alternatives considered**: A new dedicated policy class — rejected; `CampaignPolicy`'s existing
`show?` (administrator-only) is exactly the right gate for viewing a campaign's own recipient data,
no new permission concept is needed.

## Decision: Frontend data source repoint

**Decision**: In `app/javascript/dashboard/api/campaigns.js`, rename `analyticsMetrics(id)` →
`recipientsMetrics(id)` and `analyticsContacts(id, opts)` → `recipientsContacts(id, opts)`,
pointing both at `${this.url}/${id}/recipients/metrics` and `.../recipients/contacts`
respectively, and add `recipientsReplyBreakdown(id)` → `.../recipients/reply_breakdown`. Update the
two call sites in `WhatsAppCampaignAnalyticsPage.vue` (confirmed to be the only two consumers of
the old method names) to the new names, add a third fetch for the reply breakdown alongside the
existing `fetchMetrics`/`fetchDeliveries` pair (same request-id-guarded async pattern already used
by both), and render `CampaignReplyBreakdown` between `CampaignDeliveryBreakdown` and
`CampaignDeliveryTable` per the source design's stated placement.

**Rationale**: Matches the source design's "repointed" framing exactly, and the method rename
keeps the client honest about which backend routes it's calling now (avoids leaving a
`analyticsMetrics` method name pointing at a `recipients/*` URL, which would read as a copy-paste
leftover to a future reader). The existing untouched Enterprise `analytics/*` routes remain
reachable server-side but simply have no frontend caller anymore, exactly as the source design
specifies ("simply unreachable once the frontend stops calling it").

**Alternatives considered**: Keeping the old method names pointed at new URLs — rejected as a small
but real readability regression for no engineering-cost savings (a rename here is a one-line diff
per call site).

## Summary: Technical Context resolution

| Item | Resolution |
|---|---|
| Language/Version | Ruby (Rails, existing app version) backend; Vue 3 (Composition API, `<script setup>`) frontend — matches existing stack |
| Primary Dependencies | `attr_extras` (`pattr_initialize`), already used by both prepended services; no new external client |
| Storage | PostgreSQL — one new table, `ichatr_campaign_recipients`; no changes to any existing table (`conversations.campaign_id` already exists) |
| Testing | RSpec (backend), Vitest via `pnpm test` (frontend) — existing suites, per `CLAUDE.md` |
| Target Platform | Existing Chatwoot web app (Rails + Vue SPA), containerized dev stack per `CLAUDE.md` |
| Project Type | Web application (existing monolith: `app/`, `enterprise/`, `custom/`, `app/javascript/dashboard`) |
| Performance Goals | No new target; correlation adds at most one indexed lookup/small range query inline with existing webhook processing |
| Constraints | No Enterprise code path may execute without a subscription (drives the no-`super` decisions above); never guess an ambiguous attribution (FR-003) |
| Scale/Scope | Single-account-at-a-time WhatsApp campaign usage today (per spec Assumptions); correlation logic degrades safely regardless |
