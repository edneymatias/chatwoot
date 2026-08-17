# Phase 69: Opportunity Activity Log

**Status**: Design approved by user on 2026-08-17 — ready for an implementation plan.
**Depends on**: `custom/app/models/opportunity.rb` (existing Wisper event dispatch),
`OpportunityConversation`/`OpportunityStageChange` (existing linkage/history models), the
`opportunities` Super Admin feature flag (Phase 1), `AsyncDispatcher`'s unused
`prepend_mod_with('AsyncDispatcher')` hook, the core `message_created` Wisper event and
`Voice::CallMessageBuilder`'s `voice_call` message content type (existing Twilio/WhatsApp calling —
no sip-ari dependency, see §4.4), the existing `VoiceCallButton.vue` component (already used in
`ContactInfo.vue`).

## 1. Problem

Opportunities (`custom/app/models/opportunity.rb`) currently have no visible history. Agents
can't see when an opportunity was created, when it moved stages, who won/lost it, or which
conversations were opened for it over time. This spec adds a read-only audit/activity log per
Opportunity, surfaced from the Kanban board's conversation drawer.

## 2. Governing constraint

Per this fork's upstream-coupling-minimization principle: this feature must not require editing
any core (`app/`) or `enterprise/` file. Every piece of it — capture, storage, API, UI — lives
entirely in `custom/`, hooking into core through existing public interfaces (the Wisper event
dispatcher, and a `prepend_mod_with` extension point already present but unused in
`AsyncDispatcher`). The UI change is added to a drawer component our fork already owns
(`OpportunityConversationDrawer.vue`, introduced in `accf8eab8`), not to the upstream
`SidepanelSwitch.vue` (originates from core, `23a804512`/`ba8df900e`).

## 3. Data model

New table `ichatr_opportunity_activities`:

| column | type | notes |
|---|---|---|
| `id` | bigint | PK |
| `account_id` | bigint, FK, not null | tenant scoping |
| `opportunity_id` | bigint, FK, not null | |
| `event_type` | string, not null | see §4 for the full list |
| `actor_type` / `actor_id` | polymorphic, nullable | `User`, `AutomationRule`, or `nil` (system/automated) |
| `metadata` | jsonb, default `{}` | event-specific payload, flat shape, no per-type schema |
| `occurred_at` | datetime, not null | when the underlying event happened |
| `created_at` / `updated_at` | timestamps | |

Indexes: `[account_id, opportunity_id, occurred_at]` (the query the panel needs), plus
`[account_id]` alone for tenant-scoping consistency with sibling tables.

Model: `OpportunityActivity < ApplicationRecord`, `belongs_to :account`, `belongs_to :opportunity`,
`belongs_to :actor, polymorphic: true, optional: true`. `Opportunity` gains
`has_many :activities, class_name: 'OpportunityActivity', dependent: :destroy`.

`metadata` shape per `event_type`:

- `opportunity_created`: `{}`
- `opportunity_stage_changed`: `{ from_stage_id, to_stage_id }`
- `opportunity_won` / `opportunity_lost`: `{ from_stage_id, lost_reason, approximate? }` —
  `approximate: true` only present on backfilled rows (see §6); `lost_reason` populated once
  Scout Phase 01's `lost_reason` migration lands (`docs/kanban/backlog/scout/01-core-and-data-model/spec62.md`),
  absent/nullable until then.
- `conversation_opened`: `{ conversation_id, conversation_display_id, is_origin }`
- `call_placed`: `{ conversation_id, message_id, direction, provider, status }` — `direction`/
  `provider`/`status` copied verbatim from the `voice_call` message's
  `content_attributes['data']` (`call_direction`, `call_source`, `status`), see §4.4.

## 4. Event capture

All capture happens through the existing Wisper dispatcher and one model callback on a model this
fork already owns — no upstream code is touched.

### 4.1 `Custom::OpportunityActivityListener`

