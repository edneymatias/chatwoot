# Implementation Plan: WhatsApp Campaign Reply Tracking

**Branch**: `045-whatsapp-campaign-reply-tracking` | **Date**: 2026-09-03 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/045-whatsapp-campaign-reply-tracking/spec.md`

## Summary

Replace the Enterprise-licensed `campaign_recipients` tracking (currently the sole owner of the
WhatsApp one-off campaign send/inbound flow via a `super`-less Enterprise `perform` override) with
a fork-owned equivalent under `custom/`, per the foundational decision already recorded in the
source design (`docs/kanban/ciclo 12/13-whatsapp-campaign-reply-tracking/spec72.md`): a new
`ichatr_campaign_recipients` table + `Custom::CampaignRecipient` model, a `Custom::` prepend of
`Whatsapp::OneoffCampaignService` that tracks per-recipient send outcome, and a `Custom::` prepend
of `Whatsapp::IncomingMessageBaseService` that (a) reimplements `process_statuses` without `super`
to bypass the Enterprise module and update our own table, and (b) hooks `set_conversation` to
correlate an inbound reply to the campaign send that prompted it — exact match via the WhatsApp
`context.id` (quoted-message wamid), or an unambiguous single-candidate fallback within a 72h
window, never a guess — attaching `campaign_id` to the new `Conversation` and backfilling the
original campaign message as the conversation's first message, once. On top of that: a new
`Api::V1::Accounts::Campaigns::RecipientsController` (unconditional route, no Enterprise gate)
serving the existing delivery metrics plus a unique-reply count and a per-button click breakdown,
consumed by the existing `WhatsAppCampaignAnalyticsPage.vue` repointed at it; and a `campaign_id`
automation condition added the same way `team_id`/`inbox_id` already work — a single `filter_keys.yml`
entry, since `conversations.campaign_id` is already a plain core column and
`ConditionsFilterService#conversation_query_string`'s generic `'standard'` branch already builds
`#{table_name}.#{attribute_key}` for any such column with zero service-code changes required.

## Technical Context

**Language/Version**: Ruby (Rails, existing app version) backend; Vue 3 (Composition API,
`<script setup>`) frontend — no new language/runtime introduced.

**Primary Dependencies**: `attr_extras` (`pattr_initialize`, already used by both
`Whatsapp::OneoffCampaignService` and `Whatsapp::IncomingMessageBaseService`); no new external
service client — the WhatsApp send/webhook plumbing (`Whatsapp::TemplateProcessorService`,
`Channel::Whatsapp#send_template`, the Cloud API webhook payload shape) is entirely existing,
untouched infrastructure this feature reads from and writes outcomes into.

**Storage**: PostgreSQL. One new table, `ichatr_campaign_recipients` (fork-prefixed, owned
entirely by `custom/`). No changes to any existing table — `conversations.campaign_id` (the column
this feature sets) already exists as a plain `belongs_to :campaign, optional: true` column on the
core `Conversation` model. The Enterprise `campaign_recipients` table/model/migration are left in
place, untouched, permanently unused per the foundational decision.

**Testing**: RSpec (`docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec
custom/spec/...`), Vitest via `docker compose exec vite pnpm test` — existing suites and
conventions per `CLAUDE.md`. Specs written only where they materially cover new logic (recipient
lifecycle/no-downgrade transitions, the two correlation paths — exact-match and
unambiguous-fallback — and their explicit non-attribution cases, the `process_statuses` duplication
called out below, the reply-breakdown click-rate math, the automation condition SQL), per the
"avoid writing specs unless explicitly asked" project guideline balanced against `CLAUDE.md`'s
existing Ruby/JS test commands being the standard verification path.

**Target Platform**: Existing Chatwoot web app (Rails + Vue SPA), containerized dev stack per
`CLAUDE.md`.

**Project Type**: Web application (existing monolith — `app/`, `enterprise/`, `custom/` fork-tree,
`app/javascript/dashboard`).

**Performance Goals**: No new target. Correlation runs synchronously inline with the existing
inbound-webhook request path (same transaction that already creates the conversation/message
today), adding at most one indexed lookup (`source_id` exact match) or one small indexed range
query (fallback, `contact_id`/`inbox_id`/`status`/`sent_at` scoped) — negligible relative to the
webhook processing already happening there.

