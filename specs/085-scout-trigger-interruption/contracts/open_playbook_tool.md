# Contract: `open_playbook` tool (supersedes `084-scout-instructions-open-playbook/contracts/open_playbook_tool.md`)

This is the only interface this feature exposes to the model (the RubyLLM tool-calling contract), and its shape changes.
Every other change is internal prompt/tool-catalog composition, not a callable surface.

## Construction (internal, one production caller: `TurnRunner#build_tools`)

```ruby
Custom::ScoutV2::Tools::OpenPlaybook.new(
  scout, conversation,
  chat:,         # the live RubyLLM::Chat for this turn
  openable:,     # Playbook::Catalog — this turn's openable set (data-model.md §3)
  turn_setup:    # Custom::ScoutV2::Tools::OpenPlaybook::TurnSetup (below)
)

# Defined inside open_playbook.rb, next to the tool that consumes it:
Custom::ScoutV2::Tools::OpenPlaybook::TurnSetup = Data.define(
  :baseline_instructions,  # String — Instructions + Playbook Index blocks, no Block 3
  :baseline_tools,         # Array — the already-wrapped always-on tools TurnRunner registered (today: [search_knowledge_base]); excludes open_playbook itself
  :tool_wrapper            # ->(tool) { wrap_tool(tool, simulated: false) } — applied to every tool an opening registers (Path A and Path B)
)
```

Five parameters in total. RuboCop's `Metrics/ParameterLists` (default `Max: 5`, keywords counted; neither
`.rubocop.yml` nor `.rubocop_todo.yml` overrides it) rejects the flat seven-parameter form. AGENTS.md forbids new
`Max`/`Exclude` entries, and Brief 04 already had to remove an inline `rubocop:disable Metrics/ParameterLists` from
this constructor (`084-scout-instructions-open-playbook/tasks.md` T042). `TurnSetup` groups the three values
`TurnRunner` computes once at turn start for the tool, none of which changes within the turn. `chat` and `openable`
stay separate keywords: `execute` uses them directly for registration and lookup.

## Availability

Registered on the live `chat` **if and only if** this turn's openable set is non-empty
(`openable.any?`, FR-004). Compared with Brief 04's gate (`decision.playbook.blank?`), the change
goes both ways:

- **Broader:** the tool is now also offered while a procedure is pinned, as long as the catalog has
  at least one situational playbook.
- **Narrower:** with nothing pinned and an entirely empty catalog, Brief 04 still offered the tool;
  it is now withheld. This supersedes Brief 04, as stated in the spec's Assumptions.

## Request

```json
{
  "name": "open_playbook",
  "arguments": { "name": "duvida_comercial" }
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Exact playbook `name` as it appears in the `[Playbook Index]` block, unchanged from Brief 04. The index block now lists only this turn's openable set (`contracts/turn_prompt_assembly.md`), so a name outside the set is, by construction, a name the model was never shown. |

## Response — success

```json
{ "body": "## Passos\n1. ..." }
```

Same shape as Brief 04: a `{ body: ... }` Hash, `to_s`-serialized by RubyLLM, returned as
structured JSON in the playground. What differs is the **side effects**, which split into two
mutually exclusive paths selected by `playbook.when_state.blank?`:

### Path A — situational playbook (`when_state.blank?`) → takeover

Reachable whether or not a procedure was pinned at the start of the turn; FR-006 and FR-010 apply
either way. With nothing pinned at turn start, the system message already equals the baseline, so
only the tool catalog changes (it drops any tools Path B added earlier in the turn, FR-017).

1. `chat.with_instructions(turn_setup.baseline_instructions)` **replaces** the system message in place
   (`RubyLLM::Chat#with_instructions` defaults to replace). The new instructions contain only the
   always-on Instructions + Playbook Index blocks — no Block 3 (the interrupted procedure's body),
   even if one was present a moment ago (FR-006).
2. `chat.with_tools(*turn_setup.baseline_tools, self, *interruption_tools, replace: true)` **clears** every
   currently registered tool, including anything the interrupted procedure's `tools:` frontmatter
   had added, and re-registers exactly these (FR-007):
   - the injected always-on tools;
   - the `open_playbook` tool itself, so a further interruption remains reachable (FR-009);
   - every tool named in the newly opened playbook's own `tools:` list, resolved via
     `Tools::Registry` and wrapped with `turn_setup.tool_wrapper`.
3. **No** `ScoutConversationState` write of any kind (FR-011): `active_playbook`, `activated_at`
   and `activation_reason` are byte-for-byte unchanged by this call, whether or not something was
   pinned before it.

Opening the same or a different situational playbook again later in the same turn re-runs this
exact sequence. The second call's `with_tools(..., replace: true)` fully replaces the first
opening's tools (FR-010, Edge Case 3); there is no de-duplication and no "already open" guard.
The takeover never touches `openable`: re-registering `self` keeps the same turn-start set, so a
later attempt to open the interrupted procedure by name still gets the error below (Edge Case 7).

### Path B — `when_state`-bearing playbook, opened with nothing pinned → unchanged from Brief 04

Only reachable when the openable set is the full catalog (nothing pinned at turn start), because a
`when_state` playbook is never in the situational-only set built when something is pinned.

1. Every tool named in the opened playbook's `tools:` frontmatter is resolved via
   `Custom::ScoutV2::Tools::Registry`, wrapped with `turn_setup.tool_wrapper`, and added
   **additively** to the live `chat` (`chat.with_tool(...)`, no clearing), as in Brief 04.
2. `ScoutConversationState#record_trigger_activation!(name)` persists `active_playbook: name` and
   `activation_reason: 'trigger'` (FR-013, unchanged behavior).

The openable set, the index and `turn_setup.baseline_instructions` stay as computed at turn start. The new
pin takes effect from the next turn (FR-002).

### Ordering within one turn (FR-016, FR-017) — no extra code, see `research.md` §10

- **Same-step calls:** RubyLLM executes a response's tool calls sequentially, looking each one up
  in the *current* `chat.tools`. Calls listed before a Path A call run normally. Calls listed after
  it resolve against the post-takeover set. A tool the takeover removed returns RubyLLM's own
  result, `{ error: "Model tried to call unavailable tool `<name>`. Available tools: [...]" }`, as
  that call's tool result, and the loop continues (verified in-container, `research.md` §9).
- **Path B, then Path A (nothing pinned at turn start):** the pin written by Path B survives. Path A
  replaces the tools with the baseline plus its own and writes nothing.
- **Path A, then Path B:** Path B adds its tools on top of the takeover set and persists `trigger`.

## Response — error

```json
{ "error": "Playbook desconhecida: agendamento. Disponíveis: fora_de_prospeccao, pausa" }
```

- **When:** `name` doesn't resolve within **this turn's openable set**. The error is returned, not
  raised, and has the same shape for both causes (FR-005):
  - the name is not in the catalog at all;
  - the name is in the catalog but excluded by this turn's pin (e.g. a `when_state` playbook
    attempted while a procedure is pinned).
- **`Disponíveis:`** lists the openable set's names, not the full catalog's, so the model is never
  told about a name it can't currently use.
- **Side effects:** none — no tools change, no instructions change, `ScoutConversationState` is
  untouched.
- **Turn:** the top-level turn continues normally (FR-005, SC-003).

## Non-goals of this contract (unchanged from Brief 04, still out of scope)

- No `requires`/capability resolution.
- No `exits` become independently callable tools (Brief 05).
- No cap on interruptions opened per turn (brief §6, "sem evidência de laço; não entra").
