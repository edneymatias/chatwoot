# Phase 0 Research: Scout V2 Typed Instructions, Playbook Index, and Mid-Turn Playbook Activation

Source brief has zero open questions (`docs/kanban/ciclo 13/scoutv2/briefs/04-instructions-indice-open-playbook.md`,
confirmed by `checklists/requirements.md`). This document resolves *implementation* unknowns
found while reading the existing v2 engine (Briefs 01–03, already merged) that the brief and
spec don't spell out verbatim.

## 1. Mid-turn tool injection mechanism

**Decision**: `TurnRunner` builds the `RubyLLM::Chat` object first (`@scout.llm_chat.with_instructions(...)`),
then calls `chat.with_tool(...)` for every base/state tool, then — only when no playbook is
forced by state — constructs `OpenPlaybook` **with a reference to that same live `chat` object**
and adds it last. `OpenPlaybook#execute` calls `@chat.with_tool(...)` directly for the opened
playbook's declared tools.

**Rationale**: Verified in `ruby_llm-1.15.0/lib/ruby_llm/chat.rb` (read from the running
container, `bundle show ruby_llm` → `/gems/ruby/3.4.0/gems/ruby_llm-1.15.0`): `with_tool` mutates
`@tools` in place and `Chat#complete`/`handle_tool_calls` re-enter and re-read `@tools`/`@messages`
on every loop iteration (`halt_result || complete(&)`). A tool instance holding the chat
reference can therefore add tools mid-`chat.ask`, and the *next* tool-loop iteration already sees
them — exactly the mechanism `design.md` §4.2 documents and the only way to satisfy FR-014
("available... within the same turn... without ending the turn") without pre-registering every
playbook's tools up front (rejected in `design.md` §4.10 as "the tool bloat of v1 under a new
name").

**Alternatives considered**: Pre-register all playbooks' tools unconditionally (rejected: tool
bloat, defeats the whole epic's premise). Defer activation to the next turn (rejected: FR-013
explicitly requires same-turn, "not deferred").

## 2. What "capabilities" and "exits become available" concretely means in this phase

**Decision**: This phase does **not** build a capability-tool adapter or an exit-tool mechanism.
`open_playbook` only injects the opened playbook's declared `tools:` into the live chat (the one
literal RubyLLM mechanism that exists today) and returns its `body` as the tool result. Declared
`requires` (capabilities) and `exits` become "available" in the same sense they already are for a
*state*-activated playbook today — as data on the `Playbook` object reachable through
`ScoutConversationState`/`RoutingSnapshot` — not as new injected tool objects.