**Constraints**: Must not leave any Enterprise code path executing in production without a paid
subscription — the entire point of the `Custom::` prepend-priority replacement (see Constitution
Check, Principle I) — and must never guess a campaign attribution when more than one candidate is
plausible (SC-002, FR-003).

**Scale/Scope**: 1 new migration/table, 1 new model, 2 new `Custom::` service prepends (one
per existing Enterprise-prepended service), 1 new controller + 3 new routes, 1 core-model
extension via the already-wired `Campaign.include_mod_with('Campaign')` hook, 1 `filter_keys.yml`
entry (zero `ConditionsFilterService` code change — confirmed by inspection, see research.md), 2
frontend `constants.js`/`automationHelper.js` entries, repointing 2 existing frontend API methods
plus adding 1 new one, 1 new Vue component (`CampaignReplyBreakdown.vue`) plus a small addition to
the existing metric-card grid, i18n additions across `automation.json` and `campaign.json` (en +
pt_BR only — no backend-rendered strings are introduced by this feature).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design below.*

### I. Upstream Compatibility First

- **`ichatr_campaign_recipients` table + `Custom::CampaignRecipient` model, `Custom::Whatsapp::OneoffCampaignService`,
  `Custom::Whatsapp::IncomingMessageBaseService`, `Api::V1::Accounts::Campaigns::RecipientsController`**:
  all new files under `custom/`, riding the existing `prepend_mod_with`/`ChatwootApp.extensions`
  priority order (`custom` prepended after `enterprise`, so it wins) — zero edits to any file
  under `enterprise/` or the two `app/services/whatsapp/*.rb` files it prepends. **PASS**.
- **`Campaign` gains `has_many :ichatr_campaign_recipients`**: the source design
  (`spec72.md`) describes this as a "core, direct edit," but `app/models/campaign.rb` already ends
  with `Campaign.include_mod_with('Campaign')` — an unused-by-this-feature-until-now extension
  point. Research (below) revises this to a new `custom/app/models/custom/campaign.rb` module
  (`Custom::Campaign`, `included do has_many ... end`) instead of editing the core file — the
  extension point already exists, so Principle I's "extension point over direct edit" applies with
  zero additional wiring cost. **PASS** (upgrade over the source design, not a deviation from it).
- **`lib/filters/filter_keys.yml`**: one small, additive entry (`campaign_id` under
  `conversations:`), mirroring the existing `team_id`/`inbox_id` entries exactly — shared,
  channel-agnostic automation infrastructure every condition in this codebase already extends the
  same way. **PASS**.
- **`config/routes.rb`**: one small, additive block inside the existing `resources :campaigns do
  ... end`, alongside (not replacing) the untouched, still-Enterprise-gated `analytics/*` routes.
  **PASS**.
- **`app/javascript/dashboard/routes/dashboard/settings/automation/constants.js`,
  `app/javascript/dashboard/helper/automationHelper.js`**: two small, additive entries each
  (one condition definition per trigger list, one `conditionFilterMaps` entry), mirroring the
  existing `team_id` entries exactly. **PASS**.