New file: `custom/app/listeners/custom/opportunity_activity_listener.rb`. A standalone `BaseListener`
subclass (not a `prepend_mod_with` module, since it doesn't extend an existing core listener — it's
a net-new listener instance).

Handles the five events `Opportunity` already dispatches via `Rails.configuration.dispatcher`
(`custom/app/models/opportunity.rb:142-178`), reusing their existing payloads directly:

- `opportunity_created`
- `opportunity_stage_changed` (payload includes `from_pipeline_stage_id`)
- `opportunity_won`
- `opportunity_lost`
- `opportunity_reopened`

Every one of these events already carries `performed_by: Current.executed_by || Current.user` in
its payload (`opportunity.rb:147`), which becomes `actor` on the created `OpportunityActivity` row
— `User`, `AutomationRule`, or `nil` (background job / no request context).

```ruby
class Custom::OpportunityActivityListener < BaseListener
  def opportunity_created(event)
    record(event, 'opportunity_created')
  end

  def opportunity_stage_changed(event)
    opportunity = event.data[:opportunity]
    record(event, 'opportunity_stage_changed',
           from_stage_id: event.data[:from_pipeline_stage_id], to_stage_id: opportunity.pipeline_stage_id)
  end

  def opportunity_won(event)
    record(event, 'opportunity_won', from_stage_id: event.data[:from_pipeline_stage_id])
  end

  def opportunity_lost(event)
    record(event, 'opportunity_lost', from_stage_id: event.data[:from_pipeline_stage_id])
  end

  def opportunity_reopened(event)
    record(event, 'opportunity_reopened')
  end

  private

  def record(event, event_type, metadata = {})
    opportunity = event.data[:opportunity]
    opportunity.activities.create!(
      account_id: opportunity.account_id,
      event_type: event_type,
      actor: event.data[:performed_by],
      metadata: metadata,
      occurred_at: event.timestamp
    )
  end
end
```

### 4.2 Dispatcher registration

New file: `custom/app/dispatchers/custom/async_dispatcher.rb`, extending `AsyncDispatcher#listeners`
via the `prepend_mod_with('AsyncDispatcher')` hook already present (unused) at the bottom of
`app/dispatchers/async_dispatcher.rb`:

```ruby
module Custom::AsyncDispatcher
  def listeners
    super + [Custom::OpportunityActivityListener.instance]
  end
end
```

This is the same module-extension convention already used for `Custom::AutomationRuleListener`
(prepended onto core `AutomationRuleListener`) — zero edits to the core dispatcher file.

### 4.3 Conversation-linkage capture

`OpportunityConversation` (`custom/app/models/opportunity_conversation.rb`, a model this fork
already owns) gets a direct `after_create` callback — no dispatcher indirection needed since
there's no existing broadcast to reuse for this join model:

```ruby
after_create :record_activity

private

def record_activity
  opportunity.activities.create!(
    account_id: account_id,
    event_type: 'conversation_opened',
    actor: Current.user,
    metadata: {
      conversation_id: conversation_id,
      conversation_display_id: conversation.display_id,
      is_origin: conversation_id == opportunity.origin_conversation_id
    },
    occurred_at: Time.current
  )
end
```

`actor` is `Current.user` when an agent manually links a conversation, `nil` when linkage happens
automatically (e.g. CTWA referral attribution running in a background job with no request
context).

### 4.4 Call capture

Every outbound/inbound call (Twilio or WhatsApp today; sip-ari transparently once it ships, since
it's designed to reuse the same message-based call representation per
`docs/kanban/backlog/sip-ari/spec48.md`) already creates a `Message` with
`content_type: 'voice_call'` inside the call's conversation
(`enterprise/app/services/voice/call_message_builder.rb`), which dispatches the existing core
`message_created` Wisper event. No telephony code — core or `enterprise/` — needs to change for
this; the event already fires today with the currently-live calling.

`Custom::OpportunityActivityListener` (§4.1) gains a `message_created` handler:

