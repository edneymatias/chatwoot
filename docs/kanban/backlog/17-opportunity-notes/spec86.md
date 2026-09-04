# Phase 86: Notes on Opportunity

**Status**: placeholder — pending brainstorm session
**Depends on**: `app/models/note.rb` (core Chatwoot `Note` model); `custom/app/models/opportunity.rb`; `custom/app/models/opportunity_activity.rb` (audit-trail pattern).

## Quick Preview

Identified during a market-landscape brainstorm (2026-09-04). Chatwoot core already has a notes
feature, but it is scoped to `Contact`: `Note` (`app/models/note.rb`) belongs directly to
`contact_id`, with no polymorphic `notable_type`/`notable_id` — confirmed by reading the model, it
cannot be reused as-is for a different owner. That's a real gap for this product: a contact can
have several opportunities over time (different pipelines, different intake moments), and a note
like "cliente pediu desconto, aguardando aprovação do gerente" belongs to one specific opportunity,
not to the contact as a whole.

Per the fork's minimal-upstream-changes philosophy, extending core `Note` to be polymorphic is
likely the wrong move — a dedicated `custom/`-namespaced model mirroring the same shape
(`content`, `account_id`, `opportunity_id`, `user_id`) is the probable direction, to be confirmed
during brainstorm.

Open questions for the brainstorm:
- Confirm a new `Custom::OpportunityNote`-style model (own table) over touching core `Note`.
- Where displayed — a new tab in `OpportunityConversationDrawer.vue` alongside
  conversation/history, or inline on the opportunity detail panel?
- Do note-added events also appear in `OpportunityActivity`'s audit trail, or stay a separate
  stream?
- Any automation use (e.g. an "add note" automation action), or is this purely manual entry?
