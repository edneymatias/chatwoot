# Phase 1 Data Model: Scout Observability & Handoff Notice

No new database tables, columns, or ActiveRecord models are introduced by this feature (matches
spec Assumptions and Constitution Principle IV — no migrations). The three entities named in the
spec's "Key Entities" section are conceptual/in-flight, not persisted:

## Assistant Execution Trace

Not a Chatwoot-persisted record. It is an OpenTelemetry trace/span emitted by
`Integrations::LlmInstrumentation#instrument_agent_session` / `#instrument_llm_call` around
`Custom::Scout::AgentRunner#execute_chat`'s `chat.ask(...)` call, exported to Langfuse when
`ChatwootApp.otel_enabled?` is true. Lifetime is one Scout conversation turn (one `AgentRunner#perform`
invocation that reaches `generate_and_process_response`). Attributes carried on the span (per the
existing `Integrations::LlmInstrumentationSpans` helpers already used by Captain): the outgoing
prompt/message history, the model's raw response, and standard Langfuse metadata
(account/conversation identifiers) — no new attribute vocabulary is introduced; this feature reuses
the module's existing attribute-setting helpers as-is.

## Tool Call Record

Not persisted. One OpenTelemetry span per tool invocation, emitted by
`Integrations::LlmInstrumentation#instrument_tool_call(tool_name, arguments)` from
`Custom::Scout::Tools::BaseTool#call`, nested under the enclosing Assistant Execution Trace span
(via the module's existing Langfuse span-propagation helpers). Fields: tool name (`RubyLLM::Tool#name`,
e.g. `manage_opportunity`, `call_custom_api`), the normalized arguments the model supplied, and the
tool's return value (a `Hash` with an `error` key on failure, per `RubyLLM::Tool#call`'s existing
contract) or any exception `instrument_tool_call`'s block lets propagate.

## Handoff Transfer Message

A normal `Message` row (existing Chatwoot model), created via the existing
`Messages::MessageBuilder` service — no schema change. Distinguishing attributes: `message_type:
'outgoing'`, `private: false`, `content: I18n.t('conversations.scout.handoff')` (new locale key,
see `research.md` §3). Created once per handoff, immediately before the existing
`conversation.bot_handoff!` call in each of the two paths
(`Custom::Scout::AgentRunner#perform_fail_safe_handoff`, `Custom::Scout::HandoffService#perform_handoff`),
in addition to (never replacing) each path's pre-existing private note.

That private note is **not** created unconditionally in both paths, so the two flows aren't quite
symmetric: `AgentRunner#perform_fail_safe_handoff` always creates its private note. In
`HandoffService`, the private note (`create_transfer_note`) only runs `if reason.present?`
(`handoff_service.rb:12,32`) — and today it runs *after* `perform_handoff` (i.e. after
`bot_handoff!` already fired), not before. The new public transfer message does not follow that
conditional: it belongs inside/around `perform_handoff` itself (which always runs whenever the
conversation is pending), so it is created every time a handoff actually happens, independent of
whether a `reason` was supplied and independent of the private note's own conditional logic.

## Validation rules

None beyond what `Messages::MessageBuilder` and `RubyLLM::Tool#call` already enforce — this feature
adds no new validated inputs, only wraps existing call paths with tracing and one additional
message-creation call using an existing, already-validated content string (a static I18n
translation, not user input).

## State transitions

Unchanged from current behavior: `conversation.bot_handoff!` still transitions the conversation the
same way it does today (`pending` → reopened for the human queue) in both paths; this feature only
adds a `Message` row and trace spans before that existing transition, never after and never
conditionally on their success (observability failures must not block the handoff — see spec Edge
Cases).
