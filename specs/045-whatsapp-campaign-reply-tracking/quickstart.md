# Quickstart: WhatsApp Campaign Reply Tracking

Validation guide for confirming the feature works end-to-end once implemented. Assumes the
container dev stack is already running (`docker compose up -d`) per `CLAUDE.md`, and that the
account under test has a connected WhatsApp Cloud inbox with the `whatsapp_campaign` feature flag
enabled and at least one approved message template with a quick-reply button.

## Prerequisites

- A WhatsApp Cloud inbox connected to an account with `feature_enabled?(:whatsapp_campaign)`.
- A one-off `Campaign` targeting that inbox, with `template_params` set for an approved template
  that has at least one quick-reply button, and an audience label with at least 2 contacts (one for
  the button-tap scenario, one for the free-text scenario).
- Ability to trigger inbound WhatsApp webhook payloads for the test — either a real WhatsApp Cloud
  sandbox number, or replaying a captured webhook JSON payload against the account's webhook
  endpoint in the dev stack (adjust `context.id`/`from` to match the test recipient's `source_id`/
  phone number).

## Scenario 1 — Send creates `Custom::CampaignRecipient` rows, not Enterprise ones (Acceptance criteria, FR-001)

1. Trigger the campaign send (`campaign.trigger!` via Rails console, or the normal UI "Send now"
   flow).
2. **Expected** (Rails console):
   ```ruby
   campaign.ichatr_campaign_recipients.count   # == audience size
   CampaignRecipient.where(campaign_id: campaign.id).count   # == 0, always — Enterprise table untouched
   ```
3. Cross-check each `Custom::CampaignRecipient#status` matches the actual WhatsApp API outcome
   (`sent` with a `source_id` present for successful sends).

## Scenario 2 — Quick-reply button tap gets context + attribution (User Story 1, FR-002/FR-005/FR-006)

1. Have the test contact tap a quick-reply button on the received campaign message (or replay a
   webhook payload with `type: interactive`/`type: button` and `context.id` set to the recipient's
   `source_id`).
2. **Expected**: A new `Conversation` is created with `campaign_id` set to the campaign's id. Its
   first message is the backfilled campaign message (`content_attributes.campaign_context: true`,
   `content` matching `recipient.message_content`), followed by the customer's actual reply.
3. In the Rails console: `recipient.reload.status == 'replied'`, `recipient.reply_type ==
   'quick_reply'`, `recipient.reply_label` matches the tapped button's title, `recipient.replied_at`
   is set, `recipient.campaign_message_id` points at the backfilled message.

## Scenario 3 — Unambiguous free-text reply correlates (User Story 1 scenario 2, FR-003)

1. With exactly one `Custom::CampaignRecipient` for that contact in `[sent, delivered, read]` status
   and `sent_at` within the last 72h, have the contact send a plain free-text reply with no
   `context.id` (not a quoted reply).
2. **Expected**: Same as Scenario 2, except `recipient.reply_type == 'free_text'`,
   `recipient.reply_label` is `nil`.

## Scenario 4 — Ambiguous reply does not attribute (User Story 1 scenario 3, Edge case, SC-002)

1. Send the same campaign (or two different campaigns) to the same contact twice, both still
   `sent`/`delivered`/`read` and within the 72h window (or send the second immediately after the
   first).
2. Have the contact reply with free text and no `context.id`.
3. **Expected**: The new conversation has `campaign_id: nil`. Neither recipient row's `status`
   changes to `replied`. No error.

## Scenario 5 — Existing open conversation is never retagged (Edge case, FR-004)

1. With the test contact already in an open (non-resolved) conversation on the WhatsApp inbox, send
   them a new campaign, then have them reply.
2. **Expected**: `set_conversation` reuses the existing conversation (standard Chatwoot
   reuse-vs-`lock_to_single_conversation` behavior, unchanged by this feature). Its `campaign_id`
   remains whatever it was before (`nil`, if it was never previously attributed) — confirm via
   `conversation.reload.campaign_id` unchanged after the reply.

## Scenario 6 — Analytics page shows existing metrics plus new ones (User Story 2, FR-007/FR-008/FR-009)

1. Open Campaigns → the WhatsApp campaign's analytics page in the dashboard, after Scenarios 1–3
   have produced a mix of delivered/read/replied recipients.
2. **Expected**: The existing metric cards (Audience, Submitted, Delivered, Read, Failed, Skipped)
   show unchanged values, plus a new "Respostas únicas" card showing `replied` from the `metrics`
   response. The existing delivery breakdown/table are unchanged. Below them, a new "Button clicks"
   table lists each button label with its click count and click rate, plus a trailing "Outras
   respostas" row for the free-text reply from Scenario 3.
3. Confirm in browser dev tools that the page's network calls hit `.../recipients/metrics`,
   `.../recipients/contacts`, `.../recipients/reply_breakdown` — not `.../analytics/*`.

## Scenario 7 — Automation rule conditions on `campaign_id` (User Story 3, FR-010)

1. In Automation settings, create a rule on `Conversation created` (or `Message created`) with
   condition "Campaign" `is present`.
2. Trigger a campaign-attributed conversation (Scenario 2 or 3) and, separately, a normal
   non-campaign conversation on the same inbox.
3. **Expected**: The rule fires only for the campaign-attributed conversation (check the rule's
   configured action took effect, e.g. an added label). Repeat with "Campaign" `equal to` a specific
   campaign and confirm it fires only when the attributed campaign matches.

## Automated coverage

- `docker compose exec rails env -u FRONTEND_URL RAILS_ENV=test bundle exec rspec custom/spec/models/custom/campaign_recipient_spec.rb custom/spec/services/custom/whatsapp/oneoff_campaign_service_spec.rb custom/spec/services/custom/whatsapp/incoming_message_base_service_spec.rb custom/spec/requests/api/v1/accounts/campaigns/recipients_controller_spec.rb spec/services/automation_rules/conditions_filter_service_spec.rb`
- `docker compose exec vite pnpm test` (frontend — analytics page repoint, new reply-breakdown
  component, automation condition constants)
- Full pre-release gate per `CLAUDE.md` before shipping: RuboCop, ESLint, full RSpec, full `pnpm
  test`, `bin/sync-custom-module-hooks --check`/`--audit` — the latter matters here specifically
  since this feature adds MANIFEST-worthy hooks into `Whatsapp::OneoffCampaignService`/
  `Whatsapp::IncomingMessageBaseService`/`Campaign` that the sync audit should track going forward.
