# Phase 0 Research: Scout V2 Trigger-Based Playbook Interruption over an Active Procedure

Source brief has zero open questions (`docs/kanban/ciclo 13/scoutv2/briefs/11-interrupcao-por-trigger.md`,
Status "Pronto para speckit", 7 decisions already resolved, confirmed by `checklists/requirements.md`).
This document resolves *implementation* unknowns found while reading the existing Brief 04 code
(`custom/app/services/custom/scout_v2/{turn_runner,router}.rb`,
`custom/app/services/custom/scout_v2/tools/open_playbook.rb`,
`custom/app/services/custom/scout_v2/playbook/index_builder.rb`) that the brief and spec describe
behaviorally but don't spell out as a concrete Ruby shape.

## 1. Single "openable set" definition, shared by the index and by `open_playbook`

**Decision**: New `Custom::ScoutV2::Playbook::OpenableSet.call(catalog:, pinned:)`, returning a
`Custom::ScoutV2::Playbook::Catalog` (the existing `Enumerable` value object, not a new type):
`pinned` (the `Router::Decision#playbook`, blank or present) determines the result — the full
`catalog` unchanged when `pinned` is blank, a new `Catalog` wrapping only
`catalog.select { |pb| pb.when_state.blank? }` when `pinned` is present. `TurnRunner#setup_chat`
computes this **once** per turn, immediately after `Router.call` returns, and threads the same
`Catalog` instance into both `Playbook::IndexBuilder.call(openable)` (replacing today's
`IndexBuilder.call(catalog)`) and `Tools::OpenPlaybook.new(..., openable: openable, ...)`.

**Rationale**: FR-003's "no playbook outside the set, no playbook missing from it" and Decision 3
("o índice lista exatamente o conjunto que `open_playbook` aceita") both name *one* set, not two
independently-computed lists that could drift. Reusing `Catalog` (already `Enumerable`, already
exposes `#playbooks`/`#[]`/`#any?`/`#none?` via `Enumerable`) means `IndexBuilder`'s signature and
list rendering need no change — it already accepts anything responding to `#playbooks`; only its
call site changes what it's handed — and avoids introducing a second list-representation (plain
`Array`) that would need its own `#[]`/lookup helper duplicating `Catalog#find_by_name`.

**Empty-set line**: `IndexBuilder::EMPTY_CATALOG_LINE` ("Nenhum procedimento específico habilitado
no catálogo.") was written for Brief 04, where the index always listed the full catalog. Once the
index lists the openable set, the empty case also occurs while a procedure is pinned and the
catalog has no situational playbook — the shipped catalog today (`qualificacao` only). The old line
would then sit right above `qualificacao`'s Block 3 body, telling the model no procedure is enabled
while one is active. The constant is renamed and reworded to `EMPTY_INDEX_LINE = 'Nenhum playbook
disponível para abrir neste turno.'`, true in both empty cases (FR-003, Edge Cases 1 and 2). It has no
other reference in the repo (`grep EMPTY_CATALOG_LINE` → only `index_builder.rb`).

**Alternatives considered**: A plain `Array<Playbook>` (rejected: loses `Catalog#[]`/`#any?` for
free, and `IndexBuilder` would need a signature change to accept either shape — more surface
than necessary). Computing the set twice, once in `TurnRunner` for the index and once in
`OpenPlaybook` for validation (rejected: exactly the "duplicated rule" drift risk FR-003/Decision 3
exist to prevent, and research §6 of Brief 04 already established the precedent of extracting a
shared definition — `Tools::Registry` — for the same reason).

## 2. Categorization signal: `playbook.when_state.blank?`

**Decision**: A playbook is "situational" (interruption) iff `playbook.when_state.blank?` — the
existing `Playbook#when_state` array, populated by `Loader#normalize_when_state` (empty array when
the frontmatter omits `when_state` or declares `[]`). No new field on the `Playbook` `Data.define`,
no `Loader`/`Validator` change.

**Rationale**: FR-001 mandates deriving the category from the existing activation condition, "not
from a new declared attribute" — `when_state.blank?` is that condition verbatim (it's exactly what
`Router#find_matching_playbook` already uses to decide whether a playbook can ever win a state
match: `playbook.when_state.present? && Predicates::Evaluator.call(...)`). A playbook with
`when_state: []` structurally can never win the router's state match, which is the definition of
"never activates by state" the spec's Key Entities section gives for "Situational (Interruption)
Playbook".

