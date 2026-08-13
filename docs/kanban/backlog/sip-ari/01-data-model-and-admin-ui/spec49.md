# Phase 01 — Data Model & Admin UI

**Master doc**: `docs/kanban/backlog/sip-ari/spec48.md` §2, §5

## Goal

Land the `Channel::SipAri` model, the `Call.provider` enum value, and the inbox setup wizard —
enough to create and configure a SIP/ARI inbox end to end, with no call-routing behavior yet.
This phase is the foundation every other phase depends on.

## Scope

- New model `Channel::SipAri` (`app/models/channel/sip_ari.rb` or `enterprise/` if voice stays
  Enterprise-gated — confirm against how `Channel::Twilio` is namespaced today):
  - `include Channelable`
  - `encrypts :extension_secret, :ari_password`
  - `validates :sip_server, :extension, :extension_secret, :ari_base_url, :ari_username, :ari_password, presence: true`
- New migration: `channel_sip_aris` table + standard `Inbox`/`Channelable` polymorphic wiring
  (mirror the existing `Channel::Twilio` migration shape).
- Extend `Call.provider` enum: `enum :provider, { twilio: 0, whatsapp: 1, sip_ari: 2 }`
  (`enterprise/app/models/call.rb`).
- New "SIP" option in the inbox-creation channel picker, backed by `Channel::SipAri`, mirroring
  the Twilio setup wizard. Fields:
  - SIP server host
  - WSS port/URI
  - Extension (AOR)
  - Extension secret/password
  - ARI base URL, ARI username, ARI password (server-side only, encrypted, never sent to frontend)
  - Display name / phone number label
- Live ARI connectivity check on save: `GET /ari/asterisk/info` against the submitted ARI
  credentials before persisting — fail fast with a clear validation error instead of silently
  saving broken credentials. No live SIP-registration check at save time (that's async, added in
  Phase 05).
- Fix `Api::V1::Accounts::Contacts::CallsController#voice_inbox` — currently hardcodes
  `channel_type: 'Channel::TwilioSms'` when looking up the voice inbox for the contact-panel call
  button. Change to accept `Channel::SipAri` too (either an array of channel types, or drop the
  `channel_type` filter and rely on `voice_enabled?` alone). Without this, outbound calling from
  the contact panel silently breaks for SIP/ARI inboxes even after later phases ship.

## Out of scope (deferred to later phases)

- No per-agent extension/credential management — single shared-extension model only.
- No actual call routing, ARI bridge service, or frontend SIP client — this phase only makes the
  inbox creatable and validated.

## Acceptance criteria

- A SIP/ARI inbox can be created via the dashboard with all fields above, with encrypted secrets
  at rest.
- Saving with bad ARI credentials fails with a clear inline error (no silent save).
- `Call.provider` accepts `sip_ari` without breaking existing `twilio`/`whatsapp` records.
- Contact-panel outbound call button correctly resolves a `Channel::SipAri` voice inbox (spec
  test: create a contact-call request against a SIP/ARI inbox, assert it's found).