```ruby
def message_created(event)
  message = event.data[:message]
  return unless message.content_type == 'voice_call'

  conversation = message.conversation
  opportunity = conversation.account.opportunities
                            .joins(:opportunity_conversations)
                            .find_by(ichatr_opportunity_conversations: { conversation_id: conversation.id })
  return unless opportunity

  data = message.content_attributes.dig('data') || {}
  opportunity.activities.create!(
    account_id: opportunity.account_id,
    event_type: 'call_placed',
    actor: message.sender.is_a?(User) ? message.sender : nil,
    metadata: {
      conversation_id: conversation.id,
      message_id: message.id,
      direction: data['call_direction'],
      provider: data['call_source'],
      status: data['status']
    },
    occurred_at: message.created_at
  )
end
```

Only fires when the call's conversation is already linked to an Opportunity via
`OpportunityConversation` (the same linkage §4.3 maintains) — a call to a contact with no open
opportunity produces no activity row. `actor` is the calling `User` for outbound calls
(`message.sender`); inbound calls have the contact as `sender`, so `actor` is `nil` (system) for
those, consistent with the rest of this spec's actor semantics.

## 5. Backend API

New read-only route: `GET /api/v1/accounts/:account_id/opportunities/:opportunity_id/activities`.

- Controller: `Api::V1::Accounts::Opportunities::ActivitiesController`, `index` only — no
  create/update/destroy; the only writers are the listener and the `OpportunityConversation`
  callback in §4.
- Scoped via `Current.account.opportunities.find(params[:opportunity_id]).activities.order(occurred_at: :desc)`.
- Authorization mirrors the existing `opportunities_controller.rb` policy/account-scoping — no new
  permission concept.
- Response includes `event_type`, `metadata`, `occurred_at`, and a minimal `actor` payload
  (`{ type, id, name }`; `name` from `User#name` or `AutomationRule#name`; `nil` actor serializes
  as `{ type: 'system' }`).
- No pagination in v1 (reasonable per-opportunity volume) — load-more can be added later if usage
  proves it's needed; not in scope now.

## 6. One-time historical backfill

Applies only to opportunities that existed before this feature shipped. Going forward, §4's
capture layer is the permanent, precise event log — this backfill is a one-time gap-filler, not a
recurring concern, and nothing further needs to be built to prevent future features from facing
the same gap (see §6.4).

### 6.1 Fully accurate (existing historical data available)

- `opportunity_created`: one row per existing `Opportunity`, `occurred_at = opportunity.created_at`, `actor: nil`.
- `conversation_opened`: one row per existing `OpportunityConversation`, `occurred_at = record.created_at`, `actor: nil`.
- `opportunity_stage_changed`: one row per existing `OpportunityStageChange`
  (`ichatr_opportunity_stage_changes`, which already logs `from_stage_id`/`to_stage_id`/`created_at`),
  `occurred_at = record.created_at`, `actor: nil`.

### 6.2 Approximate (no reliable historical source)

- `opportunity_won` / `opportunity_lost`: one row per opportunity currently in a terminal state
  (`status: won` or `status: lost`), `occurred_at = opportunity.updated_at` (best available proxy,
  not exact), `actor: nil`, `metadata: { approximate: true }`. The frontend must render a visible
  caveat (e.g. "data aproximada" label/tooltip) wherever `metadata.approximate` is true — this must
  never be presented as an exact fact.

### 6.3 Not backfilled

- `opportunity_reopened`: skipped entirely for historical data. An open→won→reopened cycle that
  happened before this feature existed has no derivable timestamp at all — not even
  `opportunity.updated_at` is a reasonable proxy, since the opportunity may have changed further
  after any such reopen. Only `opportunity_reopened` events captured live by §4 going forward will
  appear.

### 6.4 Why this doesn't recur

The backfill gap exists only because no event log existed before this feature. Once §4 ships, that
log is permanent and precise — any future feature needing "when did this move stages" or "who won
this" queries `OpportunityActivity` directly. No further design work is needed to prevent this
class of problem from recurring; it's inherent to being a one-time migration into a system that
previously had no history.

## 7. Frontend UI

