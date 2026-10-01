# Contract: Turn assembly, exits and the `agendamento` playbook

Covers FR-006, FR-018–FR-025. Everything not listed here is unchanged from
`specs/088-scout-v2-first-playbooks/contracts/turn_assembly.md`.

## 1. Routing snapshot

`RoutingSnapshot::Builder#call` sets

```ruby
satisfied_capabilities: Custom::ScoutV2::Capabilities::Registry.satisfied_names(account: @conversation.account)
```

(was `[]`). `satisfied_business_facts` stays `[]`. One query (`account.hooks.enabled` + in-memory
app lookup) per turn. Consequences with **no other code change** (Brief 06 machinery):

| Consumer | Both capabilities satisfied | Any unsatisfied |
|---|---|---|
| `ContentBuilder` markers | `[[depends: scheduling]]` / `[[depends: customer_registry]]` render empty; no `PENDENTE`, no `PENDING_STEPS_NOTICE` (agendamento has no `politica_reagendamento` marker any more) | markers render `(PENDENTE — indisponível: …)`, notice appended |
| `TurnScope#actions_for` | declared tools + capability tools + declared exits | declared tools only, no capability tools, no declared exits |
| `UnsatisfiedItems` | `unmet_requires: []`, `unmet_needs: []` for `agendamento` (FR-024, SC-011) | `unmet_requires` = only the unsatisfied of `scheduling`/`customer_registry`; `unmet_needs: []` |

## 2. Registration order in `actions_for`

```text
declared tools (Tools::Registry.build)
  + [when requires_satisfied]
      capability OperationTools, in `requires` order, operations in declaration order
      declared exits (playbook.exits order)
```

`replace_with_baseline!`, `OpenPlaybook#takeover!`, `Exits::Transition` are untouched: they either
call `actions_for` (transition target, procedure opened by trigger — capability tools follow
automatically) or register a takeover's declared tools only (no capability tools).

## 2a. Phone-missing context block (FR-020)

`ContentBuilder#call` appends, after the pending-fields block, `PHONE_MISSING_NOTICE` iff
`playbook.requires.include?('customer_registry')` **and** the conversation contact's `phone_number`
is blank (contact reloaded when persisted, as the contact-gaps block does):

> O contato não tem telefone registrado. Não chame ferramentas customer_registry_*, não peça o telefone ao cliente e chame exit_handoff neste mesmo turno informando que o telefone está ausente.

Independent of capability satisfaction (rendered whether or not the capabilities are satisfied; on
the degraded path the playbook already says to `exit_handoff`). Not rendered when a phone exists.

## 3. Exit precondition

Playbook file grammar (exit entry): `kind`, `fields`, `target`, `stage`, **`precondition`** (new,
optional, string).

| Rule | Owner | Failure |
|---|---|---|
| unknown key still rejected | `Loader` (`ALLOWED_EXIT_KEYS` gains `precondition`) | `Invalid exit 'x': unknown key 'y'` (unchanged) |
| name must be in `Exits::Preconditions::REGISTRY` | `Playbook::DependencyRules` | `<file>: Unknown exit precondition for 'agendado': <name>` |
| allowed only on `kind: terminal` | `Playbook::DependencyRules` | `<file>: Exit 'x' declares a precondition but is not terminal` |

Runtime (`ExitTool#execute`), before payload validation and dispatch:

```text
if declaration.precondition:
  error = Exits::Preconditions.check(declaration.precondition, exit_tool)
  return { error: error } if error         # no state write, turn not ended, not completed
```

`'booking'` → `capability_state['booking']` present for `conversation`'s state row; else error:
`Você ainda não realizou nenhum agendamento nesta conversa. Chame scheduling_book antes de exit_agendado, ou transfira com exit_handoff.`

