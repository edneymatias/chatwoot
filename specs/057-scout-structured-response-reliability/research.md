# Phase 0 Research: Scout Structured Response Reliability

No `NEEDS CLARIFICATION` markers remain in the Technical Context. The user-provided direction
(investigate `ruby_llm`'s `with_schema`) turned out to point directly at an already-established
pattern in this codebase (Captain's own main response), which this document confirms by reading
the actual gem and Captain source rather than assuming.

## 1. How to enforce the response structure at the API level

**Decision**: Define `Custom::Scout::ResponseSchema < RubyLLM::Schema` with two string fields,
`reasoning` and `response` — the exact two fields `Custom::Scout::SystemPromptsService`'s prompt
already instructs the model to return — and call `chat.with_schema(Custom::Scout::ResponseSchema)`
in `AgentRunner` before/alongside the existing `chat.with_tool(...)` calls.

**Rationale**: `ruby_llm-schema` (0.3.0) is already a direct `Gemfile` dependency
(`Gemfile.lock:871-873`, `Gemfile:202`) — no new dependency needed. `RubyLLM::Schema` is a small
class DSL (`lib/ruby_llm/schema.rb` in the `ruby_llm-schema` gem) for declaring `string`/`object`/etc.
fields, compiled to a JSON Schema via `#to_json_schema`. `RubyLLM::Chat#with_schema(schema)`
(`ruby_llm-1.15.0/lib/ruby_llm/chat.rb:106-113`) accepts such a class, normalizes it, and stores it
as `@schema`; `#complete` (same file, ~line 160) forwards `schema: @schema` to the provider's
`render_payload`.

This is not a new pattern for this codebase: `enterprise/lib/captain/response_schema.rb` already
defines `Captain::ResponseSchema < RubyLLM::Schema` with **the identical two fields**
(`string :response`, `string :reasoning`), wired in as `Agentable#agent_response_schema`
(`enterprise/app/models/concerns/agentable.rb:60-62`) — this is the schema Captain V2's own main
agent response already uses. `Captain::BaseTaskService#build_chat`
(`lib/captain/base_task_service.rb:85-97`) shows the exact call shape:
`chat.with_schema(schema) if schema` called alongside `chat.with_tool(tool)` for each tool. Scout's
`Custom::Scout::ResponseSchema` mirrors this shape (not the Captain file's text — same licensing
caveat already recorded in prior Scout phases), consuming the same already-shared gem capability
Captain already relies on for its own reliability.

**Alternatives considered**: Passing a raw JSON Schema `Hash` to `with_schema` directly instead of
a `RubyLLM::Schema` subclass — technically supported (`with_schema` accepts either), but rejected
in favor of the class-DSL form to match the established `Captain::ResponseSchema` precedent
exactly, which is more readable and independently testable (`Custom::Scout::ResponseSchema.valid?`,
`#to_json_schema`, per the gem's own `Schema` class methods).

## 2. Compatibility with tool-calling (FR-004)

**Decision**: No special handling needed — `with_schema` and `with_tool` coexist in the same
`Chat` without conflict, confirmed by reading both providers Scout can be configured with.

**Rationale**: `ScoutAccountConfig#provider` only supports two values, `gemini` and `openai`
(`custom/app/models/scout_account_config.rb:21`). Read both provider adapters in the `ruby_llm` gem
directly:
- `providers/openai/chat.rb#render_payload` (lines ~15-51): when `tools.any?`, adds `payload[:tools]`
  and `payload[:tool_choice]`; when `schema` is present, **independently** adds
  `payload[:response_format] = { type: 'json_schema', json_schema: {...} }`. Both blocks are
  unconditional on each other — OpenAI's Structured Outputs and function/tool calling are used
  together in the same request, exactly matching OpenAI's real API capability.
- `providers/gemini/chat.rb#render_payload` (lines ~15-40): schema goes into
  `payload[:generationConfig]` (`responseJsonSchema` for Gemini ≥ 2.5, `responseSchema` for older
  models — version-gated automatically by `response_json_schema_supported?`, line ~196), while
  tools go into a **separate** `payload[:tools]`/`payload[:toolConfig]` — no shared/conflicting key.

Also confirmed: `RubyLLM::Chat#complete` only attempts to JSON-parse `response.content` into the
schema shape when the response is *not* a tool call
(`if @schema && response.content.is_a?(String) && !response.tool_call?`, `chat.rb` ~line 172) — so
schema enforcement never interferes with an intermediate turn where the model only calls a tool;
it only applies to the model's final natural-language turn, exactly where Scout needs it.

**Alternatives considered**: None needed — this is gem behavior already exercised by Captain in
production for a tool-calling agent, not a new integration to validate from scratch.

## 3. How the parsed response reaches `AgentRunner`, and what needs to change

**Decision**: `AgentRunner#parse_structured_response` gains a branch: if `content` is already a
`Hash` (schema mode succeeded), use it directly; otherwise fall back to the existing
fence-stripping + `JSON.parse` logic unchanged (covers FR-005's fallback for a provider/model that
doesn't honor the schema, and any edge case where schema mode's own parse attempt failed).

**Rationale**: Confirmed in `chat.rb` (~line 172-177): when `@schema` is set and the response
comes back as a JSON string, `RubyLLM` itself attempts `response.content = JSON.parse(response.content)`
and **keeps `content` as the original String if that parse fails**
(`rescue JSON::ParserError; # If parsing fails, keep content as string`). So
`AgentRunner#execute_chat`'s caller must handle both shapes:
- **Hash** (`{"reasoning" => "...", "response" => "..."}`, string keys — plain `JSON.parse`, not
  `JSON.parse(..., symbolize_names: true)`) — the common case once schema mode is active and the
  provider honors it.
- **String** — the current fallback: either the provider/model doesn't support schema mode
  (FR-005), or schema mode was requested but the model still didn't produce parseable JSON (should
  become rare, per SC-001, but must still be handled per FR-003's fail-closed guarantee).

This keeps `FR-002`/`FR-003` intact with no behavior change to the failure path: a `Hash` missing
the `response` key, or a `String` that still fails the existing `JSON.parse` fallback, both
continue to return `nil` from `parse_structured_response`, triggering the existing
`perform_fail_safe_handoff('Falha ao interpretar resposta estruturada do modelo.')` unchanged.

**Alternatives considered**: Suppressing `RubyLLM`'s own auto-parse and always handling raw text
manually — rejected; fighting a gem convenience that already does the right thing (and that
Captain already relies on, via `Llm::BaseAiService#sanitize_json_response` consuming a similarly
already-parsed shape) adds code for no benefit.

## 4. Provider/model capability fallback (FR-005)

**Decision**: No explicit capability-detection code is needed in Scout. Both providers Scout
supports already implement schema-aware `render_payload` in the installed gem version; where a
specific model doesn't support the newer schema mechanism (e.g. Gemini < 2.5), the gem's own
provider adapter already degrades gracefully to the older mechanism
(`responseSchema` instead of `responseJsonSchema`) automatically — Scout's code doesn't need to
know which one is used.

**Rationale**: This is a direct, verified reading of `gemini/chat.rb`'s
`response_json_schema_supported?`/`structured_output_config` (~lines 196-261): it inspects the
resolved `model`'s version and picks the right config key, with no caller-visible difference.
Since `ScoutAccountConfig` only allows `gemini`/`openai` (no third, potentially
schema-unaware provider today), there is currently no real path where `with_schema` is set but
silently produces zero effect — but if such a provider were added later, the graceful-degradation
behavior described in Decision 3 (Hash-or-String handling) already covers it without further
Scout-side changes, satisfying FR-005 "for free."

**Alternatives considered**: An explicit `provider_supports_schema?` check in
`Custom::Scout::AgentRunner` before calling `with_schema` — rejected as unnecessary: both
supported providers already handle it, and adding a capability check the gem itself already
performs internally would violate Constitution Principle II (smallest change; no speculative
guards for a case that can't currently occur).

## 5. Enterprise dual-tree check

**Decision**: No Enterprise-side changes needed.

**Rationale**: `Custom::Scout::ResponseSchema` is fork-owned code under `custom/`, with no upstream
or `enterprise/` counterpart to keep in sync. `ruby_llm-schema` is a plain, non-enterprise-gated
Gemfile dependency already present — confirmed in `Gemfile.lock` with no conditional/enterprise
grouping around it.