**Trigger**: `OpportunityConversationDrawer.vue` (a component this fork owns) gets a new button
added to its existing top-left `ButtonGroup` (alongside Close/Expand), gated by
`isOpportunitiesFeatureEnabled` (same computed pattern already used in `ContactPanel.vue`).
Toggling it swaps the drawer's main content between the conversation view and the new activity
panel — replacing, not stacking, matching the existing Close/Expand interaction. The upstream
`SidepanelSwitch.vue` is not touched.

**New component**: `dashboard/components-next/Opportunities/OpportunityActivityLog.vue`

- Props: `opportunityId`.
- Fetches `GET .../opportunities/:id/activities` via a new Vuex action in the existing `custom/`
  opportunities store module.
- Renders a vertical read-only timeline: icon per `event_type`, human-readable copy built from
  `event_type` + `metadata` (e.g. "Oportunidade criada", "Movida de {from_stage} para {to_stage}",
  "Ganha"/"Perdida" with an "(aproximado)" badge when `metadata.approximate`, "Conversa
  aberta"/"Nova conversa vinculada"), actor name or "Sistema" fallback, relative timestamp (reusing
  existing date-formatting components already used elsewhere in the panel).
- No actions, no edit affordances — strictly read-only.

**i18n**: new keys in both `en.json` and `pt_BR.json`, synced together per project convention —
panel title, one label template per `event_type` (including `call_placed`), "System"/"Sistema"
actor fallback, the approximate-data caveat string.

**Dial button**: reuse the existing `VoiceCallButton.vue` component as-is (already used in
`ContactInfo.vue`; provider-agnostic, handles the multi-inbox picker and both Twilio/WhatsApp
today) — no new call-initiation logic. Added next to the existing activity-log toggle in
`OpportunityConversationDrawer.vue`'s top-left `ButtonGroup`, passed `:phone="opportunity.contact.phone_number"`
and `:contact-id="opportunity.contact_id"`. Same `isOpportunitiesFeatureEnabled` gate as the rest of
this feature; additionally hidden when the contact has no phone number, matching
`VoiceCallButton`'s own `shouldRender` guard.

## 8. Out of scope

- Task-creation events — explicitly deferred; the event-type list and `metadata` shape are designed
  to accept new event types later without a schema change, but no task integration work is included
  here.
- Pagination/load-more UI for the activity timeline.
- Any write/edit affordance on activity entries — the log is permanently read-only.
- Bulk backfill tooling beyond the one-time migration in §6 (no ongoing reconciliation job).
- Backfilling historical `call_placed` rows for calls made before this feature shipped — §6 only
  covers the four backfillable event types already listed there; past voice-call messages are not
  retroactively scanned.

## 9. Acceptance criteria

- Creating an Opportunity, moving it between stages, marking it won/lost/reopened, and
  linking/opening conversations for it each produce exactly one `OpportunityActivity` row with the
  correct `event_type`, `actor`, and `occurred_at`, with zero edits to any file under `app/` or
  `enterprise/`.
- Placing or receiving a call (Twilio or WhatsApp) on a conversation linked to an open Opportunity
  produces one `call_placed` activity row with correct `direction`/`provider`/`status`; a call on a
  conversation with no linked Opportunity produces no row.
- The dial button on `OpportunityConversationDrawer.vue` starts a call to the opportunity's contact
  using the existing `VoiceCallButton` flow, with no opportunity-specific call logic added.
- The activity toggle in `OpportunityConversationDrawer.vue` is hidden when the Opportunities
  feature is disabled for the account, and visible when enabled — independent of the Captain
  feature flag.
- The one-time backfill populates accurate `created`/`stage_changed`/`conversation_opened` rows for
  all pre-existing opportunities, and approximate `won`/`lost` rows (flagged `approximate: true`)
  for opportunities currently in a terminal state, with no `reopened` rows backfilled, and no
  historical `call_placed` rows.
- The activity panel is strictly read-only and renders correctly with no activities, one activity,
  and a long history.
