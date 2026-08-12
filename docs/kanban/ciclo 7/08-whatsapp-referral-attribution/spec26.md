# Phase 26: WhatsApp Referral (Facebook/Instagram Ad) Attribution

**Status**: Part 1 (Evolution API patch) resolved and validated. Part 2 (attribution
feature design) approved by the user on 2026-08-11 — ready for an implementation plan.
Target: MVP shippable by the end of the current week.

**Depends on**: none functionally; reads data already captured by the existing WhatsApp
integrations (Cloud API and, as of the patch below, Evolution API). Part 2 also depends
on the existing `create_opportunity` automation action
(`custom/app/services/custom/automation_rules/action_service.rb`,
`custom/app/models/custom/automation_rule.rb`).

## Quick Preview

Click-to-WhatsApp (CTWA) ad campaigns land in Chatwoot via two different WhatsApp
numbers/inboxes: the official WhatsApp Cloud API and a self-hosted Evolution API
instance. Both now deliver the same structured `referral` object on the first inbound
message of a CTWA conversation (Part 1). Part 2 turns that raw signal into: fixed
campaign-attribution fields on the `Opportunity`, a background job that resolves
human-readable campaign/ad-set/ad names via the Meta Marketing API, a live UI update once
resolved, a boolean automation condition to trigger opportunity creation from campaign
messages without relying on the fragile suggested-message text, and a one-time backfill
for opportunities that already exist in production.

## Part 1 — Evolution API patch: resolved

### Original problem

Dens Odontologia (dental clinic) runs CTWA ad campaigns via a marketing agency. The only
signal the SDR had that a conversation came from a campaign was the pre-filled suggested
message text — and leads frequently edit or delete that text before sending, so
text-matching was never a reliable attribution mechanism. Goal: identify CTWA-originated
conversations unambiguously, then populate specific Opportunity fields from that data.

### Discovery: two WhatsApp numbers, two different code paths

The agency's campaigns run across **two different WhatsApp numbers/inboxes**, each
hitting a completely different Chatwoot channel:

1. **Official WhatsApp Cloud API** (`Channel::Whatsapp`) — already worked out of the box,
   no code changes needed.
2. **Evolution API** (self-hosted, wraps Baileys) connected via webhook integration — had
   a real, now-fixed gap (see below).

This was not known at the start of the investigation; discovered mid-way via live
production test traffic landing on different inboxes.

### Path 1 — Cloud API: already worked out of the box

Confirmed via a live production test message (id `1352475`, contact Gabriel Gonzales,
edited-text test) that WhatsApp Cloud API delivers a fully structured `referral` object on
the webhook payload, and Chatwoot already persists it verbatim:

- `Whatsapp::IncomingMessageServiceHelpers#referral_attributes` pulls `message[:referral]`
  from the webhook.
- `IncomingMessageBaseService` stores it into `content_attrs[:referral]` on the
  `Message`'s `content_attributes`.
- Observed real payload shape: `source_url`, `source_id` (the actual Meta ad ID),
  `source_type`, `headline`, `body`, `media_type`, `image_url`.

`source_id` — the field needed to resolve back to campaign/ad-set/ad via the Marketing
Graph API — was present here from the start. No patch needed for this number.

### Path 2 — Evolution API: root cause and patch

Evolution API (repo `evolution-foundation/evolution-api`, formerly
`EvolutionAPI/evolution-api` — same repo, org renamed) wraps Baileys
(`WhiskeySockets/Baileys`) and forwards messages to Chatwoot via its own Chatwoot
integration service.

