# Phase 0 Research: Scout Response Auditor

No `NEEDS CLARIFICATION` markers remain in the Technical Context. This document confirms, by
reading the actual gem/runtime code and the Captain reference architecture (read-only, per the
licensing caveat already recorded in the spec's source document), that every piece this feature
needs already has a proven, in-codebase precedent — this is a new consumer of established patterns,
not new architecture.

## 1. How to ground the consistency check in real tool activity (not just reply text)

**Decision**: Extract `PlaygroundRunner`'s existing `wrap_tool`/`execute_and_record` private
methods into a shared module, `Custom::Scout::Tools::CallRecorder`, wrapping each tool's
`#execute` method (not `#call`) via `define_singleton_method`. Both `AgentRunner` and
`PlaygroundRunner` include it and wrap the tools they build before registering them with the chat.

**Rationale**: Read `RubyLLM::Tool#call` (`ruby_llm-1.15.0/lib/ruby_llm/tool.rb:106-114`): it
validates args, then calls `execute(**normalized_args)` and returns the result. Scout's own
`Custom::Scout::Tools::BaseTool#call` (`custom/app/services/custom/scout/tools/base_tool.rb:15-19`)
already overrides `call` to wrap `instrument_tool_call(name, args) { super(args) }` for telemetry.
`PlaygroundRunner#wrap_tool` (`custom/app/services/custom/scout/playground_runner.rb:70-93`)
instead patches `execute` directly via `define_singleton_method`, which sits *underneath* that
`call`/`instrument_tool_call` layer — so recording tool activity this way doesn't interfere with,
duplicate, or need to know about the existing instrumentation wrapper. This is exactly the
mechanism the spec's source document calls for explicitly, rejecting the alternative of inspecting
`chat.messages`/`RubyLLM::ToolCall` as a second, redundant mechanism.

Extracting into a shared module (rather than duplicating the ~15-line pattern into `AgentRunner`)
keeps both runners using one tested implementation and one recorded-call shape. **Correction from
cross-validation**: the actual base hash `PlaygroundRunner#execute_and_record` builds
(`playground_runner.rb:82`) is `{tool_name:, arguments:, simulated:}`, not just
`{tool_name:, arguments:}` — `simulated: tool_name != 'call_custom_api'` is always present,
success or failure, alongside `result:` or `error:`. `simulated` is Playground-specific business
logic (only `call_custom_api` genuinely calls out even during a simulation); `CallRecorder` makes
it an explicit parameter the includer supplies per call rather than baking that rule into the
shared module: `PlaygroundRunner` passes `tool_name != 'call_custom_api'` (unchanged behavior),
`AgentRunner` always passes `simulated: false` (every tool call it wraps is a real production
execution). The success/failure shape itself is unchanged: `result:` on success, `error:` on
failure (caught, re-raised — `PlaygroundRunner`'s existing `ensure` block already guarantees the
record is appended even when the tool raises). This failure-shape is what makes FR-001's clarified
behavior possible: a tool that ran but errored produces a recorded call with an `error` key and no
`result`, which the consistency checker (§3 below) treats as "the action did not succeed," not as
grounding for a "completed" claim.

**Alternative considered and rejected — chat-level `before_tool_call`/`after_tool_result`
callbacks**: `RubyLLM::Chat` (this exact pinned version, confirmed by reading
`ruby_llm-1.15.0/lib/ruby_llm/chat.rb:140-145`) exposes `before_tool_call { |tool_call| ... }` and
`after_tool_result { |result| ... }` as chat-level callback registration, which would avoid
monkey-patching `execute` entirely. Rejected because `handle_tool_calls`
(`chat.rb:279-283`) calls `execute_tool` (which calls `tool.call(args)`, i.e. Scout's own
`BaseTool#call` → `execute`) with **no rescue** — a raised exception propagates past the
`run_callbacks(:after_tool_result, ...)` line entirely, so `after_tool_result` never fires for a
tool that raises. `PlaygroundRunner`'s existing `ensure`-based capture does not have this gap
(§ above). Using the callback API for the shared module would silently regress Playground's
existing behavior of recording a failed call (with its `error`) even when the tool raised. Note
this gap doesn't matter for `AgentRunner` itself in practice: a tool exception that propagates all
the way up already aborts the whole turn via `AgentRunner#perform`'s existing top-level rescue
(`agent_runner.rb:26-30`) before any reply is drafted or audited — but keeping one shared
implementation for both runners means the `execute`-wrapping approach (which handles both runners'
needs correctly) is preferred over one that only works for `AgentRunner`.

**Alternatives considered**: Inspecting `RubyLLM::Chat#messages`/`ToolCall` objects directly after
`chat.ask` returns — rejected per the spec's source document: this is exactly the second mechanism
the phase explicitly avoids introducing, when an already-working, already-tested pattern
(`PlaygroundRunner`'s wrapping) does the same job and already distinguishes success from failure.

## 2. Explicit-handoff-intent detection — adapting `AssistantActionClassifierService`

**Decision**: `Custom::Scout::ActionClassifierService#classify(message_history:)` calls
`@scout.llm_chat(temperature: 0.0).with_schema(Custom::Scout::ActionClassifierSchema)
.with_instructions(...).ask(...)`, returning a normalized `{action:, action_reason:}` (or an error
hash) exactly like Captain's service does, but built around Scout's own commercial-domain reasons
(e.g. explicit human request, accepted human offer, repeated frustration/loop, off-topic request
already outside the Phase 08 guardrail's boundary) rather than Captain's 12 support-domain reasons.

**Rationale**: Read `Captain::Llm::AssistantActionClassifierService`
(`enterprise/app/services/captain/llm/assistant_action_classifier_service.rb`): it is a small,
self-contained service — one LLM call via `with_schema`, wrapped in
`instrument_llm_call`/`rescue StandardError => e; ChatwootExceptionTracker...`, returning a
normalized hash with an `'error'` key on any failure rather than raising. This shape is
directly reusable by Scout with two substitutions already required by the spec's constraints:
`@scout.llm_chat(temperature: 0.0)` instead of `Llm::BaseAiService#chat` (Captain's per-feature
model-routing infrastructure, `Llm::FeatureRouter`, is Captain-only and would break the "one
provider/key per Scout account" constraint from `ScoutAccountConfig`), and a Scout-owned
`ActionClassifierSchema`/reason list instead of `Captain::AssistantActionSchema`'s support-domain
`REASONS` (`enterprise/lib/captain/assistant_action_schema.rb`). The prompt-building helper
(`Captain::Llm::AssistantResponseInspectionHelpers#assistant_response_inspection_prompt`,
`enterprise/app/services/captain/llm/assistant_response_inspection_helpers.rb`) is similarly
small and mirrors what `AgentRunner#instrumentation_params` already builds (a `{role:, content:}`
array) — Scout's classifiers build their own equivalent prompt-formatting from the same
message-history shape `AgentRunner` already produces, rather than including Captain's
enterprise-only helper module.

**Alternatives considered**: Reusing Captain's `Llm::BaseAiService`/`AssistantActionSchema`/
`AssistantResponseInspectionHelpers` directly (via `include`/inheritance across the OSS-Enterprise
boundary) — rejected: those are Enterprise-only, Captain-domain-specific (support reasons,
per-feature model routing that assumes an installation-wide `Llm::FeatureRouter`, not a
per-account `ScoutAccountConfig`), and Constitution Principle V requires Enterprise-only behavior
to stay decoupled from OSS/fork-owned code rather than creating a reverse dependency from
`custom/` onto `enterprise/`.

## 3. Reply-vs-reality grounding — adapting `AssistantFalsePromiseService`

**Decision**: `Custom::Scout::ClaimConsistencyService#check(message_history:, assistant_response:,
recorded_tool_calls:)` calls `@scout.llm_chat(temperature: 0.0).with_schema(
Custom::Scout::ClaimConsistencySchema).with_instructions(...).ask(...)`, where the prompt includes
the turn's `recorded_tool_calls` (from `CallRecorder`, §1) as explicit grounding context alongside
the conversation history and drafted reply. The schema's `decision` enum is
`safe | false_promise | false_completed_action` (three values, vs. Captain's two —
`false_completed_action` is new, per the spec's clarified scope covering both a broken future
promise of *any* action and a false claim that something already happened).

**Rationale**: Read `Captain::Llm::AssistantFalsePromiseService`
(`enterprise/app/services/captain/llm/assistant_false_promise_service.rb`): structurally identical
shape to the action classifier (one `with_schema` call, same rescue/normalize pattern), but its
`detect` method only ever receives `message_history:`/`assistant_response:` — never tool-call data
— because `Captain::AssistantFalsePromiseSchema`'s two decisions (`safe`/`future_work_promise`,
`enterprise/lib/captain/assistant_false_promise_schema.rb`) only need to judge the reply's *text*
against conversation context, not against ground truth of what actually ran. That is precisely why
this detector, unmodified, cannot catch the Scout bug that motivated this feature (a reply claiming
a *completed* action with no matching tool call) — confirmed by reading the schema and the prompt
helper together: nothing in Captain's inspection prompt carries tool-call data. Scout's
`ClaimConsistencyService` prompt explicitly includes `recorded_tool_calls` (tool name, arguments,
and outcome — see §1) as a labeled context block, giving the model the grounding it needs to
distinguish "claims a future action" (no tool call exists for it) from "claims a completed action"
(a tool call for it either doesn't exist, or exists but has an `error` key — clarified spec
decision) from "safe" (a matching successful tool call exists, or no completion/future claim is
made at all).

**Alternatives considered**: Two separate schemas/services (one Captain-style textual
`false_promise` detector, one new tool-grounded `false_completed_action` detector) — rejected as
unnecessary duplication of the LLM call and prompt-formatting code; a single grounded call can
judge both categories in one pass since the tool-call context is a strict superset of what the
textual-only judgment needs (the model can still flag `false_promise` for a future-work claim even
when no relevant tool call exists in the recorded list at all, exactly as Captain's own detector
does today for the promise-only case).

## 4. Orchestration order and the repair-and-reverify loop

**Decision**: `Custom::Scout::ResponseAuditor#audit(chat:, response_text:, message_history:,
recorded_tool_calls:)`, called once from `AgentRunner#process_response` right after
`parse_structured_response` succeeds and before `dispatch_outgoing_reply`, runs:
`ActionClassifier` (only if conversation still `pending`) → if `handoff`, call
`HandoffService#perform(reason: action_reason)` and stop (no further checks, no reply dispatched
by the auditor's caller for that turn). Otherwise, `ClaimConsistency` (only if still `pending`) →
if `false_promise`/`false_completed_action`, send one repair instruction via `chat.ask(...)` on the
*same* `chat` object already carrying history/tools/schema, then re-run `ActionClassifier` (if
still `pending`) and re-run `ClaimConsistency` once more → if still inconsistent, call the existing
`AgentRunner#perform_fail_safe_handoff` path. If `safe` (initially or after repair), the caller
proceeds to `dispatch_outgoing_reply` with the (possibly repaired) reply text.

**Rationale**: This exact ordering — action classifier always first, consistency detector second
and only when still pending, repair via the live `chat` object, reverify both — mirrors
`Captain::Conversation::V1ActionClassifier`/`V1FalsePromiseHandler`
(`enterprise/app/jobs/captain/conversation/v1_action_classifier.rb`,
`v1_false_promise_handler.rb`), confirmed by reading both job modules: `classify_v1_response_action`
runs first and short-circuits (`return if legacy_v1_handoff_token?`,
`mark_v1_false_promise_handoff_fallback` sets `action: 'handoff'` directly rather than going through
a second classifier call), and `repair_v1_false_promise_response` regenerates via
`Captain::Llm::AssistantChatService#generate_response` with a *rebuilt* message history (Captain
reconstructs history from scratch each repair) — whereas the spec's source document explicitly
simplifies this for Scout: since `AgentRunner` already keeps one live `RubyLLM::Chat` object per
turn with history/tools/schema already loaded, the repair instruction can just be
`chat.ask(repair_instruction)` on that same object, no history reconstruction needed. The repair
instruction itself is an internal-only message (never surfaced to the customer, satisfying spec
FR-011), following the same "internal instruction, not a customer message" framing as Captain's own
`FUTURE_PROMISE_REPAIR_INSTRUCTION` constant — Scout's version additionally covers the
`false_completed_action` case (asking the model to either call the missing tool now if still
appropriate, or honestly state it hasn't been done yet, rather than only covering future-promise
repair).

Escalating to `AgentRunner#perform_fail_safe_handoff` (rather than a bespoke handoff path) after a
failed reverification satisfies spec FR-006 with no new customer-message-creation call site (FR-010)
— this is the same fail-closed path Phase 057/058's predecessor phases already established and
already covers "never expose an unresolved/inconsistent reply to the customer."

**Alternatives considered**: Rebuilding message history from scratch for the repair call (matching
Captain's `regenerate_v1_false_promise_response` exactly) — rejected per the spec's source
document's explicit simplification: `AgentRunner` already holds one live `chat` per turn, so
reusing it is strictly simpler and loses no context Captain's rebuild-from-scratch approach would
have had.

**Flagged risk (pre-existing, not introduced by this feature; cross-validated)**: The repair
`chat.ask(...)` call reuses the *same* `chat` object the main turn already built with both
`with_schema(...)` and `with_tool(...)` active — a combination `AgentRunner` has used for every
turn since Phase 057, not something new here. Reading the installed Gemini provider adapter
(`ruby_llm-1.15.0/lib/ruby_llm/providers/gemini/chat.rb#render_payload`/`structured_output_config`)
confirms it unconditionally sets `generationConfig.responseMimeType: 'application/json'` (plus
`responseJsonSchema`/`responseSchema`) whenever a schema is present, in the same request as
`tools`/`toolConfig` whenever tools are present — the two do not share a JSON key (which is what
Phase 057's research checked and confirmed), but the Gemini *API itself* has a documented history
of rejecting `responseMimeType: application/json` combined with function/tool calling in the same
request (independent of the `ruby_llm` gem — a provider-level constraint, and it's unconfirmed
whether it still applies to the Gemini API versions/models `response_json_schema_supported?` gates
on, i.e. ≥2.5). This is out of scope to fix in this feature — it's inherited, unchanged, from
`AgentRunner`'s existing chat setup — but it should be verified empirically against a live Gemini
model during implementation (e.g. a quickstart walkthrough run with a Gemini-configured
`ScoutAccountConfig`) rather than assumed safe on the strength of Phase 057's key-collision-only
check.

## 5. Feature flag and migration shape

**Decision**: One new boolean column, `feature_response_auditor` on `ichatr_scouts`, `null: false,
default: false`, added via a single additive migration following the exact pattern of the existing
`feature_memory` column. `AgentRunner` checks `@scout.feature_response_auditor?` (Rails' automatic
boolean predicate method, same as the existing `@scout.feature_memory?` call site) once, gating the
entire `ResponseAuditor` call.

**Rationale**: `feature_memory` was added via `change_table :ichatr_scouts, bulk: true do |t|
t.boolean :feature_memory, null: false, default: true end`
(`db/migrate/21260819000005_add_pipeline_fields_to_ichatr_scouts.rb:7`) with no dedicated index,
no foreign key, and no frontend toggle — confirmed by searching `app/javascript` for
`feature_memory`/`featureMemory`: the only hits are Captain's *own* `feature_memory` (assistant
config, a different column on a different table), not Scout's. Scout's `ScoutSettings.vue` page
has no boolean feature toggles at all today; the column is read/written via the existing Rails
console/seed/API surface, matching how `feature_memory` itself is operated today. This precedent
directly supports the spec's User Story 3 (operators can enable "this safety net per account") and
FR-007/FR-008 without requiring new frontend work, which the spec's source document does not list
as in-scope.

**Alternatives considered**: Two independent flags mirroring Captain's
`captain_v1_action_classifier`/`captain_false_promise_harness_enabled`
(`account.feature_enabled?(...)` calls in the Captain job modules, §4) — explicitly rejected by the
spec's source document: Scout uses one flag for both auditors together, since (unlike Captain's
account-level `feature_enabled?` flags, which gate installation-wide Captain features) Scout's flag
is a plain scoped column on the `Scout` record itself, and splitting one cohesive safety net into
two independently-toggleable pieces adds configuration surface the spec does not call for.

## 6. Auditor-failure fallback and quota/usage accounting

**Decision**: Every new LLM-backed call (`ActionClassifierService#classify`,
`ClaimConsistencyService#check`, and the repair `chat.ask` inside `ResponseAuditor`) is wrapped in
`rescue StandardError => e; ChatwootExceptionTracker.new(e, account: @account).capture_exception;
Rails.logger.warn(...)`, returning a "no decision" sentinel that `ResponseAuditor` treats as "skip
remaining audit steps, deliver the original reply as-is" — never as "block delivery." No new
`responses_consumed` increment is added anywhere in the new code; the existing single increment in
`AgentRunner#dispatch_outgoing_reply` (`@scout.update!(responses_consumed: ...+ 1)`) already fires
exactly once per turn regardless of how many auditor/repair LLM calls preceded it, since none of
the new services call `dispatch_outgoing_reply` or increment the counter themselves.

**Rationale**: This exactly matches both Captain's own per-call rescue pattern (§2/§3 above, both
`classify`/`detect` catch `StandardError` and return an error-flagged hash rather than raising) and
`AgentRunner#perform`'s existing top-level rescue
(`custom/app/services/custom/scout/agent_runner.rb:26-30`), so no new failure-handling pattern is
introduced. Token usage from the extra calls is still captured by the existing token telemetry
(`instrument_llm_call`, already `include`d by `AgentRunner`/`BaseTool` via
`Integrations::LlmInstrumentation`) — satisfying the spec's Assumptions note that "extra tokens are
captured by telemetry but never billed against `responses_quota`" without any new code, since
`responses_quota`/`responses_consumed` and LLM-call telemetry are already two separate, already-
implemented counters (Phase 11) that this feature does not need to touch.

**Alternatives considered**: A shared "audit failed" flag threaded through `ResponseAuditor`'s
return value that `AgentRunner` checks before dispatch — unnecessary; since every auditor-side
failure already resolves internally to "treat as safe, proceed to dispatch," the caller
(`AgentRunner#process_response`) doesn't need to know *why* the audit step was skipped, only that
it was — matching Constitution Principle II (no added surface for a distinction nothing consumes).

## 7. Enterprise dual-tree check

**Decision**: No Enterprise-side changes needed.

**Rationale**: All new classes (`ActionClassifierService`, `ActionClassifierSchema`,
`ClaimConsistencyService`, `ClaimConsistencySchema`, `ResponseAuditor`, `CallRecorder`) are
fork-owned code under `custom/`, with no upstream or `enterprise/` counterpart to keep in sync.
Captain's `enterprise/` files are consulted as read-only architecture reference (per the spec's
source document's licensing caveat) and are not modified, extended, or depended on at runtime.
