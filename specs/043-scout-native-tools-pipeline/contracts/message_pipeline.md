# Contracts: Message Pipeline, Debounce & Fail-Safe

**Branch**: `043-scout-native-tools-pipeline` | **Date**: 2026-08-19 | **Spec**: [spec.md](file:///home/matias/dev/chatwoot/specs/043-scout-native-tools-pipeline/spec.md)

This contract defines the interfaces for the incoming message pipeline, debounce buffer, fail-safe handoff, and contact memory generation.

---

## 1. Debounce Buffer Contract

### Enqueue Interface
- **Trigger**: `Custom::ScoutListener#message_created` (dispatched on incoming WhatsApp message).
- **Service/Job**: `Custom::Scout::ProcessMessageJob.enqueue_debounced(conversation, scout)`
- **Redis Keys**:
  - `scout:debounce:conversation:<id>:last_message_at`: `SET <timestamp> EX 3600` (always updated on every message to slide the window).
  - `scout:debounce:conversation:<id>:enqueued`: `SET true NX EX 3600` (returns `true` if this is the first message in the current burst).
- **Sidekiq Execution**:
  - If `scout:debounce:conversation:<id>:enqueued` was acquired:
    `Custom::Scout::ProcessMessageJob.perform_in(scout.debounce_delay_seconds.seconds, conversation.id)`
  - When `ProcessMessageJob` fires:
    - Calculates `elapsed = Time.current.to_f - last_message_at`.
    - If `elapsed < debounce_delay_seconds`:
      - Re-schedules itself: `perform_in((debounce_delay_seconds - elapsed).ceil.seconds, conversation_id)`.
    - If `elapsed >= debounce_delay_seconds`:
      - Deletes `scout:debounce:conversation:<id>:enqueued` and `scout:debounce:conversation:<id>:last_message_at`.
      - Invokes `Custom::Scout::AgentRunner.new(scout: scout, conversation: conversation).perform`.

---

## 2. Fail-Safe Handoff Contract

### Pre-Call Check Contract
Prior to calling `ruby_llm`, `AgentRunner` evaluates:
1. `scout.quota_available?` (`responses_quota == -1 || responses_consumed < responses_quota`)
2. `api_key_present?` (`scout.api_key_override.present? || ENV["#{scout.provider.upcase}_API_KEY"].present?`)

If either check is `false`, LLM call is **never** initiated, and `perform_fail_safe_handoff` is triggered.

### Runtime Error Wrapper Contract
Any `StandardError` during runner execution (network timeout, provider 500, rate limit 429, schema error) is rescued:
```ruby
begin
  # Context building, RubyLLM chat invocation, and tool handling
rescue StandardError => e
  ChatwootExceptionTracker.new(e, account: conversation.account).capture_exception
  perform_fail_safe_handoff("Runtime error: #{e.message}")
end
```

### `perform_fail_safe_handoff` Execution
1. Check `conversation.pending?` — only transition if currently pending.
2. Call `conversation.bot_handoff!`.
3. Create private alert note:
   ```text
   ⚠️ [IA Pausada]: A conversa foi transferida para atendimento humano devido a esgotamento de saldo/limite de API.
   ```
4. If `scout.feature_memory` is `true`:
   `Custom::Scout::ContactNotesService.new(scout, conversation).generate_and_update_notes`.

---

## 3. Contact Memory Generation Contract

- **Trigger Points**:
  1. Successful human handoff via `Custom::Scout::Tools::HandoverToHuman`.
  2. Fail-Safe handoff via `perform_fail_safe_handoff`.
- **Condition**: `scout.feature_memory? == true`.
- **Action**:
  Calls `Custom::Scout::ContactNotesService.new(scout, conversation).generate_and_update_notes`.
- **Intermediate Turns**: No memory generation on turns that do not result in a handoff.
