# Contract: Capabilities (model-facing operations)

Covers FR-001…FR-008, FR-011, FR-013…FR-016, FR-028, FR-029. All strings model-facing → Portuguese, outside
the i18n files (as 088). Tool result envelope: success → the `data` hash below; failure →
`{ error: '<Portuguese sentence naming what to fix or what happened>' }`. No operation ever ends the
turn (`scope.end_turn!` is only called by exits).

## 1. Common behavior of every operation tool

Order of checks in `OperationTool#execute(**inputs)` — the first failing step returns and **no ERP
request has been made** for steps 1–2:

1. **Input contract** (FR-003): `Operation#problems_for(inputs)`.
   - missing required: `campo 'date' ausente`
   - wrong type: `campo 'date' deve ser uma data no formato YYYY-MM-DD`; `campo 'name' deve ser texto não vazio`
   - undeclared key: `campo 'idEmpresa' não declarado`
   - result: `{ error: "Dados inválidos para scheduling_list_slots: <problems>. Corrija e chame a ferramenta novamente." }`
     (record outcome `invalid_input`).
2. **Capability preconditions** (defined per operation below) → `{ error: … }` (outcome
   `precondition_failed`).
3. **Provider call.** `Erp::Error` → `{ error: <text chosen by class> }` (outcome `erp_error`), see §1a; no retry
   and the text forbids the model from repeating a write (FR-015). Other exceptions propagate.
4. **Soft output** (FR-004): the provider's answer is already normalized to the contract shape;
   `Operation#deviations_for(data)` lists declared required fields that are missing. Deviations go to the
   `CallRecord`; the data is returned unchanged (except the missing-identifier cases of §1a, which return a failed result); nothing raises; the tool never hands off by itself.
5. **Remember + record.** State writes per operation; `CallRecord` set on the current span as
   `langfuse.observation.metadata.capability_call` (JSON; see §5).

`TurnScope#guard_tool` still short-circuits any call after the turn ended
(`TURN_ENDED_ERROR`).

## 1a. Failure results (single source)

Every result below is `{ error: <text> }` with outcome `erp_error`; none ends the turn, none is retried,
and the playbook follows each with `exit_handoff` in the same turn (no second attempt; the only counted
attempts are `ambiguous` lookups, FR-016).

| Situation | Text (Portuguese, model-facing) | State written |
|---|---|---|
| `Erp::AuthenticationError` (401/403) | `O sistema do cliente recusou as credenciais configuradas; nada foi registrado. Não prometa nem confirme o agendamento; chame exit_handoff neste mesmo turno.` | none |
| any other `Erp::Error` (timeout, network, 5xx, malformed body, declined write) | `O sistema do cliente não respondeu ou recusou a operação. Se era um cadastro ou agendamento, o resultado é desconhecido e pode ter sido concluído: não repita. Não prometa nem confirme o agendamento; chame exit_handoff neste mesmo turno.` | none |
| `book` answered without `appointment_id` (FR-028) | `O sistema do cliente não confirmou o agendamento (resposta sem identificador); ele pode ter sido criado. Não repita a operação, não prometa nem confirme o agendamento; chame exit_handoff neste mesmo turno.` | none; deviation recorded |
| `create` answered without a person id (FR-029) | `O sistema do cliente não confirmou o cadastro (resposta sem identificador); ele pode ter sido criado. Não repita a operação; chame exit_handoff neste mesmo turno.` | none; deviation recorded |
| `find_by_phone`, single match without a readable id (FR-029) | `O sistema do cliente encontrou um cadastro, mas não foi possível identificá-lo. Não cadastre novamente; chame exit_handoff neste mesmo turno.` | none; deviation recorded |

A declined write (`sucesso: false`) is an `Erp::ApiError`, indistinguishable from a timeout by class, so
it gets the "unknown" wording: conservative, and followed by the same transfer.

## 2. `scheduling` (`Capabilities::Scheduling`)

### 2.1 `scheduling_list_slots`

| Input | Type | Required | Notes |
|---|---|---|---|
| `date` | date (`YYYY-MM-DD`) | yes | Syntax only; a past date is valid, the ERP's answer is reported as any other. |
| `service` | string | no | Informational (research §6). Recorded in `inputs`, never sent. Description: "nome do serviço desejado, apenas informativo". |

