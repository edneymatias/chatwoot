# Phase 26: WhatsApp Referral (Facebook/Instagram Ad) Attribution — feasibility study

**Status**: placeholder — pending brainstorm session (research/feasibility
phase, not committed to an implementation yet)
**Depends on**: none functionally; reads data already captured by the
existing WhatsApp Cloud integration

## Quick Preview

WhatsApp's Cloud API already sends a `referral` object on the first
inbound message of a "click-to-WhatsApp" conversation started from a
Facebook/Instagram ad (source ad/post id, source URL, headline, body,
media type/URL, CTWA click id). Chatwoot already captures this today:
`Whatsapp::IncomingMessageServiceHelpers#referral_attributes` pulls
`message[:referral]` from the webhook payload and
`IncomingMessageBaseService` stores it as-is into
`content_attrs[:referral]` on the `Message` record's
`content_attributes` — but that's the entire extent of what exists. The
raw hash is persisted and never touched again: not normalized into a
predictable schema, not surfaced anywhere in the frontend (conversation
sidebar, contact panel), not copied onto the `Conversation` or `Contact`
for cross-message reuse, and not aggregated into any report.

This phase is explicitly a **feasibility/design study**, not committed
implementation — the goal is to figure out what "reading referral data"
should mean product-wise before building it:
- Surfacing it per-conversation (e.g. a "veio de anúncio: <headline>"
  badge/panel in the conversation view) — lowest-effort, data already
  exists, closest to a pure UI phase.
- Attribution reporting (e.g. "opportunities/conversations originated
  from ad X", tying `referral.source_id`/`ctwa_clid` through to
  Opportunity creation and eventually to Phase 21's funnel report) —
  meaningfully bigger scope, needs a place to persist normalized
  referral data (new column/table vs. reading `content_attributes` live
  each time) and a decision on which record it belongs to (message vs.
  conversation vs. contact, since a contact could have multiple
  ad-originated conversations over time).

Open questions for the brainstorm:
- Confirm the actual field set Meta sends today (may differ from the
  stored raw hash across API versions) — worth a quick reference check
  against WhatsApp Cloud API docs before designing a schema, rather than
  inferring from whatever's currently landing in `content_attributes`.
- Does this apply only to WhatsApp Cloud (`incoming_message_whatsapp_cloud_
  service.rb`), or do other WhatsApp providers (360dialog, Twilio) send
  an equivalent referral payload worth normalizing the same way?
- Scope for this phase: read-only surfacing (badge/panel), or does it
  extend into attribution reporting/analytics? Recommend treating those
  as two separate phases even if this one studies both — surfacing is a
  much smaller, faster win.
- Is there a data-retention/PII concern with persisting ad creative
  content (headline/body/media URL) beyond the message it already lives
  on?