**Alternatives considered**: A new `type: situational|procedure` frontmatter field (rejected
explicitly by Decision 1 of the brief: "não há campo novo no frontmatter... um campo explícito
duplicaria uma informação que o loader já tem").

## 3. Takeover mechanism: `with_instructions` + `with_tools(replace: true)`, rebuilt from data already on hand

**Decision**: `OpenPlaybook#execute`, when the resolved playbook is situational, calls:
1. `@chat.with_instructions(@turn_setup.baseline_instructions)` — `baseline_instructions` is a `String`
   precomputed once by `TurnRunner#setup_chat` as `build_instructions(nil, nil, openable)` (the
   Instructions block + Playbook Index block over the *same* `openable` set, with no Block 3 —
   i.e. exactly what `TurnRunner` would build for "nothing pinned", verified reusable because
   `build_instructions` only reads `ctx` inside its `if playbook.present?` branch).
2. `@chat.with_tools(*@turn_setup.baseline_tools, self, *interruption_tools, replace: true)` where
   `baseline_tools` is the injected `Array` of the **already-wrapped always-on tool instances**
   `TurnRunner` registered at turn setup (today exactly `[search_knowledge_base]`), `self` is the
   currently-executing `OpenPlaybook` instance (already the object `chat.tools[:open_playbook]`
   points to, already wrapped by `TurnRunner#wrap_tool` — `CallRecorder#wrap_tool` redefines
   `execute` as a singleton method on the same object, so re-adding it performs no new wrapping),
   and `interruption_tools` is `Tools::Registry.build(playbook.tools, ...).map { |t| @turn_setup.tool_wrapper.call(t) }`.

No `active_playbook`/`activated_at`/`activation_reason` write (Decision 5/FR-011) — this branch
never touches `ScoutConversationState`.

**Rationale — confirmed against the actual gem, not assumed**: read `ruby_llm-1.15.0/lib/ruby_llm/chat.rb`
in the running container. `with_instructions(instructions, append: false, replace: nil)` defaults to
**replace** (`replace_system_instruction`, which mutates `@messages` in place, swapping the single
system message's content) — exactly the "instructions block replaced" behavior Decision 4/FR-006
require, verbatim, no extra flag needed at the call site. `with_tools(*tools, replace: false,
choice:, calls:)` does `@tools.clear if replace` then re-adds each given tool via `with_tool` —
confirms `with_tools(*array, replace: true)` is the literal "drop everything, keep only what's
listed" primitive Decision 4/FR-007 need. `with_tool(tool)` keys `@tools` by `tool.name.to_sym`, so
re-adding the same `self` object is idempotent, not a second wrap.

`TurnRunner` owns the single definition of the always-on tool list (`always_on_tools`, built once in
`#setup_chat`), and the same instances go to both the initial registration and `OpenPlaybook`'s
`TurnSetup#baseline_tools`. Brief 05's exit action is then added in one place and is automatically kept by
every takeover. There is no chicken-and-egg problem: the list passed in excludes `open_playbook`
itself, which `takeover!` adds as `self`.

**Alternatives considered**: Re-instantiating `SearchKnowledgeBase` inside `OpenPlaybook#takeover!`
(rejected in `/speckit.analyze` finding B1: it creates a second definition of the always-on
baseline that drifts as soon as Brief 05 adds a tool to it). Threading a `Proc` that closes over the
`OpenPlaybook` instance (rejected: needs a mutable setter after construction; excluding `self` from
the injected list and adding it at takeover time achieves the same thing without mutation). Reading
`@chat.tools` to recover the baseline by name (rejected: after additive registration of a
state-pinned playbook's tools, the hash no longer distinguishes baseline tools from the interrupted
procedure's tools).

## 4. Two execution paths inside one tool, selected by openable-set membership + categorization

**Decision**: `OpenPlaybook#execute(name:)`:
```ruby
playbook = @openable[name]
return { error: "..." } if playbook.blank?          # covers unknown name AND outside this turn's openable set — same error shape
playbook.when_state.blank? ? takeover!(playbook) : activate_procedure!(playbook)
{ body: playbook.body }
```
`activate_procedure!` is **exactly** today's Brief 04 body (additive `@chat.with_tool` per
declared tool, then `ScoutConversationState#record_trigger_activation!`) — reachable only when
`@openable` is the full catalog (nothing pinned), since a `when_state`-bearing playbook is never a
member of the situational-only `openable` set built when something *is* pinned. This is the
concrete mechanism behind FR-013/Decision 7 ("unchanged from Brief 04").

**Rationale**: `@openable[name]` (`Catalog#find_by_name`/`#[]`) already returns `nil` for both "not
in the catalog at all" and "in the catalog but excluded from this turn's openable set" (e.g. a
`when_state` playbook while pinned) — one error branch satisfies both FR-005 (reject
outside-the-set) and the pre-existing "unknown name" case (Brief 04's FR-016) without needing to
distinguish *why* the name didn't resolve, matching the brief's own framing ("rejeita nome fora do
conjunto abrível com erro de tool" — one rejection path, one error shape). Branching on
`playbook.when_state.blank?` *after* that resolves cleanly because, by construction, the only way a
`when_state`-bearing playbook reaches this line is when `@openable` is the unfiltered full catalog
(nothing pinned) — so `activate_procedure!` never needs its own "is something pinned" check.

`takeover!` and `activate_procedure!` are each called once. AGENTS.md discourages one-use private helpers unless
they make the main flow meaningfully easier to read. Here they do: `execute` stays a lookup, a guard and a
two-way dispatch, and each named method holds one path's side effects, which is exactly the Path A/Path B split
that the contract, the mutants (M3–M5) and the unit examples refer to. Inlining both would put a
`with_instructions` + `with_tools(replace: true)` block and a `with_tool` loop + state write side by side in one
conditional, hiding which effects belong to which path.

**Alternatives considered**: A third explicit "pinned but tried a when_state playbook" error branch
distinct from "not found" (rejected: no FR asks for a differentiated error message, and `Catalog#[]`
already can't tell the two cases apart without an extra full-catalog lookup that exists nowhere
else in this design — adding it would be speculative precision Constitution Principle II forbids).

## 5. `open_playbook`'s own availability gate changes from "nothing pinned" to "openable set non-empty"

**Decision**: `TurnRunner#build_tools(decision, openable, chat)` adds `Tools::OpenPlaybook` iff
`openable.any?` (previously: iff `decision.playbook.blank?`). The interrupted/pinned procedure's
own declared tools (`decision.playbook.tools`) are still added **additively**, unconditionally,
whenever `decision.playbook` is present — that part of Brief 04's behavior is untouched; only the
`open_playbook` gate condition changes, per Decision 2 ("`open_playbook` é oferecida em todo turno
em que há algo que ela possa abrir... substitui o FR-012 do brief 04").

**Rationale**: FR-004 states the gate precisely ("offered whenever the openable set... is
non-empty, and MUST NOT be offered when... empty — including when a procedure is pinned but the
catalog has no situational playbook, and when no procedure is pinned but the catalog is entirely
empty"). `openable.any?` is that predicate verbatim, for both branches of `OpenableSet.call`.

**Alternatives considered**: Keep the old `decision.playbook.blank?` gate and additionally offer a
*second*, separately-gated tool for the pinned case (rejected: Decision 2 is explicit that it's the
*same* `open_playbook` action, just accepting a narrower set — two tool names would need two
descriptions the model has to disambiguate, solving nothing FR-004 doesn't already solve with one
gate).

## 6. `open_playbook`'s constructor signature changes — a cutover, not an addition

**Decision**: `Tools::OpenPlaybook.new(scout, conversation, chat:, openable:, turn_setup:)`
replaces Brief 04's `catalog:` keyword with `openable:` (a `Catalog`, same shape, narrower
contents) and replaces `tool_wrapper:` with `turn_setup:`, an
`OpenPlaybook::TurnSetup = Data.define(:baseline_instructions, :baseline_tools, :tool_wrapper)` defined in
`open_playbook.rb` (the `String` and the always-on tool `Array` from research §3, plus the unchanged wrapper
lambda). `TurnRunner` is the only caller in production code;
`custom/spec/services/custom/scout_v2/tools/open_playbook_spec.rb` is the only other caller (tests). Its
fixtures are rewritten first on the current signature (tasks.md T004). The subject then moves to the new
keywords in the same refactor commit as the production signature and the `TurnRunner` call site (T005), so
no commit leaves a caller on the old signature. Per Constitution Principle VI ("test and code disagree...
`spec.md` decides"), this `spec.md`'s FR-001/FR-002 supersede Brief 04's "any playbook persists as trigger"
fixture assumptions this existing spec currently pins: its two fixture playbooks both have
`when_state: []`, which under this feature makes *both* of them situational, so the existing "persists
`activation_reason: trigger`" assertion for one of them stops being the correct behavior to assert. The
brief's own §8 test plan already describes the replacement fixture shape: at least one situational and one
`when_state`-bearing playbook per context.

**Why `TurnSetup`, not three more keywords**: the flat form
`(scout, conversation, chat:, openable:, baseline_instructions:, baseline_tools:, tool_wrapper:)` has seven
parameters. RuboCop's `Metrics/ParameterLists` defaults to `Max: 5` with keywords counted, and neither
`.rubocop.yml` nor `.rubocop_todo.yml` changes that. AGENTS.md forbids new `Max`/`Exclude` entries, and Brief 04
already removed an inline `rubocop:disable Metrics/ParameterLists` from this same constructor
(`084-scout-instructions-open-playbook/tasks.md` T042). The three grouped values are all computed once by
`TurnRunner` at turn start and never change within the turn. `chat` and `openable` stay separate keywords
because `execute` uses them directly.

**Rationale**: Constitution Principle II (smallest change, no shim/dual-signature backward
compatibility layer for a fork-internal, single-caller class) and the top-level delivery contract's
"default clean cutover: migrate every caller; no shims, aliases, deprecated paths."

**Alternatives considered**: Keep `catalog:` and add `pinned:`/`openable:` as a second optional
keyword, computing the openable subset inside `OpenPlaybook` itself (rejected: reintroduces the
"index and `open_playbook` compute the set independently" drift research §1 rules out). Pass the
`TurnRunner` itself as `recorder:` instead of `tool_wrapper` (rejected: same parameter count, and it couples
the tool to the runner's whole interface instead of one lambda).

## 7. FR-014's "reviewable turn record" is already produced by existing instrumentation — no `lib/integrations/llm_instrumentation*.rb` change

**Decision**: No change to `Integrations::LlmInstrumentation`/`LlmInstrumentationHelpers`/
`LlmInstrumentationSpans`. `Custom::Scout::Tools::BaseTool#call` (which every tool, including
`OpenPlaybook`, already inherits and cannot bypass) already wraps every tool execution in
`instrument_tool_call(name, args) { super(args) }`, which opens its own nested OTel/Langfuse span
(`ATTR_LANGFUSE_OBSERVATION_TYPE = 'tool'`, input = `args.to_json`, output = `result.to_json`)
**while the turn's `agent_session`/`llm_call` span is still open** (the tool call happens inside
`chat.ask`'s tool loop, itself inside `instrument_llm_call`'s `yield`), so OpenTelemetry's ambient
context automatically nests it as a child of that turn's span. For an opened interruption this span
alone already carries: `tool_name: 'open_playbook'` (provable only via a same-turn model-initiated
call — a state-pinned playbook never produces this span, satisfying "opened by the assistant's own
initiative rather than pinned by routing") and `arguments: { name: <situational playbook name> }`
(which playbook). The same call is also appended by `CallRecorder#execute_and_record` to
`recorded_tool_calls`, which `TurnRunner#perform` returns as `tool_calls` — the playground endpoint
exposes it verbatim, while the inbox path (`ProcessMessageJob#dispatch_scout_v2`) discards it and
relies on the span. Both are fed by the same wrapped `execute`, so the playground `tool_calls` entry
is the observable proof the request spec asserts; the span itself is already covered generically for
every `BaseTool` by `custom/spec/services/custom/scout/tools/base_tool_spec.rb` and gets no
feature-specific spec (asserting it would need an OTel exporter the repo doesn't have). This is the
concrete mechanism behind FR-014/SC-006, inherited unmodified from Brief 04 (which already gave
`OpenPlaybook` this instrumentation by making it a `BaseTool` subclass) — no new code is needed to
produce it.

**Rationale**: `TurnRunner#metadata_for` (the turn-level `playbook`/`activation_reason` pair)
intentionally stays untouched: it reads `decision.playbook`/`conversation_state.activation_reason`
computed *before* `chat.ask` runs, describing *why this turn has the procedure it has* — a question
this feature's Decision 5 (interruption never persists) explicitly keeps unaffected by any
mid-turn interruption. Threading interruption awareness into that same pre-computed hash would
require either mutating an OTel span's attributes after code that already read them once (no such
re-entry point exists in `instrument_llm_call`/`instrument_agent_session` today — both call
`set_metadata_attributes` exactly once, before `yield`) or restructuring shared, broadly-used
instrumentation helpers (used by every other LLM call site: v1 Scout, Captain, Google Translate,
etc.) for a need this feature's own scope note (brief §5, §6) never actually asks to touch — the
per-tool-call span already answers the question the brief's Decision 6 poses ("fica no trace do
turno"), which is measurable in Langfuse today by filtering `tool_name = open_playbook` without any
code change, matching design.md §4.3's own stated mitigation ("observar `activation_reason` em
produção" was written before Brief 11 existed and refers to the *state*-activation counter; the
interruption-specific signal this brief adds is the tool-call span itself).

**Alternatives considered**: Add a second `span.set_attribute` call after `chat.ask` returns inside
`instrument_agent_session`/`instrument_llm_call`, reading a mutable hash `OpenPlaybook` writes into
(rejected: touches shared instrumentation infra used by every non-Scout LLM call site in the repo,
for a signal the existing per-tool-call span already provides — directly against Constitution
Principle II and brief §5's explicit 3-file scope, which never lists any `lib/integrations/`
file). Persist an ephemeral "last interruption this turn" value somewhere `metadata_for` could read
post-hoc (rejected: the only candidate storage is `ScoutConversationState`, and writing to it — even
transiently — is exactly what Decision 5/FR-011 forbid).

## 8. No new Scout admin UI, no migration, no schema change

**Decision**: This feature adds zero ActiveRecord columns and zero database migrations. Production
files: `custom/app/services/custom/scout_v2/turn_runner.rb`,
`custom/app/services/custom/scout_v2/tools/open_playbook.rb` and
`custom/app/services/custom/scout_v2/playbook/index_builder.rb` (empty-set line only, §1) changed,
plus one new file, `custom/app/services/custom/scout_v2/playbook/openable_set.rb`.

**Rationale**: Every FR is phrased at the prompt-assembly/tool-registration/state-non-mutation
level; `ScoutConversationState`'s schema (including the `trigger` enum value) was already delivered
by Brief 03/04 and needs no new column — `record_trigger_activation!` (existing method) is reused
as-is for the one path that still calls it (`activate_procedure!`), never called by the new
`takeover!` path.

## 9. Test strategy: real engine end to end, WebMock only at the provider HTTP boundary

**Decision**: Every acceptance scenario is covered by a `type: :request` example against
`POST /api/v1/accounts/:account_id/scouts/:scout_id/playground_messages` that runs the real
controller → `TurnRunner` → `Scout#llm_chat` → `RubyLLM::Chat` → `Router` →
`ScoutConversationState`. The only double is `stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})`,
with a sequenced `to_return` (function-call responses, then a text response). `Tools::OpenPlaybook`
unit examples use a real `RubyLLM::Chat` from `scout.llm_chat` and never call `ask`, so they make no
HTTP requests.

**Evidence (in-container probes, 2026-09-25, RubyLLM 1.15.0)**:
- `RubyLLM.context { |c| c.gemini_api_key = 'k' }.chat(model: 'gemini-2.0-flash')` builds a real
  `RubyLLM::Chat` offline. Two consecutive `with_instructions` calls leave exactly one system message
  with the latest content.
- The outgoing Gemini request carries the system instruction as `contents[0].parts[0].text` and the
  offered tools as `tools[0].functionDeclarations[].name`. These are the observable assertions at
  the boundary.
- In one stubbed response carrying `open_playbook` (which ran `with_instructions('BASELINE')` +
  `with_tools(self, replace: true)`) followed by `tool_a`, `open_playbook` returned its body. `tool_a`
  got `{error: "Model tried to call unavailable tool `tool_a`. ..."}` as its tool result, the loop
  continued, `ask` returned the final text, and the next provider request offered only
  `open_playbook`. This is the concrete behavior behind FR-016.

**Existing `turn_runner_spec.rb` examples**: they stub `scout.llm_chat` with an
`instance_double(RubyLLM::Chat)`. That is a pre-existing pattern this feature neither extends nor
rewrites (Principle VI: no drive-by specs). Every one of them still holds under the new gate. One
cutover (Brief 11 §5): the pinned tool-catalog example no longer asserts `open_playbook` absent, since
that held only because the shipped catalog has no situational playbook and would break once Brief 06
ships some; the request spec's procedure-only variant owns that gate. The nothing-pinned examples open
only `qualificacao` (Path B, unchanged) or an unknown name (`turn_runner_spec.rb:343,379,412`), so
the double never needs `with_tools`. The file runs as regression (quickstart §4).

**Fixture catalog**: `Dir.mktmpdir` + `FileUtils.cp` of the shipped `qualificacao.md` + inline
`File.write` of `pausa.md` (situational, no `tools:`, `priority: 20`) and `duvida_comercial.md`
(situational, `tools: [manage_opportunity]`, `priority: 5`), activated with
`with_modified_env SCOUT_V2_PLAYBOOKS_DIR:` (existing pattern, `turn_runner_spec.rb:221-224`).
`manage_opportunity` is the only name in `Tools::Registry`, so "procedure tools dropped" is proven
with `pausa` (declares none: `manage_opportunity` must disappear after the takeover), and "the
interruption's own tools added" is proven by `duvida_comercial` after `pausa` (it must come back).
`pausa`'s priority (20 > `qualificacao`'s 10) makes the pre-feature bug observable: had the
interruption persisted `active_playbook: pausa`, `Router#resolve_selected_playbook` would keep
`pausa` over `qualificacao` on the next turn. So the FR-012 example is red on any implementation that
persists.

**Alternatives considered**: Keep doubling `RubyLLM::Chat` and stubbing `scout.llm_chat` (rejected:
Principle VII forbids stubbing a model method, and a doubled chat can only prove the takeover via
"received with args" assertions, which Principle VII rules out as cosmetic). A committed fixture
directory (rejected: a copy of `qualificacao.md` would drift from the shipped file; the tmp-dir copy
always tracks it).

## 10. Same-step multiple tool calls and mixed Path A/B turns need no code

**Decision**: FR-016 and FR-017 are satisfied by the two paths from §4 combined with RubyLLM's
sequential tool loop (§9 evidence). No ordering guard, no "already pinned this turn" check, and no
mid-turn recomputation of the openable set.
- A situational takeover followed by more calls in the same response: each later call is looked up in
  the post-takeover `chat.tools`, and a removed tool gets RubyLLM's own error result (FR-016).
- Path B, then Path A (nothing pinned at turn start): Path B persists `trigger` and adds tools
  additively. Path A then replaces the tools with baseline + its own and writes nothing, so Path B's
  pin survives into the next turn (FR-017).
- Path A, then Path B: Path B adds its tools on top of the takeover set and persists `trigger`
  (unchanged Brief 04 behavior, FR-013).

**Rationale**: Principle II. Each case is a composition of already-specified behavior; the spec
pins the outcome so tests can guard it.