Success path (`Terminal`): unchanged transaction (`record_terminal_exit!('agendado',
completed: 'agendamento')`, stage move if declared — none for `agendamento`); the returned message
becomes `"Desfecho 'agendado' registrado. Início: <booking.starts_at>. Referência: <booking.appointment_id>. Escreva agora sua resposta final ao cliente."`
when the declaration has a precondition `booking`, else the existing message. The recorded outcome
(start + reference) is `capability_state['booking']`, the exit's `tool_calls` result and its span.

`exit_agendado` declares no fields: an assistant-supplied start is rejected as undeclared (`PayloadValidator`).

`exit_sem_horario` keeps `fields: { motivo: string }`, no precondition; `exit_handoff` unchanged
(built-in escalation, any time).

## 4. `custom/playbooks/agendamento.md` (target shape)

```yaml
---
name: agendamento
title: Agendamento do lead qualificado
priority: 20
when_state:            # unchanged
  - opportunity_in_stage: qualified
  - contact_has_phone
  - playbook_not_completed: agendamento
trigger: >             # unchanged
  O lead foi qualificado e o próximo passo é agendar um atendimento.
requires: [scheduling, customer_registry]
exits:
  agendado:
    kind: terminal
    precondition: booking
  sem_horario:
    kind: terminal
    fields:
      motivo: string
---
```

- **No** `needs:`; body contains exactly four `[[depends: …]]` markers (`customer_registry` ×1,
  `scheduling` ×3) and none for `politica_reagendamento`.
- Body invariants asserted by the catalog spec (key phrases, as 088 does for model-behavior):
  - names the four tools: `customer_registry_find_by_phone`, `customer_registry_create`,
    `scheduling_list_slots`, `scheduling_book`, and `exit_agendado`, `exit_sem_horario`, `exit_handoff`;
  - locate/create by the contact's phone, register with the name the lead confirmed;
  - `not_found` → confirm the name and `customer_registry_create`; after two `ambiguous` answers → `exit_handoff`;
  - ask the preferred day; present **no more than three** of the returned times, only ones returned,
    in natural language; book only a returned `slot_id`;
  - `exit_agendado` only after `scheduling_book` succeeded;
  - empty day → offer the nearest available date, found by calling `scheduling_list_slots` on at most the three following days in order (none free → `exit_sem_horario` stating that no availability was found); all declined → `exit_sem_horario` with `motivo`;
  - request for a person, clinical urgency, any tool returning an error (an ERP failure transfers at once; never repeat the call), ERP unavailable →
    `exit_handoff` in the same turn, no promise of a booking;
  - contact without phone (the appended notice, or a tool error saying so) → `exit_handoff` in the same turn,
    stating the phone is missing, **without** asking the lead for it and without customer-registry calls;
  - no rescheduling/cancellation rules stated by the assistant.
- Steps are no longer numbered around a policy step; `[[depends:]]` markers sit on the same steps as
  in 088 (find/create → `customer_registry`; list/book/no-slot → `scheduling`).

## 5. Behavior matrix (spec scenarios → observable effect)

| Situation | Registered tools | Result |
|---|---|---|
| Both satisfied, phone on record | 4 capability tools + `exit_agendado`, `exit_sem_horario` + baseline (`search_knowledge_base`, `exit_handoff`) | US3 happy path |
| Either unsatisfied | baseline only for `agendamento`, no declared exits | Brief 06 degradation; 0 ERP requests; `unmet_requires` lists the unsatisfied ones only |
| Qualified, no phone, both satisfied | as first row | guidance carries `PHONE_MISSING_NOTICE` → `exit_handoff` stating phone missing, 0 capability calls; if the model calls anyway, `customer_registry_*` returns the no-phone error before any request |
| ERP failure on any call | as first row | tool returns the ERP-failure error → `exit_handoff` same turn, no booking promise |
| `exit_agendado` without booking | — | `{ error }`, state unchanged, `agendamento` not in `completed_playbooks`, can still book/transfer |
| After `agendado`/`sem_horario`/handoff | — | `completed_playbooks` contains `agendamento` (existing mechanism) → not pinned by state again, incl. after hand-back |
| Interruption takeover while pinned | takeover's declared tools only | no capability operations offered |