**Rationale**: `custom/app/services/custom/scout_v2/capabilities/catalog.rb` only has a
`KNOWN_NAMES` allowlist used by the boot-time `Playbook::Validator`; there is no
`CapabilityRegistry`/adapter anywhere in the tree. `design.md` §6 places the capability registry
and adapters in **Fase 2**, and exit tools/handlers in **Fase 1's "Escalation" sub-slice**, which
Brief 04 itself excludes ("Fora de escopo: Escalation, `exit_handoff` e o mecanismo de exits —
brief 05"). Today's state-activated path (`TurnRunner#build_tools`) *already* does nothing with
`playbook.requires`/`playbook.exits` beyond carrying them on the `Playbook` struct and computing
`unmet_requires` for telemetry — `open_playbook` reaching exact parity with that existing
behavior is the correct, non-speculative scope. The brief's own test plan (§8) confirms this: the
only asserted `open_playbook` outcomes are "tools catalog contains the opened playbook's tools",
"body came back as the result", and "`activation_reason` persisted as `trigger`" — nothing about
a new capability or exit mechanism.

**Alternatives considered**: Building a minimal capability-tool stub now (rejected: speculative,
no consumer, explicitly deferred by the brief and the design doc's phase table — violates
Constitution Principle II). Blocking `open_playbook` on unsatisfied `requires` (rejected: no FR
asks for this, and the one existing playbook fixture with `requires` — `agendamento` — isn't part
of this brief's fixture set per the spec's Assumptions).

## 3. `activation_reason` telemetry accuracy (adjacent fix required by this feature)

**Decision**: `TurnRunner#metadata_for` currently hardcodes `activation_reason: 'state'` whenever
`decision.playbook.present?`. This becomes provably wrong the first time a conversation carries a
playbook opened via `open_playbook` into a later turn (Router's continuity rule keeps
`decision.playbook` present via `ctx.active_playbook`, but the real persisted reason is
`trigger`). Fix: read the real `ScoutConversationState#activation_reason` for the conversation
when populating turn metadata, instead of assuming `'state'`.

**Rationale**: `ScoutConversationState.activation_reason` enum already includes `trigger`
(delivered by Brief 03 in anticipation of this exact brief) precisely so
`design.md` §4.9 ("o trace de cada turno passa a carregar... `activation_reason`... responde *por
que esta playbook*") stays true. This is a direct, narrowly-scoped consequence of adding real
`trigger` activations, not scope creep — leaving the hardcoded literal would silently regress
observability for every trigger-activated conversation from this feature onward.

**Alternatives considered**: Leave hardcoded (rejected: silently wrong telemetry the moment this
feature ships real trigger activations — an adjacent regression this feature itself introduces).
Add `activation_reason` to `RoutingSnapshot` instead of querying `ScoutConversationState` again in
`metadata_for` (rejected: `RoutingSnapshot` is built once at the top of the turn, before
`persist_state_activation_if_needed` runs, so it would carry the *previous* turn's reason, not the
one just persisted for *this* turn's initial decision. Metadata is computed after that
persistence and immediately before `chat.ask`, so a direct read is what genuinely reflects
"why this playbook, at the start of this turn").

## 4. Instructions block section headers

**Decision**: Use literal English bracket headers — `[Identity]`, `[Communication]`, `[Memory]`,
`[Safety]` — one per section, in that fixed order, each produced by its own builder class under
`custom/app/services/custom/scout_v2/instructions/`.

**Rationale**: The spec (FR-001, Key Entities, all three US1 acceptance scenarios) names these
four sections in English as the canonical, testable vocabulary — unlike v1's descriptive
Portuguese headers (`[Identidade e Escopo]`, `[Diretrizes de Segurança e Resposta]`), which mix
multiple concerns per header (exactly the thing this feature dismantles). A literal, stable
4-header format makes "exactly four sections and nothing else" (AC1) trivially assertable by
regex without coupling tests to prose wording, and cleanly distinguishes the new typed block from
v1's block by construction (reinforcing FR-017's "v1 unchanged" — no shared header vocabulary to
accidentally couple the two).

**Alternatives considered**: Reuse v1's Portuguese header style (rejected: reintroduces exactly
the "everything is prose, nothing is structurally verifiable" problem the design doc's
Testability section, §7, calls out as the reason to do this work at all).

## 5. Playbook index line format and ordering

