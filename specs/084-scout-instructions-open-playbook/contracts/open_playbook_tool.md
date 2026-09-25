# Contract: `open_playbook` tool

The one new interface this feature exposes to the model (RubyLLM tool-calling contract). Every
other change is internal prompt composition, not a callable surface.

## Availability

Registered on the live `chat` **if and only if** no playbook is currently forced by conversation
state for this conversation (`decision.playbook.blank?` at the start of the turn). When a
playbook is already active, this tool is absent from `chat.tools` entirely — the model cannot see
or call it, and cannot get a "not currently allowed" error for it (FR-011, FR-012).

## Request

```json
{
  "name": "open_playbook",
  "arguments": { "name": "duvida_comercial" }
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | Exact playbook `name` as it appears in the `[Playbook Index]` block (the machine token, not the `title`) |

## Response — success

```json
{ "body": "## Passos\n1. ..." }
```

`execute` returns a Ruby `Hash` (`{ body: ... }` / `{ error: ... }`), like every v1 tool; RubyLLM
serializes it into the tool message with `to_s`. It stays a `Hash` because
`Integrations::LlmInstrumentation#instrument_tool_call` flags the tool span as an error only for a
`Hash` result carrying `error`, and the playground renders a `Hash` result as structured JSON.

- `body` is the opened playbook's full markdown body (frontmatter stripped), verbatim — no
  summarization, no truncation (FR-013).
- Side effects, both committed before the tool call returns:
  1. Every tool name in the opened playbook's `tools:` frontmatter list is resolved via
     `Custom::ScoutV2::Tools::Registry` and added to the live `chat` (`chat.with_tool(...)`) —
     available starting the very next tool-loop iteration of the same `chat.ask` (FR-014). Every
     such name is guaranteed registered: the boot `Playbook::Validator` rejects any `tools:` entry
     missing from the Registry.
  2. `ScoutConversationState#record_trigger_activation!(name)` persists `active_playbook: name`,
     `activation_reason: 'trigger'` for the conversation (FR-015).

## Response — error

```json
{ "error": "Playbook desconhecida: agendamentoo. Disponíveis: qualificacao, duvida_comercial" }
```

- Returned (not raised) when `name` doesn't match any entry in the currently loaded catalog.
- No side effects: no tools injected, `ScoutConversationState` untouched.
- The top-level turn continues normally — the model receives this as an ordinary tool result and
  may retry with a corrected name or respond directly (FR-016).

## Non-goals of this contract (explicitly out of scope, see `research.md` §2 and §8)

- No `requires`/capability resolution — `requires` is not validated, resolved, or blocked on here.
- No `exits` become independently callable tools from this action — that mechanism doesn't exist
  yet (Brief 05).
- Re-opening the same or a different playbook later in the same turn is not guarded against
  (Edge Case 4) — a second call simply re-runs the same side effects.