**Root cause was Evolution-side, not Baileys-side.** WhatsApp's protobuf
`ContextInfo.ExternalAdReplyInfo` (declared in Baileys' `WAProto/WAProto.proto`) already
includes `sourceId` (field 8) alongside `title`, `body`, `mediaType`, `thumbnailUrl`,
`mediaUrl`, `thumbnail`, `sourceType`, `sourceUrl`. Baileys decodes all of these fields
automatically via standard protobuf decoding — Baileys never needed a fix.

Evolution's own code simply didn't read the field. In
`src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts`:

- `getAdsMessage(msg)` (~line 1722–1741) extracted only `title`, `body`, `thumbnailUrl`,
  `sourceUrl` from `contextInfo.externalAdReply` — omitted `sourceId`/`sourceType`.
- The call site (~line 2034) and send logic (~line 2208–2260) rendered the ad data into a
  caption string concatenated onto the **same message** as the lead's own text, sent to
  Chatwoot as an image attachment — free text, not structured data.
- Reference implementation used to validate the target shape: `clairton/unoapi-cloud`'s
  `src/services/transformer.ts`, which already extracts `externalAdReply.sourceId` →
  `referral.source_id`.

**Patch (completed, 2 days of work, tested)**: `getAdsMessage` now also captures
`sourceId`/`sourceType`, and the referral data is stored structurally (mirroring Cloud
API's shape) instead of only being concatenated into the caption text. Both numbers now
deliver an equivalent, normalized `content_attributes.referral` object:

```
content_attributes.referral = {
  source_id: "120246899522180701",
  source_type: "ad",
  source_url: "https://fb.me/3nQ212CeX",
  headline: "Você Merece o Melhor Tratamento! ⭐",
  body: "Por que marcar uma consulta...",
  media_type: "image", # example
  image_url: "https://scontent.fbfh3-3.fna.fbcdn.net/...",
}
```

This patch lives in the user's own fork/deployment of Evolution API — not in this repo.
Whether it gets upstreamed to `evolution-foundation/evolution-api` is undecided and not a
blocker; the user needs to be able to run the patched code in their own environment
regardless of upstream acceptance.

### Empirical validation: does editing/clearing the suggested text break attribution?

This was the central open question during the investigation — the user's literal concern
was: lead clicks the ad, WhatsApp opens with a suggested message, and *before sending* the
lead edits or deletes that suggested text. Does that wipe the ad metadata too?

Tested live against real ad campaigns (Meta Ads Manager Ad Preview, not
scripted/automated clicks — avoids invalid-traffic/click-fraud policy risk) with three
real test sends, SQL run directly by the user against production and pasted back for
analysis:

1. **Test 1** — Cloud API number, text edited before sending (message id `1352475`,
   contact Gabriel Gonzales). Referral metadata present and intact.
2. **Test 2** — Evolution/WhatsApp Business number, text sent unedited (message id
   `1352606`, same contact, via Instagram-sourced ad). Ad-card metadata present.
3. **Test 3** — Evolution/WhatsApp Business number, text replaced entirely with
   "Abobrinha" before sending (message id `1352618`). Ad-card metadata still present.

**Conclusion: metadata survives text edits on both numbers.** The attribution signal is
tied to the ad-click origin itself (`ctwa_clid`-style tracking baked into the click, not
the literal message body), not to whatever text the lead actually sends. This fully
de-risks the design that follows in Part 2 — editing/clearing the suggested message is not
a failure mode to design around.

### Architectural caveat: post-send deletion

Separately investigated: what happens if a lead deletes the message *after* sending it?
Chatwoot represents a deleted message by overwriting `content` and setting
`content_attributes.deleted = true` — this destroys whatever was in that message. On the
Cloud API path this is a non-issue: `referral` lives in `content_attributes` on the lead's
own first message, and that message is extremely unlikely to be the one deleted in
practice. The Evolution patch also stores referral data structurally on that same first
inbound message (same shape as Cloud API), so both paths now share this same residual risk
profile rather than Evolution being uniquely fragile. No genuine occurrence of this was
found in production data. Treated as an accepted, documented residual risk, not something
actively designed around.

## Part 2 — Attribution feature design (approved)

With both numbers now delivering normalized referral data, this section defines what to
build on top of it. The design intentionally trades scope for speed: it's the smallest
version of the feature that's genuinely useful, sized to ship within the current week.
Goals not covered here (multi-field automation filters, per-inbox capture toggles,
conversation-level attribution) are listed under **Out of scope**, not silently dropped —
they were considered and deliberately deferred past v1.

### Goals (v1)

- Show campaign attribution (platform icon immediately, campaign/ad-set/ad name once
  resolved) directly on the Opportunity card, for opportunities created from a campaign
  message.
- Resolve `source_id` into human-readable campaign/ad-set/ad names via the Meta Marketing
  Graph API, without blocking Opportunity creation or the automation that creates it.
- Let an Automation Rule trigger Opportunity creation from the mere *presence* of campaign
  referral data on the triggering message, replacing reliance on the fragile
  pre-filled/suggested opening message text.
- Backfill existing (pre-feature) opportunities in production so historical data isn't
  permanently missing attribution.
- Gate all of this behind a master toggle plus a Meta OAuth connection scoped for the
  Marketing API (`ads_read`) — separate from the existing WhatsApp Cloud embedded-signup
  Meta app config, though it may reuse the same underlying Meta App/credentials.

### Data model: fixed columns on Opportunity

Campaign attribution is a general-purpose, flow-independent attribute of an
Opportunity — like `value` (already a dedicated column) — not something scoped to a
specific pipeline/business flow the way `PipelineClosingRequiredField` or stage
configuration is. It is stored as **new dedicated columns** on `ichatr_opportunities`, not
folded into the existing `custom_attributes` jsonb bucket:

| Column | Type | Populated |
|---|---|---|
| `campaign_source_id` | `string` | synchronously, at Opportunity creation |
| `campaign_source_url` | `string` | synchronously, at Opportunity creation |
| `campaign_platform` | `string` (`facebook`/`instagram`) | synchronously, at Opportunity creation |
| `campaign_name` | `string` | asynchronously, by the resolution job |
| `campaign_adset_name` | `string` | asynchronously, by the resolution job |
| `campaign_ad_name` | `string` | asynchronously, by the resolution job |
| `campaign_resolution_status` | `string` enum: `not_applicable` / `pending` / `resolved` / `failed` | both stages |

`campaign_platform` is derived from `source_url`'s host: contains `instagram` →
`instagram`, otherwise `facebook` (covers both `facebook.com` and the `fb.me` short-link
domain observed in Part 1's real payloads).

`campaign_resolution_status` starts `not_applicable` for opportunities with no referral
data at all (the vast majority, unrelated to campaigns). It becomes `pending` the moment
the synchronous fields are populated, `resolved` once the async job succeeds, or `failed`
if the job exhausts retries (e.g. the ad/campaign was deleted, or the token was revoked) —
this drives the card's "campaign data loading" vs. resolved-name vs. no-indicator states.

A migration adds these seven columns (with a partial index on
`campaign_resolution_status` for the job's own polling query, e.g.
`WHERE campaign_resolution_status = 'pending'`).

### Backend — synchronous capture

No new listener and no Conversation-level storage layer. The flow is simply
`message → opportunity`: the existing `create_opportunity` automation action
(`custom/app/services/custom/automation_rules/action_service.rb`) is the single place that
creates an Opportunity from a triggering message, so it's also the single place that reads
`message.content_attributes['referral']` and populates the three synchronous columns plus
sets `campaign_resolution_status` (`pending` if `referral` present, `not_applicable`
otherwise) at creation time. If the master toggle is off or Meta isn't authenticated, the
columns are still populated from the raw message data (capture has no external
dependency) — only the async resolution stage (below) is gated.

### Backend — async resolution job

A background job resolves `campaign_name`/`campaign_adset_name`/`campaign_ad_name` via the
Meta Marketing Graph API (`GET /{ad_id}?fields=name,adset{id,name},campaign{id,name}`),
enqueued right after synchronous capture, on the existing `low` priority Sidekiq queue
(already used by `DataImports::Intercom`'s equivalent low-priority import work,
`config/sidekiq.yml`). Runs only when the master toggle is on and Meta Marketing API auth
is configured for the account; otherwise the opportunity stays `pending` until an admin
enables it (re-enqueued at that point, or picked up by re-running the backfill task below).

Two pieces are reused from existing patterns in this codebase rather than built from
scratch:

- **Proactive pacing** — a `Meta::RateLimiter`, modeled directly on
  `app/services/auto_assignment/rate_limiter.rb`'s Redis sliding-window counter
  (`within_limit?`/`track_assignment`), checked before every Graph API call so the job
  self-throttles instead of relying purely on reacting to 429s.
- **Reactive backoff** — a `Meta::RateLimitError` (capturing the `Retry-After` /
  `X-Business-Use-Case-Usage` response headers) wired via ActiveJob's native `retry_on`,
  modeled on `app/jobs/data_imports/intercom/base_job.rb`. If the proactive limiter is
  wrong or Meta throttles anyway, the job retries with backoff instead of failing —
  matching the "stays in queue until processed" behavior discussed.

On success: campaign/ad-set/ad names are saved and `campaign_resolution_status` becomes
`resolved`. On terminal failure (retries exhausted): `campaign_resolution_status` becomes
`failed`, and the raw `campaign_source_id`/`campaign_platform` remain visible as a
fallback — no case where a resolvable opportunity silently shows nothing.

### Backend — realtime UI update

Small, included-in-scope refactor: today `custom/app/models/opportunity.rb`'s
`after_commit :broadcast_opportunity_updated` calls `ActionCableBroadcastJob.perform_later`
directly, bypassing this app's standard event pattern
(`Rails.configuration.dispatcher.dispatch` → `SyncDispatcher` →
`ActionCableListener`). Both `ActionCableListener` (`app/listeners/action_cable_listener.rb`)
and `AutomationRule` (used by this fork's own `create_opportunity` action) already carry a
trailing `prepend_mod_with('X')` call — an extension point built into Chatwoot core for the
Enterprise overlay, which this fork's `custom/` tree already reuses elsewhere. Adopting it
here needs **zero core file changes**, only new files under `custom/`:

- `custom/app/models/opportunity.rb`: `broadcast_opportunity_updated` calls
  `Rails.configuration.dispatcher.dispatch('opportunity_updated', Time.zone.now, { opportunity: self })`
  instead of calling the broadcast job directly.
- New `custom/app/listeners/custom/action_cable_listener.rb` defining
  `Custom::ActionCableListener#opportunity_updated`, reusing the existing private
  `broadcast`/`user_tokens` helpers already on `ActionCableListener` to broadcast to
  `"account_#{account_id}"` (the same account-wide stream every logged-in agent already
  subscribes to via `app/channels/room_channel.rb:29`).

This is worth doing now because the resolution job (above) needs to fire this same event
when it finishes — better to have both call sites go through the standard pattern than
have the job either duplicate the ad-hoc direct-broadcast code or be the only caller using
the "correct" path while the model keeps the old one.

The frontend side needs **no changes** — `app/javascript/dashboard/helper/actionCable.js`
already listens for `opportunity_updated` and dispatches `opportunities/updateOpportunity`
(added in a previous phase, commit `0eab699cf`); it already works end-to-end today and
will keep working unchanged after this refactor.

### Backend/Frontend — "mensagem de campanha" automation condition

A new boolean automation condition, evaluating to true when the triggering message carries
`content_attributes.referral`. **v1 scope is a pure boolean presence check — no other
campaign field (platform, source_id, campaign_name, etc.) is exposed as a filter.** This
was an explicit scope decision to keep the MVP achievable this week; broader filtering is
listed under Out of scope.

This is **not** free the way conversation/contact custom-attribute filters are — `referral`
is raw JSON on `Message.content_attributes`, not an account-defined
`CustomAttributeDefinition`, so it doesn't ride the existing dynamic
`custom_attribute_query` path. It requires small, additive touches in a few places (all
purely additive — a new attribute key alongside existing ones, no existing behavior
changed):

- `lib/filters/filter_keys.yml`: a new `campaign_referral_present` entry under `messages:`,
  boolean type, `equal_to`/`not_equal_to` operators — needed for
  `AutomationRules::ConditionValidationService` to accept the condition as valid.
- `app/services/automation_rules/conditions_filter_service.rb`'s `message_query_string`:
  one new case building a `messages.content_attributes -> 'referral' IS NOT NULL`-style
  presence query when `attribute_key == 'campaign_referral_present'` — mirroring how
  `private_note`/`content` already get attribute-key-specific handling in that same method.
- `app/javascript/dashboard/routes/dashboard/settings/automation/constants.js`: one new
  entry in `AUTOMATIONS.message_created.conditions`, mirroring the existing `private_note`
  entry (`inputType: 'search_select'`, `filterOperators: OPERATOR_TYPES_1`).
- `app/javascript/dashboard/helper/automationHelper.js`'s `conditionFilterMaps`: one new
  `campaign_referral_present: booleanFilterOptions` entry, mirroring `private_note`.
- i18n labels for the new condition name, in both `en.json` and `pt_BR.json`.

None of these touch a class that already has a `custom/`-reroutable extension point (unlike
the broadcast refactor above), so this is the one piece of the design that genuinely edits
a handful of core files — kept intentionally small and purely additive.

### Backend — backfill for existing production data

A rake task (`lib/tasks/campaign_attribution.rake`, task
`campaign_attribution:backfill`), run manually via `rails runner`/`rake` after this feature
deploys and the master toggle + Meta auth are configured — not part of any automatic
deploy/migration step, since scanning production data and enqueueing external-API jobs
inside a schema migration would be unsafe.

- **Idempotent scope**: `Opportunity.where(campaign_resolution_status: nil).where.not(origin_conversation_id: nil)`,
  iterated via `find_each` in batches — re-running the task after an interruption simply
  skips everything already processed.
- **Per-account gate**: skips opportunities belonging to accounts where the master toggle
  isn't enabled, rather than assuming a single-tenant deploy.
- **Per opportunity**: looks up the origin conversation's inbound message carrying
  `content_attributes.referral`, and reuses the exact same synchronous-capture code as the
  real-time path (no duplicated extraction logic) to populate the three sync columns.
- **Async enqueueing**: for each opportunity where sync data was found, enqueues the same
  resolution job used by the real-time path — the job's own rate limiter naturally paces
  the backfill's calls to the Meta API, so the task itself needs no throttling logic of its
  own.
- **Visibility**: logs a final count of processed / skipped-no-referral / skipped-gated
  opportunities, since this is a manually-triggered, one-time operation the user will want
  to confirm the result of.

### Settings / gating

A master toggle ("Ativar rastreio de campanhas do Meta") plus a Meta OAuth connection
scoped for Marketing API access (`ads_read`), configured as a **separate surface** from the
existing WhatsApp Cloud embedded-signup Meta app config (Super Admin) — may reuse the same
underlying Meta App/credentials, but must not share UI/state with the inbox-connection
flow. Synchronous capture works without this (it only reads data already on the message);
the toggle + auth gate the async resolution job and the backfill task specifically. Exact
settings-screen placement (e.g. a new tab alongside Pipeline Stages settings) is an
implementation-plan-level detail, not re-litigated here.

### Out of scope (v1)

- Exposing `campaign_platform`, `campaign_source_id`, `campaign_name`,
  `campaign_adset_name`, or `campaign_ad_name` as automation filter conditions — only the
  boolean "referral present" check ships in v1. Revisit once there's a concrete need (e.g.
  "different pipeline per campaign" would need at least `campaign_source_id`/campaign-level
  filtering, and `campaign_name`-based filtering would need a new Opportunity-centric
  automation trigger, since no such trigger exists today — automation triggers today are
  strictly Conversation/Message-centric).
- Any Conversation-level storage of referral data (previously drafted in an earlier version
  of this document, superseded by this design) — the flow is `message → opportunity`
  directly, no intermediate normalization layer.
- Per-inbox capture toggle (Cloud vs. Evolution/WhatsApp Business) — capture is unconditional
  wherever `referral` is present on the triggering message; there's no per-inbox opt-out in
  v1.
- Multi-account SaaS token management (per-account Meta app review for `ads_read` against
  other people's ad accounts) — explicitly deferred by the user, not a blocker for this
  design.
- A dedicated UI for manually retrying a `failed` resolution — v1 shows the `failed` state
  with the raw source id/platform as fallback; a manual retry action can be added later if
  it turns out to matter in practice.

### Constraints observed during this investigation (for future reference)

- Evolution API and Baileys are external repos, not part of this codebase — the patch
  lives in a separate fork/deployment, not in this repo.
- Live testing against real Meta ad campaigns must go through Ads Manager's **Ad Preview**
  tool (Campaigns → Ads → select ad → Preview panel), not scripted/automated clicks —
  avoids invalid-traffic/click-fraud policy risk, even against one's own campaign.
- Per the user's explicit workflow preference during the investigation: no direct
  production DB/VPS access was used — SQL was provided, the user ran it against production
  themselves and pasted the output back for analysis.
- This feature ships to an account already live in production (real CRM usage) — the
  backfill task and the resolution job's rate limiting were both designed with that
  constraint front of mind: no blocking operations, no risk of exceeding Meta's API limits
  against a live ad account.
