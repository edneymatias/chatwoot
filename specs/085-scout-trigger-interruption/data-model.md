# Phase 1 Data Model: Scout V2 Trigger-Based Playbook Interruption over an Active Procedure

No schema change. No migration. Every entity below is either an existing persisted model (read,
never written differently than today) or a new/changed in-memory value object scoped to one
`TurnRunner#perform` call.

## 1. `ScoutConversationState` (existing model, `ichatr_scout_conversation_states` table) — unchanged shape, narrower write path

No new column, no new enum value (`trigger` already exists, delivered by Brief 03 ahead of Brief 04).

| Method | Called by | Changes in this feature? |
|---|---|---|
| `record_state_activation!` | `TurnRunner#persist_state_activation_if_needed` | No — router-driven state pin, entirely outside this feature's scope |
| `record_trigger_activation!` | `Tools::OpenPlaybook#activate_procedure!` (renamed private method; same call as Brief 04's `#execute` body) | No — same method, same arguments. Now reachable **only** for `when_state`-bearing playbooks (`when_state.present?`), which are members of `@openable` only when nothing is pinned (full catalog) |
| — (no call) | `Tools::OpenPlaybook#takeover!` | **New non-call**: the situational-playbook branch never touches `ScoutConversationState` — this is the concrete mechanism behind FR-011 |

**Invariant this feature adds** (enforced by construction, not a new validation): opening a
situational playbook (`when_state.blank?`) never calls any `record_*!`/`update!` method on
`ScoutConversationState`, regardless of whether a procedure was pinned before the interruption —
`takeover!` has no reference to `ScoutConversationState` at all, so there is no code path by which
it could write.

## 2. `Custom::ScoutV2::Playbook` (existing `Data.define`, unchanged shape)

No new fields. The one field this feature reads for a purpose it wasn't read for before:
`when_state` — already carried on every `Playbook` instance, now doubles as the situational/
procedure classification signal (research.md §2), read via `playbook.when_state.blank?` in
`Tools::OpenPlaybook#execute` and in the new `Playbook::OpenableSet.call`.

## 3. NEW: `Custom::ScoutV2::Playbook::OpenableSet` (stateless class method, no persistence)

```ruby
class Custom::ScoutV2::Playbook::OpenableSet
  class << self
    def call(catalog:, pinned:)
      return catalog if pinned.blank?

      Custom::ScoutV2::Playbook::Catalog.new(catalog.select { |pb| pb.when_state.blank? })
    end
  end
end
```

| Input | Type | Meaning |
|---|---|---|
| `catalog:` | `Custom::ScoutV2::Playbook::Catalog` | The full loaded catalog for this turn (`Playbook::Loader.load_all`'s result, already computed by `TurnRunner#perform`) |
| `pinned:` | `Custom::ScoutV2::Playbook` or `nil` | `decision.playbook` — the `Router::Decision`'s resolved playbook for this turn (spec Key Entity "Pinned Procedure"), blank when nothing is pinned |

**Output**: a `Custom::ScoutV2::Playbook::Catalog` — the *same object* as `catalog` when `pinned`
is blank (Decision 2: "sem ativa, aceita qualquer playbook"), a new, narrower `Catalog` containing
only `when_state.blank?` entries when `pinned` is present (Decision 2: "com ativa, só
interrupções"). This is **the single definition** FR-002/FR-003/Key-Entities "Openable Set"
require — both `Playbook::IndexBuilder.call(openable)` and `Tools::OpenPlaybook`'s own membership
check (`@openable[name]`) consume this exact same value within one turn, never recomputed.

**Validation rule this represents**: FR-002 ("entire loaded catalog when no procedure pinned;
only situational playbooks when pinned") — enforced structurally by this one method, not by a
separate check at each of the two consumption sites.

## 4. NEW in-memory value objects (no persistence, scoped to one `TurnRunner#perform` call)

| Type | Owner | Shape | Purpose |
|---|---|---|---|
| Openable set (`Catalog`) | `TurnRunner#setup_chat` (computed once via `OpenableSet.call`) | Same shape as the existing `Catalog` | FR-002/FR-003 — the one set threaded into both the index and `open_playbook`'s validation |
| Baseline instructions (`String`) | `TurnRunner#setup_chat`, passed into `Tools::OpenPlaybook.new(turn_setup:)` as `TurnSetup#baseline_instructions` | `build_instructions(nil, nil, openable)` — Instructions block + Playbook Index block, no Block 3 | The exact text `takeover!` hands `chat.with_instructions(...)` — what "the interrupted procedure's guidance... no longer present" (FR-006) concretely is |
| Baseline tools (`Array`) | `TurnRunner#setup_chat` (`always_on_tools`, built once, already wrapped), passed into `Tools::OpenPlaybook.new(turn_setup:)` as `TurnSetup#baseline_tools` | Today `[search_knowledge_base]`; excludes `open_playbook` itself | The single definition of the always-on tool list: registered at turn start and re-registered by every takeover alongside `self` (FR-007, FR-009). Brief 05 extends it in one place |
| `Tools::OpenPlaybook::TurnSetup` (`Data.define(:baseline_instructions, :baseline_tools, :tool_wrapper)`) | Defined in `open_playbook.rb`; built once by `TurnRunner#build_tools` | The two baseline values above plus the existing `tool_wrapper` lambda (`->(tool) { wrap_tool(tool, simulated: false) }`) | Keeps `OpenPlaybook#initialize` at five parameters, the RuboCop `Metrics/ParameterLists` limit (`contracts/open_playbook_tool.md` "Construction"). Groups only the values computed once at turn start |
| Tool result (`Hash`) | `Tools::OpenPlaybook#execute` | `{ body: String }` on success, `{ error: String }` on a name outside the openable set (whether absent from the catalog entirely, or present but excluded) | Unchanged shape from Brief 04 — same single-error-branch contract, now covering one more rejection reason (FR-005) without a new field |

## 5. Changed in-memory value object: `Tools::OpenPlaybook`'s own constructor

| Brief 04 (before) | This feature (after) |
|---|---|
| `.new(scout, conversation, chat:, catalog:, tool_wrapper:)` | `.new(scout, conversation, chat:, openable:, turn_setup:)` — five parameters, within RuboCop's `Metrics/ParameterLists` limit |
| `catalog:` — the full catalog, used both for lookup and (implicitly, by `TurnRunner`'s separate gate) availability | `openable:` — the narrower, turn-scoped set from §3, used for the *same* lookup, now also the source of truth for "what's available" (no separate gate elsewhere) |
| `tool_wrapper:` | Moves into `turn_setup:` (`TurnSetup#tool_wrapper`), same lambda, same use (wrap every tool an opening registers) |
| (nothing) | `TurnSetup#baseline_instructions`, `TurnSetup#baseline_tools` — new, see §4 |

Cutover, not addition (research.md §6): the one production caller (`TurnRunner#build_tools`) and
the spec subject in `open_playbook_spec.rb` move to the new signature together, in one refactor
commit that changes no behavior (tasks.md T005); no dual-signature compatibility path.

## 6. Validation summary (delta only — everything else in the v2 engine is untouched)

| Rule | Enforced by | FR |
|---|---|---|
| Openable set = full catalog when nothing pinned, situational-only when pinned | `OpenableSet.call` — one definition, two consumers | FR-002, Key Entities "Openable Set" |
| Playbook index lists exactly the openable set, never the full catalog when something is pinned; an empty set renders `EMPTY_INDEX_LINE` ("Nenhum playbook disponível para abrir neste turno."), never a "no procedure enabled" claim | `IndexBuilder.call(openable)` call site in `TurnRunner#build_instructions`; `IndexBuilder::EMPTY_INDEX_LINE` (renamed/reworded from `EMPTY_CATALOG_LINE`, research.md §1) | FR-003 |
| `open_playbook` offered iff `openable.any?` (not iff nothing pinned) | `TurnRunner#build_tools` | FR-004 |
| Name outside the openable set (absent from catalog, or present but excluded by the pin) → tool-level error, turn continues, no state write | `Tools::OpenPlaybook#execute`'s single `@openable[name].blank?` branch | FR-005 |
| Opening a situational playbook never writes `ScoutConversationState` | `Tools::OpenPlaybook#takeover!` has no reference to the model | FR-011 |
| Opening a situational playbook replaces instructions + tools wholesale (baseline + its own declarations only) | `takeover!`'s `with_instructions`/`with_tools(replace: true)` pair | FR-006, FR-007, FR-010 |
| Opening a `when_state`-bearing playbook (only reachable with nothing pinned) still persists `activation_reason: trigger`, additive tools | `Tools::OpenPlaybook#activate_procedure!` — unchanged from Brief 04 | FR-013 |
| Next turn starts from the stored state it had before the interruption | No code change needed — `takeover!` never writes `ScoutConversationState`, the only cross-turn pin storage `Router`/`RoutingSnapshot::Builder` read. Conversation data deliberately changed by the interruption's own tools (e.g. `manage_opportunity`) feeds routing normally | FR-012 |
| Interruption shows in the turn's reviewable record | Inherited `BaseTool#call` → `instrument_tool_call` nested span, plus `CallRecorder`'s `result[:tool_calls]` entry (`tool_name: 'open_playbook'`, `arguments: { name: }`) returned by the playground endpoint — no new code (research.md §7) | FR-014 |
| Same-step calls after a takeover resolve against the post-takeover tool set; a removed tool gets RubyLLM's error result, turn continues | RubyLLM 1.15 `handle_tool_calls` (sequential, per-call `tools[name]` lookup) — no new code (research.md §9, §10) | FR-016 |
| Mixed Path A/B in one turn: Path B's pin always persists; a later Path A replaces tools but never un-pins; a later Path B adds tools on top | Composition of `takeover!`/`activate_procedure!`; openable set and baseline fixed at turn start — no new code (research.md §10) | FR-017 |
