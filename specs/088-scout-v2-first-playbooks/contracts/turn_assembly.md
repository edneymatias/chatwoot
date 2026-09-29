# Contract: v2 turn assembly — changes from 087

Base contract: [087 turn_assembly.md](../../087-scout-v2-exits-escalation/contracts/turn_assembly.md)
and [087 exit_tools.md](../../087-scout-v2-exits-escalation/contracts/exit_tools.md). Only the deltas
are listed. v1 (`AgentRunner`, `SystemPromptsService`, v1 tools) is untouched (FR-024).

## 1. Routing snapshot

`RoutingSnapshot::Builder` adds `completed_playbooks` (from the state row it already loads) and
`satisfied_business_facts: []`; `pending_fields` with no active opportunity = the scout's
qualification requirement keys ([data-model.md](../data-model.md#customscoutv2routingsnapshot-in-memory-value--extended)).

## 2. System instructions

Unchanged order: `Identity · Communication · Memory · Safety · [Playbook Index] · [Escalation]`,
then — only when a procedure is pinned — `TurnScope#content_for(pinned)` instead of
`body + PendingFieldsFormatter`. Content = rendered body (markers resolved), pending-steps notice if
any step is pending, then the context blocks the playbook's `when_state` reads (pending fields;
missing contact data). The Index lists every openable playbook's `trigger` (six entries when nothing
is pinned; the three situational ones when a procedure is pinned — existing `OpenableSet` rule).

## 3. Offered actions per step (FR-017, FR-021)

| Playbook in effect | Offered (besides `search_knowledge_base`, `exit_handoff`, `open_playbook`*) |
|---|---|
| none | nothing |
| `identificacao` | `update_contact`, `exit_identificado` |
| `qualificacao` | `manage_opportunity`, `exit_qualificado`, `exit_desqualificado` |
| `agendamento`, a `requires` unsatisfied | nothing (declared exits withheld) |
| `agendamento`, all `requires` satisfied (FR-019 design property; component level only until Brief 07) | `exit_agendado`, `exit_sem_horario` |
| situational takeover (`fora_de_prospeccao`, `duvida_comercial`, `pausa`) | nothing |

\* `open_playbook` is present whenever the openable set is non-empty — always, with the shipped
catalog (three situational playbooks).

Withholding is decided per playbook in `TurnScope#actions_for`, so it applies identically when the
playbook is pinned at turn start, opened mid-turn, or reached as a transition target.

## 4. Tool/exit results that carry playbook guidance

| Result | Before | Now |
|---|---|---|
| `open_playbook` → procedure | `{ body: playbook.body }` | `{ body: TurnScope#content_for(playbook) }` |
| `open_playbook` → situational takeover | `{ body: playbook.body }` | `{ body: TurnScope#content_for(playbook) }` (rendered body; no context blocks — situational playbooks read no state) |
| successful transition exit | `target.body` (String) | `TurnScope#content_for(target)` (String) |

`content_for` renders with the snapshot `setup_initial_tools!(…, ctx:)` stored; that call is the only
way a `TurnScope` receives it (production: `TurnRunner`; specs that build a `TurnScope` directly —
`exits/exit_tool_spec.rb`, `tools/open_playbook_spec.rb` — go through it too). Calling `content_for`
before it is a wiring bug and fails loudly (no default snapshot).

## 5. Exit effects on routing state (FR-026)

Every exit calls the state operation with `completed: scope.active_procedure_name`:

- `Exits::Terminal` → `record_terminal_exit!(name, completed:)`
- `Exits::Transition` success → `record_transition!(target, turn_transition_count:, completed:)`,
  **then** `scope.active_procedure_name = target` (unchanged order). Limit refusal: unchanged call
  without `completed:`.
- `Exits::Escalation` inbox (inside `conversation.with_lock`) and playground →
  `record_terminal_exit!(name, completed:)`.

Tool-result texts and error strings are unchanged.

## 6. Turn completion (FR-018)

Two steps, split around `instrument_agent_session` so that a failing write can never re-run the turn:
`instrument_agent_session` rescues `StandardError` and re-yields its block while `executed` is still
false (`lib/integrations/llm_instrumentation.rb:45-47`), which would repeat `chat.ask` and every exit
of the turn (duplicate transitions, stage moves, transfers). No write happens inside the block.

1. **Inside** the `instrument_agent_session` block, right after `instrument_llm_call` returns the
   response: `@turn_record = UnsatisfiedItems.trace!(playbook: catalog[scope.active_procedure_name], conversation:, scout:, ctx:)`,
   which builds `record = UnsatisfiedItems.call(playbook:, conversation:, scout:, ctx:)` (reads only),
   sets `OpenTelemetry::Trace.current_span.set_attribute('langfuse.trace.metadata.unsatisfied_flags', record.to_json)`
   on the agent-session span (no-op when OTel is disabled) and returns `record`; the block still
   returns the response.
2. **After** the block returns and before `build_final_reply` (so unreadable/empty outputs and
   escalations are covered): `ScoutConversationState.for_conversation(conversation).record_unsatisfied_items!(@turn_record)`
   (fresh row read; creates the row when absent). A failure here raises out of the turn — loud —
   instead of silently re-running it.

`TurnRunner` gains three lines (plan Constraints, `Metrics/ClassLength`).

The start-of-turn metadata keeps `scout_id`, `playbook`, `activation_reason` and drops
`unsatisfied_flags`. A turn that stops before the model call (quota / API key) writes nothing. An
exception raised by `chat.ask` propagates as today and writes nothing.
