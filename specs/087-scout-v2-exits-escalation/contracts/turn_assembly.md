# Contract: v2 turn assembly, tool catalog and final reply

Producer: `Custom::ScoutV2::TurnRunner` + `Custom::ScoutV2::TurnScope`. Consumers: the LLM provider
request (system text, function declarations), `ProcessMessageJob#dispatch_scout_v2` (inbox) and
`PlaygroundMessagesController` (playground). Supersedes the tool-list and block-order parts of
`specs/085-scout-trigger-interruption/contracts/turn_prompt_assembly.md`.

## System instructions — block order (FR-001, FR-002)

1. `[Identity]` · 2. `[Communication]` · 3. `[Memory]` · 4. `[Safety]` — unchanged (Brief 04 / 086)
5. `[Playbook Index]` — unchanged (Brief 11)
6. `[Escalation]` — **new**, always present
7. pinned procedure body (+ pending fields) — only when pinned

`baseline_instructions` (used after a takeover or a transition) = blocks 1–6.
Bracketed headers in a v2 system text are therefore exactly
`Identity, Communication, Memory, Safety, Playbook Index, Escalation`.

### `Custom::ScoutV2::Instructions::Escalation::SECTION`

```text
[Escalation]
Quando transferir para um atendente humano:
- o cliente pede para falar com uma pessoa ou atendente;
- você não sabe a resposta, ou o contexto e as ferramentas disponíveis não bastam para resolver o pedido;
- o contato não busca uma nova oportunidade comercial: já é cliente com um produto ou serviço em andamento, quer alterar ou cancelar algo que já existe, ou tem uma reclamação;
- a conversa entrou em repetição ou o cliente demonstra frustração repetida.
Antes de transferir:
1. Registre com as ferramentas disponíveis neste turno os dados informados pelo cliente que ainda não foram registrados.
2. Use o exit de escalação da playbook ativa quando ela declarar um para o caso; nos demais casos, use `exit_handoff` informando o motivo.
```

It never contains the closing-message rule (no "encerramento", no "sem perguntas"); that rule
exists only in `Exits::Escalation::CLOSING_INSTRUCTION` ([exit_tools.md](./exit_tools.md)).

## Tool catalog per step (FR-003, FR-007, FR-018)

| Turn state | Offered `functionDeclarations[].name` |
|---|---|
| nothing pinned, openable set non-empty | `search_knowledge_base`, `exit_handoff`, `open_playbook` |
| nothing pinned, empty catalog | `search_knowledge_base`, `exit_handoff` |
| procedure P pinned | baseline (+ `open_playbook` iff a situational playbook exists) + P's `tools` + `exit_<P exits>` |
| after opening procedure P mid-turn (first procedure this turn) | previous set + P's `tools` + `exit_<P exits>` |
| `open_playbook` for a procedure after one was pinned, opened, or transitioned to this turn | unchanged; the call returns `{ error: PROCEDURE_IN_EFFECT_ERROR }` |
| after a situational takeover | baseline + the situational playbook's `tools` |
| after transition to T | baseline + T's `tools` + `exit_<T exits>` |

`Custom::ScoutV2::Tools::OpenPlaybook::PROCEDURE_IN_EFFECT_ERROR` =
`Já existe um procedimento em andamento neste turno: <nome>. Siga esse procedimento; a troca de procedimento só acontece por um exit de transição.`
(With a procedure pinned, procedures are not in the openable set, so the existing
`Playbook desconhecida: …` error applies first — same outcome: refused, nothing changes.)

Never offered on v2, at any step: `move_opportunity_stage`, `handover_to_human`, `call_custom_api`
(not in `Tools::Registry`; a playbook declaring one fails boot).

Registry (`Custom::ScoutV2::Tools::Registry::TOOL_CLASSES`):

| Name | Class |
|---|---|
| `manage_opportunity` | `Custom::ScoutV2::Tools::ManageOpportunity` (subclass of v1's) |
| `update_contact` | `Custom::Scout::Tools::UpdateContact` |

### v2 `manage_opportunity`

Same name, description and parameters as v1 **minus `stage_id`**. A call carrying `stage_id`
returns `{ error: 'stage_id não é aceito: a mudança de estágio acontece apenas pelos exits da playbook.' }`
and changes nothing. Updating an opportunity already in the qualified stage keeps v1's private
requalification note but returns `Opportunity updated successfully (ID: <id>).<reminder>` — no
closing instruction, no handoff flag.

## Turn-ended guard (FR-015)

After a terminal or escalation exit succeeds, every registered tool (baseline, playbook tools,
exits) returns `{ error: TURN_ENDED_ERROR }` without running, and the attempt is recorded:
`TURN_ENDED_ERROR` = `O turno já foi encerrado por um exit. Nenhuma outra ação é executada; escreva apenas a resposta final ao cliente.`

## Final reply (FR-012, FR-020, FR-021)

The final output is plain text (no schema, no `reasoning`). "Unreadable" = `response&.content` not a
`String` or blank after `strip`.

| Final output | Escalation succeeded | Inbox return → effect | Playground return |
|---|---|---|---|
| readable | any | `{ reply: <text>, tool_calls: }` → job posts one outgoing message | `{ reply: <text>, tool_calls: }` |
| unreadable | yes | `{ reply: I18n.t('conversations.scout.handoff', locale:), tool_calls: }` → job posts it; no fail-safe | same |
| unreadable | no | fail-safe `HandoffService#perform(message: nil, reason: UNREADABLE_REPLY_REASON)` (standard message, transfer, note) → `{ reply: '', tool_calls: }`, job posts nothing | `{ reply: "Erro ao executar simulação: #{UNREADABLE_REPLY_REASON}", tool_calls:, error: UNREADABLE_REPLY_REASON }` |

`UNREADABLE_REPLY_REASON` = `Resposta final do modelo vazia ou ilegível.`
Locale: `conversation.language.presence || account.locale.presence || I18n.default_locale`.
Quota / missing API key: unchanged (`handle_infra_failure`, same fail-safe, no model call).
No path invokes `ResponseAuditor`, `ActionClassifierService` or `ClaimConsistencyService`.
