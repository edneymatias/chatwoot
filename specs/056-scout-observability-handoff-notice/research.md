# Phase 0 Research: Scout Observability & Handoff Notice

No `NEEDS CLARIFICATION` markers remain in the Technical Context — the source doc
(`docs/kanban/ciclo 10/scout/17-observability-and-handoff-notice/spec77.md`) and the spec's
Clarifications session already pinned every open decision. This document records the concrete
integration points confirmed by reading the actual dependency source, since "mirror the existing
pattern" only becomes actionable once the exact method to call is known.

## 1. How to instrument Scout's main LLM call

**Decision**: `Custom::Scout::AgentRunner` includes `Integrations::LlmInstrumentation` directly and
wraps the `chat.ask(...)` call inside `#execute_chat` with `instrument_agent_session` (outer trace)
and/or `instrument_llm_call` (per-call span), calling the module's public methods explicitly.

**Rationale**: `Integrations::LlmInstrumentation#instrument_llm_call` / `#instrument_agent_session`
take a `params` hash and a block, and both already no-op via `return yield unless
ChatwootApp.otel_enabled?` (`lib/integrations/llm_instrumentation.rb:10-48`) — no new gating logic
is needed, only calling them.

**Alternatives considered**: Mirror Captain's `install_instrumentation` (`Agents::Instrumentation.install(runner, ...)`,
`enterprise/app/services/captain/assistant/agent_runner_service.rb:147-160`) — rejected. That
auto-instrumentation hooks into the `agents` gem's `Agents::Runner`, which Captain uses instead of
calling `RubyLLM::Chat#ask` directly. Scout's `AgentRunner` calls `chat.ask` directly (plain
`RubyLLM::Chat`, no `Agents::Runner`), so there is no runner object to auto-instrument — the manual
`instrument_agent_session`/`instrument_llm_call` API is the one applicable here. This is exactly
what the source doc specifies ("envolver a chamada principal (`chat.ask`, em `execute_chat`) com
`instrument_agent_session`/`instrument_llm_call`").

Confirmed against the official OpenTelemetry Ruby SDK docs: `tracer.in_span(name) { |span| ... }`
is exactly the documented pattern for nested spans (parent/child derived automatically from lexical
nesting, no manual `parent:` needed), and the SDK's own `in_span` implementation already records
exceptions, sets the error status, and calls `span.finish` in an `ensure` before re-raising — so
`instrument_tool_call`'s intentional lack of its own `rescue` (see its comment: "tools can fail and
LLMs should be aware of those failures") is safe by design, not an oversight.

## 2. How to instrument every tool call at a single point

**Decision**: `Custom::Scout::Tools::BaseTool` overrides `#call(args)` (not `#execute`), wrapping
`super` with `instrument_tool_call(name, args)`.

**Rationale**: Confirmed by reading `ruby_llm` gem source (`ruby_llm-1.15.0/lib/ruby_llm/tool.rb:106-113`):
`RubyLLM::Tool#call(args)` is the one method the `ruby_llm` gem itself invokes when the model
requests a tool call; it normalizes/validates arguments and then calls `execute(**normalized_args)`
on the subclass. Every one of Scout's seven tools
(`ManageOpportunity`, `MoveOpportunityStage`, `UpdateContact`, `CreatePrivateNote`,
`HandoverToHuman`, `CallCustomApi`, `SearchKnowledgeBase`) subclasses `BaseTool` and defines only
`#execute`, never overriding `#call` — so overriding `#call` once in `BaseTool` is a true single
choke point that requires zero changes to any individual tool file, matching the source doc's
"ponto único, herdado por todas as tools" requirement exactly. `Captain::ToolInstrumentation`
(`lib/captain/tool_instrumentation.rb`) is not reusable as-is here — it instruments the `agents`
gem's session/tool-call callbacks (`instrument_tool_session`, `on_tool_complete`), a different tool
framework than `RubyLLM::Tool`. The relevant reusable piece is
`Integrations::LlmInstrumentation#instrument_tool_call(tool_name, arguments)`
(`lib/integrations/llm_instrumentation.rb:50-64`), which is framework-agnostic (just wraps a block
in a span) and already used as the tool-call primitive underneath Captain's own instrumentation.

**Alternatives considered**:
- Instrumenting inside `AgentRunner#build_tools` by wrapping each tool instance individually —
  rejected as unnecessary indirection; `BaseTool#call` is strictly simpler and is the actual
  dispatch point regardless of how tools are constructed.
- The official `ruby_llm` v1.15+ callback hooks, `chat.before_tool_call { |tool_call| ... }` /
  `chat.after_tool_result { |result| ... }` (a public, documented API, distinct from overriding
  `#call`) — rejected. `instrument_tool_call(name, args) { ... }` expects one block that opens and
  closes the span in the same scope; the two-callback API would require correlating a
  `before`/`after` pair by `tool_call.id` and holding the open span in some external state (e.g. a
  hash on `AgentRunner`) until the matching `after` fires — more moving parts than a single
  `#call` override for no offsetting benefit here.
- `prepend`-ing an instrumentation module onto `BaseTool` and overriding `#execute` (the pattern
  `Captain::Tools::Instrumentation` uses today, `enterprise/app/services/captain/tools/instrumentation.rb`)
  — rejected, and not just for style: this is a **confirmed latent bug** in Captain's own code, not
  a pattern to copy. Verified live in the `rails` container: when a subclass defines its own
  `#execute` without calling `super` — which is exactly what Captain's Copilot tools
  (e.g. `Captain::Tools::Copilot::GetArticleService`) do — Ruby's method resolution order makes the
  subclass's `#execute` win over the `prepend`ed module's `#execute`, so the instrumentation never
  runs. `BaseTool#call` avoids this failure mode entirely: none of Scout's seven tools override
  `#call`, and plain inheritance (not `prepend`) means there is no MRO race to lose — the override
  in `BaseTool` always runs.
- The community gem `opentelemetry-instrumentation-ruby_llm` (auto-instruments `ruby_llm` chat
  completions and tool calls, with built-in Langfuse attribute support) — rejected as a new
  dependency used nowhere else in this fork, diverging from the exact pattern Captain already uses
  and violating spec77's explicit "mesmo padrão usado por Captain" direction and Constitution
  Principle I (prefer existing extension points over new dependencies).

## 3. Where to send the public handoff message, and with what content

**Decision**:
- `Custom::Scout::AgentRunner#perform_fail_safe_handoff`: call
  `Messages::MessageBuilder.new(nil, @conversation, { content: I18n.t('conversations.scout.handoff'), message_type: 'outgoing', private: false }).perform`
  immediately before `@conversation.bot_handoff!`, in addition to (not replacing) the existing
  private-note call.
- `Custom::Scout::HandoffService#perform_handoff` (or immediately around it in `#perform`): the
  same call, before `@conversation.bot_handoff!` fires within `perform_handoff`.
- Message text key: `conversations.scout.handoff`, added to `config/locales/en.yml` and
  `config/locales/pt_BR.yml` (per the spec Clarification: single message, no variation by path or
  reason).

**Rationale**: `config/locales/en.yml` and `config/locales/pt_BR.yml` already define a sibling key,
`conversations.captain.handoff` (`en.yml:307-308`: "Transferring to another agent for further
assistance."; `pt_BR.yml:290`: "Transferindo para que outro agente dê assistência."). For the
**fail-safe path** this matches an existing, direct reference implementation:
`enterprise/app/services/enterprise/message_templates/hook_execution_service.rb#perform_handoff`
(lines 56-67) creates exactly this kind of outgoing, non-private message before calling
`bot_handoff!` when Captain hits its own fail-safe (quota exhaustion). Note that
`hook_execution_service.rb` itself hardcodes the English string literally rather than calling
`I18n.t('conversations.captain.handoff')` — that key currently has no Ruby caller anywhere in the
codebase; this is a pre-existing inconsistency in Captain's own code, not something to replicate.
Scout's implementation follows CLAUDE.md's i18n convention (no bare user-facing strings) and this
repo's existing `conversations.<assistant>.handoff` shape by adding `conversations.scout.handoff`
and calling it via `I18n.t`, rather than hardcoding text.

For the **explicit-handoff path**, there is no equivalent direct precedent to mirror: Captain V2's
own explicit handoff tool (`enterprise/lib/captain/tools/handoff_tool.rb`, current upstream
`develop`) creates only a private note with the reason and calls
`conversation.bot_handoff!(dispatch_event: false)` — no public message. So Scout sending a public
transfer message on its explicit-handoff path (`HandoffService#perform`) isn't mirroring an
existing Captain behavior for that specific path; it's closing a customer-visibility gap that
Captain V2 itself still has today. This doesn't change the decision (the spec's Clarification is
explicit: one fixed message, both paths), it just corrects the rationale — cite the fail-safe
precedent for *why the message shape and creation-before-`bot_handoff!` ordering is right*, not as
proof this exact gap was already solved elsewhere for the explicit path.

`Custom::Scout::AgentRunner` and `Custom::Scout::HandoffService` already use `Messages::MessageBuilder`
for the private notes and for normal outgoing replies, so this reuses an already-established call
shape rather than introducing a new message-creation path.

**Alternatives considered**: A hardcoded string instead of an i18n key — rejected; violates
CLAUDE.md's "no bare strings in templates/user-facing text" convention and the spec's own FR-004
("translated string, available in the product's supported languages"), even though the Captain
reference implementation itself does this today.

## 4. Enterprise dual-tree check

**Decision**: No Enterprise-side changes needed.

**Rationale**: `Custom::Scout::*` is entirely fork-owned code under `custom/`, with no upstream or
`enterprise/` counterpart to keep in sync (Scout is not an upstream Chatwoot feature). The two
shared dependencies touched (`Integrations::LlmInstrumentation`, `Messages::MessageBuilder`) are
consumed read-only — their own files are not modified, so there is no OSS/Enterprise contract at
risk. Confirmed no drift between this fork and upstream on the touched shared files: `git diff`
against the local `develop` branch (the fork's up-to-date mirror of `chatwoot/chatwoot`, per
CLAUDE.md's Branch Model) shows zero differences for `lib/integrations/llm_instrumentation.rb`,
`lib/captain/tool_instrumentation.rb`, and `app/builders/messages/message_builder.rb`. Also
confirmed `Messages::MessageBuilder` does have an Enterprise override
(`enterprise/app/builders/enterprise/messages/message_builder.rb`, via `prepend_mod_with`), but it
only adjusts `message_type` for voice-channel inboxes — it does not touch `content` or `private`,
so it has no effect on the fixed transfer message this feature adds.

## 5. External validation

Every decision above was independently cross-checked, after the initial draft, against three
sources: this fork's own code plus the local `develop` mirror of upstream, official documentation
(OpenTelemetry Ruby SDK, Langfuse OTel integration, `ruby_llm`), and real-world open-source usage
(via GitHub code search). Two corrections came out of that pass and are folded into §§2–4 above:
the rejected-alternatives list in §2 now includes the official `ruby_llm` callback API and the
confirmed MRO bug in Captain's `prepend`+`#execute` pattern (found live, not from docs), and §3's
rationale no longer overstates the explicit-handoff-path precedent. Everything else — the `#call`
override point, the `tracer.in_span` error-handling behavior, the Langfuse attribute names, and the
"no upstream drift" claim — was confirmed as-is with no changes needed.