- **`app/javascript/dashboard/api/campaigns.js`**: existing fork-owned frontend file (not
  upstream core-critical path — it's the campaigns API client), edited to repoint two existing
  method bodies at the new backend routes and add one new method. No upstream file is restructured.
  **PASS**.

### II. Smallest Production-Ready Change

- Reuses `Api::V1::Accounts::Campaigns::AnalyticsController`'s exact metric-computation shape
  (`delivery_metrics`) and `CampaignPolicy`'s existing `show?` gate rather than inventing new
  authorization. Reuses the existing `message['context']&.[]('id')` extraction expression already
  used by `process_in_reply_to` (`app/services/whatsapp/incoming_message_service_helpers.rb:80`)
  rather than re-deriving context-id parsing. Reuses the existing
  `message.dig(:button, :text)` / `message.dig(:interactive, :button_reply, :title)` field paths
  already used by `message_content` (same helper file, lines 32–34) for button-tap label
  extraction. No speculative multi-campaign concurrency guard, no manual reattribution UI, no
  trend chart — all explicitly deferred per spec Out-of-scope/Assumptions. **PASS**.

### III. Adhere to Established Conventions

- `Custom::CampaignRecipient`'s status lifecycle (`mark_sent!`/`mark_skipped!`/`mark_failed!`,
  no-downgrade `update_from_whatsapp_status!`) is modeled directly on the Enterprise
  `CampaignRecipient` it replaces — same method shapes, same `with_lock` guard, extended with one
  more non-downgradable state (`replied`). RuboCop/ESLint/Tailwind/Composition API/i18n conventions
  apply unchanged; new Vue additions reuse `BaseTable`/`BaseTableRow`/`BaseTableCell` (already used
  by `CampaignDeliveryTable.vue`) and `CampaignMetricCard.vue` unmodified. New i18n keys added to
  `automation.json`/`campaign.json` in both `en` and `pt_BR` synchronously per `CLAUDE.md`. **PASS**.

### IV. Safe, Reversible Change Management

- The new table is purely additive; no existing table/column is altered or dropped. The Enterprise
  `campaign_recipients` table, model, job, and controller are left completely in place and
  untouched — inert, not deleted — so this change is trivially revertable (re-enabling the
  Enterprise prepends would restore prior behavior with no data migration needed either way, since
  the two tables are independent). **PASS**.

### V. Dual-Tree Awareness (OSS + Enterprise)

- This is the one feature in the fork whose entire purpose is to change how OSS and Enterprise
  interact at a specific extension point: `Custom::Whatsapp::OneoffCampaignService` and
  `Custom::Whatsapp::IncomingMessageBaseService` are prepended *after* (and therefore take priority
  over) the existing `Enterprise::Whatsapp::OneoffCampaignService`/`Enterprise::Whatsapp::IncomingMessageBaseService`
  modules, per `ChatwootApp.extensions` returning `['enterprise', 'custom']` and `prepend`'s
  front-of-ancestor-chain semantics (verified: both Enterprise modules exist exactly where the
  source design says, `enterprise/app/services/enterprise/whatsapp/{oneoff_campaign_service,incoming_message_base_service}.rb`).
  The one place this requires *not* calling `super` — `process_statuses` — is called out explicitly
  in research.md with the exact duplicated lines identified. Every other hook (`perform`,
  `set_conversation`) either fully replaces the OSS method (`perform`, matching how Enterprise
  itself already fully replaces it with no `super`) or calls `super` normally where Enterprise
  doesn't touch that method at all (`set_conversation` — confirmed by inspection: Enterprise's
  `IncomingMessageBaseService` module only defines `process_statuses`). **PASS**.

**Overall gate result**: PASS, with one recorded improvement over the source design (Campaign
extension via `include_mod_with` instead of a direct core edit) and one recorded, spec-acknowledged
exception (the `process_statuses` duplication, justified in Complexity Tracking below — already
flagged as a known, deliberate trade-off in the approved source design itself).

**Post-design re-check** (after Phase 0/1 artifacts below): unchanged — all five gates still PASS.
research.md's decisions (Campaign extension point, `set_conversation` hook shape, zero
`ConditionsFilterService` code change) were folded into the table above rather than discovered
afterward as a surprise, so no gate flipped.

## Project Structure

### Documentation (this feature)