Output: `shape: list`, elements `{ slot_id, starts_at }` — both required (declared). Returned as
`{ slots: [ { slot_id:, starts_at: }, … ] }`, ordered by start ascending, **all** slots the ERP returned
(the ≤ 3 presentation limit is the playbook's, and the returned list is what "none presented that the
ERP did not return" is checked against).
State: `remember_slots!({ slot_id => starts_at })`.
Preconditions: none (no phone/customer needed to list).

### 2.2 `scheduling_book`

| Input | Type | Required | Notes |
|---|---|---|---|
| `slot_id` | string | yes | Must be a key of `capability_state['offered_slots']` (FR-014). |
| `notes` | string | no | Free text appended to `observacoes`. |

Preconditions, in order:

1. A booking already remembered (`capability_state['booking']` present), else `{ error: 'Já existe um agendamento confirmado nesta conversa. Não agende novamente; encerre com exit_agendado.' }` (FR-028).
2. `capability_state['customer']` present, else `{ error: 'Nenhum cliente foi localizado ou cadastrado nesta conversa. Use customer_registry_find_by_phone (ou customer_registry_create) antes de agendar.' }` (FR-013).
3. `slot_id ∈ offered_slots`, else `{ error: "O horário '<slot_id>' não foi oferecido nesta conversa. Liste os horários com scheduling_list_slots e escolha um dos retornados." }` (FR-014).

Output: `shape: record`, required `appointment_id`. Returned as `{ appointment_id:, starts_at: }`.
State: `remember_booking!` **only** when `appointment_id` is present; an answer without it is the failure
of §1a (deviation recorded, booking not remembered, `exit_agendado` stays rejected, the assistant
transfers).
The model never supplies the person id, title, start instant or any identifier: the provider gets
`person_id` and `person_name` from state and `starts_at` from `offered_slots[slot_id]`.

## 3. `customer_registry` (`Capabilities::CustomerRegistry`)

Common precondition (FR-011): the conversation contact has a non-blank `phone_number`, else
`{ error: 'O contato não tem telefone registrado. Não peça o telefone ao cliente; chame exit_handoff neste mesmo turno informando que o telefone está ausente.' }`
— returned before any request (outcome `precondition_failed`).

### 3.1 `customer_registry_find_by_phone`

No inputs (`params_schema` `nil`). Provider gets the contact's normalized phone.

| Provider result | Returned | State |
|---|---|---|
| exactly one person | `{ status: 'found', name: <string or nil> }` | `remember_customer!(id, name)` |
| more than one (`multiple_matches`) | `{ status: 'ambiguous' }` | none (no person selected, FR-016) |
| none | `{ status: 'not_found' }` | none |

Output: `shape: record`, required `status`. A single match whose person id cannot be read is the failure
of §1a (FR-029), not `not_found`: registering again would duplicate the person. The missing id is
recorded as a deviation.

### 3.2 `customer_registry_create`

| Input | Type | Required | Notes |
|---|---|---|---|
| `name` | string | yes | The name the lead gave/confirmed. |

Provider gets `name`, the contact's normalized phone. Returned `{ status: 'created', name: }`; output
required `status`. State: `remember_customer!(id, name)`. A success answer without an id is the failure
of §1a (FR-029): it is not returned as `created`, no customer is remembered, and the deviation is
recorded.

## 4. Scoping and registration (FR-018)

`TurnScope#actions_for(playbook, …)`:

```text
requires_satisfied = playbook.requires.all? { |c| ctx.satisfied_capabilities.include?(c) }
tools = declared tools
return tools unless requires_satisfied
tools + capability OperationTools(playbook.requires) + declared exits
```

- Registered only for the playbook being made active (pinned, opened procedure, transition target).
- Never in the baseline; never for a situational takeover (`replace_with_baseline!` receives only the
  takeover playbook's declared tools).
- Tool names never collide with declared tools or exits (`exit_*`, `open_playbook`,
  `search_knowledge_base`, `update_contact`, `manage_opportunity`).

## 5. Capability call record (FR-017)

Span attribute `langfuse.observation.metadata.capability_call` on the tool span, one JSON object per
call:

```json
{
  "capability": "scheduling", "operation": "book",
  "inputs":   { "slot_id": "2026-10-15T14:30:00-03:00", "notes": "prefere manhã" },
  "injected": { "id_empresa": 1041, "id_agenda": 1, "id_servico": 1, "id_usuario": 201313, "id_convenio": 1, "person_id": "123" },
  "outcome": "ok", "error": null, "deviations": []
}
```

- `inputs`: exactly what the model supplied.
- `injected`: allow-list — the seven identifiers actually placed in the request that operation makes,
  plus `phone` (normalized) for customer-registry calls, plus `person_id` for `book`. **Never `token`.**
  Empty (`{}`) when the call stopped before the provider.
- Recorded for every outcome, including `invalid_input`/`precondition_failed` (then `injected` is `{}`).

## 6. Catalog and boot validation (FR-027)

`Capabilities::Catalog::KNOWN_NAMES` stays `%w[scheduling customer_registry]` and remains what
`Playbook::DependencyRules#validate_requires` checks. A spec asserts that
`Capabilities::Base` subclasses' `capability_name`s equal `KNOWN_NAMES`, so the registry cannot know a
capability the catalog rejects (or vice versa).
