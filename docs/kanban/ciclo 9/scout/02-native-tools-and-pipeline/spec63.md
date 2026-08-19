# Phase 02 — Native Tools & Message Pipeline

**Master doc**: `docs/kanban/backlog/scout/spec60.md` §2, §4, §5, §8, §10
**Depends on**: Phase 01 (`Scout`/`ScoutInbox`/`ScoutTool` models, `ruby_llm` client).

## Goal

Wire a real incoming WhatsApp message through debounce → context building → LLM tool-calling →
Opportunity/Kanban side effects, with the Fail-Safe handoff guaranteeing no conversation is ever
stuck waiting on the bot.

## Scope

- `Scout::ProcessMessageJob` — Sidekiq job triggered off the incoming-message event dispatcher,
  debounced via Redis (5s default window, `Scout#debounce_delay_seconds`), following the buffering
  idiom already used by `Whatsapp::MessageDedupLock`
  (`app/services/whatsapp/message_dedup_lock.rb`, `Redis::Alfred.set(key, true, nx: true, ex:
  ttl)`).
- `Scout::AgentRunner` — orchestrates one turn:
  1. `BalanceCheck`: `scout.quota_available?` AND API key present/valid. On failure → Fail-Safe
     (below), do not call the LLM.
  2. Detects `Attachment#file_type` (`:audio`/`:image`) and passes them to the multimodal-capable
     `ruby_llm` call (spec60.md §6 — single-key all-in-one providers).
  3. Checks `inbox.out_of_office?` (`OutOfOffisable` concern) and injects the result into the
     prompt context (does not block the response, per spec60.md §5).
  4. Builds context (persona/system_prompt + `product_catalog` + `knowledge_sources` +
     `contact.to_llm_text` — the existing `LlmFormatter::ContactLlmFormatter`, already used
     elsewhere in the codebase, whose "Contact Notes" section surfaces any notes Captain or a
     previous Scout run already generated for this contact, at no extra cost) and calls `ruby_llm`
     with the enabled tools from Phase 02/04.
  5. On successful response, increments `scout.responses_consumed`.
- Fail-Safe Handoff (spec60.md §4.2/§4.3): on quota exhaustion or API key failure, explicitly check
  `conversation.pending?` (the guard lives in the caller, not in `bot_handoff!` — see spec60.md
  §4.1 revision note), then call `conversation.bot_handoff!` and create the yellow alert private
  note. Never assume `bot_handoff!` itself gates on status.
- Native Ruby tools (spec60.md §10), calling into existing services rather than reimplementing:
  - `manage_opportunity(action, title, stage_id, estimated_value, custom_attributes)` — creates/
    updates via existing `Opportunity` model; attribution fields are populated by reusing
    `Custom::ReferralAttributionService` / `Custom::AutomationRules::ActionService#find_referral_message`
    (`custom/app/services/custom/automation_rules/action_service.rb:10-42`), **not** a
    reimplementation of the referral SQL query.
  - `move_opportunity_stage(stage_id, lost_reason)` — writes the `lost_reason` column added in
    Phase 01.
  - `update_contact(name, email, phone, custom_attributes)`.
  - `create_private_note(content)`.
  - `handover_to_human(assignee_id, team_id, reason)` — reuses the same `bot_handoff!` call path as
    the Fail-Safe flow.
- Contact memory (spec60.md §9.1 `feature_memory`): when `scout.feature_memory` is true, generate
  contact notes at the end of a qualification run, reusing Captain's exact mechanism rather than a
  new implementation — `Captain::Llm::ContactNotesService` already takes any `(assistant,
  conversation)` pair (it only calls `conversation.contact`/`conversation.account`, nothing
  Captain-specific), so `Scout::AgentRunner` calls it directly (`Captain::Llm::ContactNotesService.new(scout,
  conversation).generate_and_update_notes`) instead of duplicating the notes-generation prompt/flow.
  Triggered from the same places `CaptainListener#conversation_resolved` triggers it for Captain:
  on `handover_to_human` (successful human handoff) and on the Fail-Safe handoff path — not on
  every turn, to avoid redundant LLM calls mid-conversation.

## Out of scope (deferred to later phases)

- No external REST/webhook tool execution (`call_custom_api`/`ScoutTool` dispatch) — Phase 04.
- No UI for configuring Scouts, tools, or product catalogs — Phase 05.
- No follow-up/re-engagement job — Phase 07.
- Production encryption-key availability is a **dependency**, not built here — see Phase 03. This
  phase can be developed/tested in an environment where `ActiveRecord::Encryption` is already
  configured (e.g. local dev with keys generated via `bin/rails db:encryption:init`), but must not
  ship to production until Phase 03 is resolved.

## Acceptance criteria

- An incoming WhatsApp message to a Scout-enabled inbox is debounced, processed once per buffer
  window (not once per message), and produces either a tool-calling response or a Fail-Safe
  handoff.
- A referral-carrying first message (CTWA) results in an `Opportunity` with intact campaign
  attribution (thumbnail, headline, campaign name) after the Scout tool creates it — verified
  against the existing `Custom::ReferralAttributionService` pipeline, not a new implementation.
- Forcing quota exhaustion (`responses_quota: 0`) or an invalid API key results in the conversation
  moving to `open` status with a yellow alert private note, and never stays `pending`.
- `move_opportunity_stage` with a lost outcome persists `lost_reason`.
- With `scout.feature_memory` true, a handoff (human or Fail-Safe) produces at least one
  `contact.notes` row summarizing the qualification conversation, and a subsequent Scout run (or
  Captain run) for the same contact sees that note in its `contact.to_llm_text` context. With
  `feature_memory` false, no notes are generated.