```text
specs/045-whatsapp-campaign-reply-tracking/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md         # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/
│   └── campaign-recipients-api.md   # Phase 1 output (/speckit-plan command)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
# Backend — fork-owned tree (custom/), plus minimal wiring in shared config files
db/migrate/21260903100000_create_ichatr_campaign_recipients.rb  # new migration

custom/app/models/custom/campaign_recipient.rb        # new: Custom::CampaignRecipient
custom/app/models/custom/campaign.rb                  # new: Custom::Campaign (has_many :ichatr_campaign_recipients), via Campaign.include_mod_with('Campaign')

custom/app/services/custom/whatsapp/oneoff_campaign_service.rb        # new: Custom::Whatsapp::OneoffCampaignService (prepend, no super)
custom/app/services/custom/whatsapp/incoming_message_base_service.rb  # new: Custom::Whatsapp::IncomingMessageBaseService (prepend; process_statuses no super, set_conversation calls super)

custom/app/controllers/api/v1/accounts/campaigns/recipients_controller.rb  # new: Api::V1::Accounts::Campaigns::RecipientsController
config/routes.rb                                       # edit: 3 new routes inside existing `resources :campaigns do ... end`

custom/spec/models/custom/campaign_recipient_spec.rb                                        # new
custom/spec/services/custom/whatsapp/oneoff_campaign_service_spec.rb                        # new
custom/spec/services/custom/whatsapp/incoming_message_base_service_spec.rb                  # new
custom/spec/requests/api/v1/accounts/campaigns/recipients_controller_spec.rb                # new
spec/services/automation_rules/conditions_filter_service_spec.rb                            # edit: new context block for campaign_id, matching the campaign_referral_present precedent (feature 031) — not a new custom/spec/ file

lib/filters/filter_keys.yml                            # edit: campaign_id entry under conversations:

# Frontend — existing dashboard tree
app/javascript/dashboard/api/campaigns.js                                                 # edit: rename analyticsMetrics/analyticsContacts → recipientsMetrics/recipientsContacts (new URLs), add recipientsReplyBreakdown
app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue # edit: call renamed methods, add "replied" metric + fetch/render CampaignReplyBreakdown
app/javascript/dashboard/components-next/Campaigns/Pages/CampaignAnalyticsPage/CampaignReplyBreakdown.vue  # new
app/javascript/dashboard/routes/dashboard/settings/automation/constants.js                # edit: campaign_id condition entry in message_created + conversation_created
app/javascript/dashboard/helper/automationHelper.js                                       # edit: campaign_id: generateConditionOptions(campaigns) entry

app/javascript/dashboard/i18n/locale/en/automation.json                                   # edit: ATTRIBUTES.CAMPAIGN label
app/javascript/dashboard/i18n/locale/pt_BR/automation.json                                # edit: same, pt-BR
app/javascript/dashboard/i18n/locale/en/campaign.json                                      # edit: METRICS.REPLIED + REPLY_BREAKDOWN section
app/javascript/dashboard/i18n/locale/pt_BR/campaign.json                                   # edit: same, pt-BR
```

**Structure Decision**: No new top-level directories. All new backend logic lives under
`custom/app/**`, mirroring the Enterprise services it replaces file-for-file
(`custom/app/services/custom/whatsapp/*` mirrors `enterprise/app/services/enterprise/whatsapp/*`)
and the existing `custom/app/models/custom/*` namespacing convention already used for
extension-point modules (`Custom::AutomationRule`) and collision-avoidance models. Frontend changes
are entirely additive slices through the existing `dashboard/` tree (one new component beside its
three existing siblings, two small automation-config file edits mirroring `team_id`). The
Enterprise `campaign_recipients` table/model/job/controller/routes are untouched and out of scope
for deletion (per spec Out-of-scope).

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| `Custom::Whatsapp::IncomingMessageBaseService#process_statuses` duplicates ~15 lines of `Whatsapp::IncomingMessageBaseService#process_statuses`/`update_message_with_status` instead of calling `super` | `Enterprise::Whatsapp::IncomingMessageBaseService#process_statuses` calls `super` itself (see `enterprise/app/services/enterprise/whatsapp/incoming_message_base_service.rb`) — because Ruby method resolution walks the *entire* prepend chain in order, a `Custom` override that also calls `super` would still route through the Enterprise module sitting between it and the OSS base, defeating the entire purpose of replacing Enterprise's `CampaignRecipient` writes. There is no way to "skip one link" of a prepend chain from within it. | Leaving Enterprise's `process_statuses` in place and only reading its `CampaignRecipient` writes was rejected in the source design's foundational decision — Enterprise's `perform` already runs the full send flow unconditionally, so partial bypass (statuses only) would still leave Enterprise code executing on every send with no subscription, the exact exposure this phase exists to remove. The duplication is small, stable (it hasn't changed upstream in this fork's history), and mitigated by specs asserting the duplicated behavior stays correct — flagged explicitly in the approved source design itself, not discovered here. |