**Decision**: One line per catalog entry, `- {name}: {trigger}` (machine `name` — the exact token
`open_playbook` accepts — plus the human-authored `trigger` sentence), in the catalog's existing
iteration order (currently: `Loader`'s alphabetical-by-filename order via `Dir.children(...).sort`).
Header `[Playbook Index]`; when the catalog is empty, the block still opens with the header
followed by a single explicit "no playbooks enabled" line — never an empty/omitted block (FR-018,
SC-007 require the block to always be present).

**Rationale**: `name` is what the model must pass into `open_playbook(name: ...)` — showing it
verbatim (not just `title`) makes the affordance directly actionable, matching the Captain V2
precedent cited in the design doc (`- {title}: {description}, use handoff_to_{key}` — one
authoritative identifier per line). Reusing the catalog's natural order avoids introducing a new,
undocumented ordering rule; nothing in the spec requires priority-sorting the index (only the
*router* is priority-ordered, for a different purpose — arbitrating between simultaneously-matching
`when_state` playbooks, which doesn't apply to a flat display list).

**Alternatives considered**: Priority-ordered index (rejected: no FR asks for it, and conflating
router precedence with index display order invites someone to later assume the index order has
routing significance, which it explicitly does not per Decision 5 in `design.md` §4.3 — trigger
exclusivity is convention-in-prose, not order-based).

## 6. Tool-class resolution shared between state and trigger activation

**Decision**: Extract `TurnRunner::TOOL_CLASSES` into a new
`Custom::ScoutV2::Tools::Registry.build(tool_names, scout:, conversation:)`, used by both
`TurnRunner` (state-forced playbook's tools) and `OpenPlaybook` (trigger-opened playbook's
tools).

**Rationale**: Both call sites need the identical "playbook tool name → instantiated tool" step.
Duplicating the one-entry `TOOL_CLASSES` hash into `OpenPlaybook` would immediately drift the
moment a second mutation tool is registered for a future playbook — the exact churn pattern
`design.md` §1.1 measured and is trying to eliminate ("regra escrita três vezes"). Naming mirrors
the existing `Custom::ScoutV2::Predicates::Registry` convention already in the tree.

**Alternatives considered**: Duplicate the hash in `OpenPlaybook` (rejected: guaranteed drift).
Pass `TurnRunner::TOOL_CLASSES` directly into `OpenPlaybook` (rejected: couples a tool class to a
service class's private constant instead of a shared, independently testable registry).

## 7. Tool-call instrumentation/recording parity for trigger-injected tools

**Decision**: `TurnRunner` passes a `tool_wrapper:` callable (its own `#wrap_tool` from the
existing `CallRecorder` concern) into `OpenPlaybook`'s constructor; `OpenPlaybook` applies it to
every tool it injects via `@chat.with_tool(...)`, and is itself wrapped the same way when
`TurnRunner` adds it to the chat.

**Rationale**: `CallRecorder#wrap_tool` closes over the `TurnRunner` instance's
`@recorded_tool_calls` array, which is what `perform` returns as `tool_calls:` and what
`turn_runner_spec.rb`'s existing instrumentation tests assert against. Without this, a tool
injected mid-turn via `open_playbook` would silently execute unrecorded — an observability gap
for exactly the trigger-activation path this feature is supposed to make debuggable
(`design.md` §4.9's whole point). Dependency-injecting the wrapper keeps `OpenPlaybook` ignorant
of `CallRecorder`'s internals.

**Alternatives considered**: Have `OpenPlaybook` include `CallRecorder` itself (rejected: would
record into a *second*, disconnected `@recorded_tool_calls` array scoped to the tool instance,
never surfacing in `TurnRunner#perform`'s return value).

## 8. No new Scout admin UI

**Decision**: This phase adds `tone`/`response_length`/`greeting` as plain model columns +
enums, reachable through Rails console / direct model writes / specs. It does **not** touch
`Api::V1::Accounts::ScoutsController#scout_params` or `ScoutGeneralSettings.vue`.

**Rationale**: Brief §5 ("Escopo preliminar") lists exactly four touch points and none of them is
the controller or frontend; every FR/acceptance-scenario in the spec is phrased and testable at
the model/prompt-composition level (`Given a scout's configured tone... is changed`), never "an
admin changes it in the settings screen". Wiring the settings screen without a documented
requirement is scope not asked for (Constitution Principle II, and the top-level "NEVER infer
extra scope" delivery contract). A follow-up brief can wire the UI once an operator actually needs
to set these per account.

**Alternatives considered**: Add the three fields to `scout_params`'s allowlist "for
completeness" (rejected: nothing in this feature's scope exercises that path, and the constitution
explicitly forbids speculative scope expansion "while you're at it").
