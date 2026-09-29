# Contract: Exit tools offered to the model

Producer: `Custom::ScoutV2::Exits::ExitTool` (one instance per available exit), effects in
`Custom::ScoutV2::Exits::{Terminal,Transition,Escalation,StageMove,PayloadValidator}`.
Consumer: the LLM (function declarations + tool results) and the reviewable record of actions
(`result[:tool_calls]`, playground JSON).

## Availability (FR-003, FR-007)

| Turn state | Exits offered |
|---|---|
| any step of any v2 turn | `exit_handoff` (baseline) |
| procedure P pinned at turn start | + P's declared exits, from the first step |
| procedure P opened mid-turn (`open_playbook`, nothing pinned) | + P's declared exits, from the next step (additive; only the first procedure opened in the turn — FR-007) |
| transition to T succeeded | baseline + T's tools + T's exits, from the next step (source's removed) |
| situational playbook opened (takeover) | baseline + its tools (situational playbooks have no exits) |

One procedure per turn (FR-007): once a procedure is pinned, opened, or a transition target, a
further `open_playbook` for any procedure (including the same one) returns
`{ error: PROCEDURE_IN_EFFECT_ERROR }` (text in [turn_assembly.md](./turn_assembly.md)) and changes
nothing, so two playbooks' `exit_<name>` tools are never offered together.

## Declaration sent to the provider

- `name`: `exit_<declaration.name>` (built-in: `exit_handoff`).
- `description` (Portuguese, by kind):
  - terminal: `Registra que o procedimento atual terminou com o desfecho '<name>'.`
  - transition: `Encerra o procedimento atual e passa para o procedimento '<target>'.`
  - escalation: `Transfere a conversa para atendimento humano (desfecho '<name>').`
  - `exit_handoff`: `Transfere a conversa para atendimento humano. Informe o motivo da transferência.`
  - with `stage`: append ` Move a oportunidade para o estágio <qualificado|desqualificado>.`
- `parameters`: `{ type: object, properties: { <field>: { type, [format: date-time] } }, required: [every field] }`;
  omitted entirely when the exit has no fields. Type map: string→string, integer→integer,
  number→number, boolean→boolean, datetime→string + `format: date-time`.

## Processing order for one call

1. Turn already ended (terminal/escalation succeeded earlier) → `{ error: TURN_ENDED_ERROR }`.
   Applies to every tool, not only exits (FR-015).
2. Payload check → `{ error: "Dados inválidos para exit_<name>: <p1>; <p2>. Corrija e chame o exit novamente." }`
   listing every problem: `campo '<f>' ausente`, `campo '<f>' não declarado`, `campo '<f>' deve ser <type>`
   (FR-004, FR-008). `string`/`datetime` values must be non-blank; `datetime` must parse with
   `Time.iso8601`; `number` accepts Integer or Float; `nil` never valid.
3. Kind-specific effect (below). Any `{ error: }` ⇒ nothing persisted, turn continues.

Several calls in one model response run in order (RubyLLM); a call to a tool no longer in the chat
(e.g. a source exit after a transition earlier in the same response) gets RubyLLM's
`Model tried to call unavailable tool …` error and is still appended to `tool_calls`
(FR-016, FR-024).

## Effects and results

### Terminal

- Stage (if declared) → `StageMove`; error ⇒ `{ error: <stage error> }`, nothing written.
- One transaction: stage write + `ScoutConversationState#record_terminal_exit!(name)`.
- Turn becomes ended.
- Result (String): `TERMINAL_RESULT` = `Desfecho '<name>' registrado. Escreva agora sua resposta final ao cliente.`

### Transition

- 2 transitions already succeeded this turn ⇒ `record_transition!` sets `handoff_limit_reached_at`;
  `{ error: TRANSITION_LIMIT_ERROR }` = `A transição para '<target>' não aconteceu: limite de transições deste turno atingido. Responda ao cliente agora.`
- Stage (if declared) → `StageMove`; error ⇒ `{ error: }`, nothing written.
- One transaction: stage write + `record_transition!(target, turn_transition_count:)`.
- Chat: instructions → baseline; tools → baseline + target's tools + target's exits.
- Result (String): the target playbook's full body.

### Escalation (built-in `exit_handoff` and declared)

Inbox, all-or-nothing (FR-022), in `conversation.with_lock`:

1. `status != pending` ⇒ `{ error: ESCALATION_REFUSED_ERROR }` =
   `A transferência não aconteceu e o estágio não foi alterado: a conversa não está mais aos cuidados do assistente.`
2. Stage (if declared) → `StageMove`; error ⇒ rollback, `{ error: <stage error> }`.
3. `HandoffService#transfer!(reason: note_reason)` — team `scout.handover_team_id`, `bot_handoff!`,
   one private transfer note. No public message.
4. `record_terminal_exit!(name)` (`handoff` for the built-in).

Then the turn is ended and marked escalated. Result (String):
`Transferência para atendimento humano realizada. ` + `CLOSING_INSTRUCTION`, where
`CLOSING_INSTRUCTION` = `Escreva agora sua resposta final ao cliente: uma mensagem natural de encerramento, sem perguntas, informando que um atendente humano dará continuidade ao atendimento.`
— present exactly once here and nowhere else on the v2 path (FR-013).

`note_reason`: built-in → the supplied `reason`; declared → `<name> (<f1>: <v1>; <f2>: <v2>)` in
declaration order, or `<name>` with no fields. Note text (existing `HandoffService` format):
`📋 Transferência para atendimento humano: <note_reason>` + ` | Oportunidade #<id> - <title>` when linked.

Playground (FR-023): steps 1 and 3 are skipped (the sandbox is never queued); step 2 and 4 run in
one transaction; result text identical.

### StageMove (any kind with `stage`)

| Check | Error (`{ error: }`) |
|---|---|
| no `conversation.active_opportunity` | `A oportunidade não pode mudar de estágio: a conversa não tem oportunidade.` |
| role's scout stage id is nil | `A oportunidade não pode mudar de estágio: o estágio '<role>' não está configurado para este assistente.` |
| `OpportunityStageTransitionService#call` not `moved?` | the service's own text (names missing fields) |

On success the service's text is discarded and `handoff_needed` ignored (a stage move never
transfers, FR-014).

## Record of actions (FR-024)

Every attempt appears in `tool_calls` as `{ tool_name: 'exit_<name>', arguments: <payload>, result: <String or { error: }>, simulated: false }`.
