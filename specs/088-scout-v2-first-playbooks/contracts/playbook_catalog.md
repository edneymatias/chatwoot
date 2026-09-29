# Contract: the first-cut playbook catalog (`custom/playbooks/*.md`)

Six files, loaded by `Playbook::Loader` and validated at boot by `Playbook::Validator`
(`config/initializers/scout_v2_playbooks.rb`, unchanged). Frontmatter below is normative; bodies
must satisfy the listed obligations (wording is authoring, in Portuguese, research §9). Exit
declaration syntax: [087 playbook_exit_declaration.md](../../087-scout-v2-exits-escalation/contracts/playbook_exit_declaration.md).
State-condition syntax: [state_conditions.md](./state_conditions.md).

## Frontmatter

```yaml
# fora_de_prospeccao.md
name: fora_de_prospeccao
title: Contato fora de prospecção
priority: 100
trigger: >
  O contato não busca uma nova oportunidade comercial: já é cliente com produto ou serviço em
  andamento, quer alterar ou cancelar algo existente, tem uma reclamação, ou faz uma pergunta
  puramente informativa sem interesse de compra. Não use para dúvidas de produto ou preço de um
  lead em prospecção (isso é duvida_comercial).
```

```yaml
# duvida_comercial.md
name: duvida_comercial
title: Dúvida comercial
priority: 60
trigger: >
  Um lead em prospecção pergunta sobre produto, serviço, preço, plano ou política comercial. Não
  use para cliente existente com reclamação ou pedido sobre algo já contratado (isso é
  fora_de_prospeccao).
```

```yaml
# pausa.md
name: pausa
title: Pausa pedida pelo lead
priority: 50
trigger: >
  O lead sinaliza que quer pausar ou encerrar por ora ("vou pensar", "depois eu volto",
  "obrigado").
```

```yaml
# identificacao.md
name: identificacao
title: Identificação do contato
priority: 30
when_state:
  - contact_identity_incomplete
  - playbook_not_completed: identificacao
trigger: >
  O contato ainda não informou como quer ser chamado ou não tem telefone registrado.
tools: [update_contact]
exits:
  identificado:
    kind: transition
    target: qualificacao
```

```yaml
# agendamento.md
name: agendamento
title: Agendamento do lead qualificado
priority: 20
when_state:
  - opportunity_in_stage: qualified
  - contact_has_phone
  - playbook_not_completed: agendamento
trigger: >
  O lead foi qualificado e o próximo passo é agendar um atendimento.
requires: [scheduling, customer_registry]
needs: [politica_reagendamento]
exits:
  agendado:
    kind: terminal
    fields:
      inicio: datetime
  sem_horario:
    kind: terminal
    fields:
      motivo: string
```

```yaml
# qualificacao.md (existing file — frontmatter replaced, body rewritten)
name: qualificacao
title: Qualificação comercial do lead
priority: 10
when_state:
  - in_qualification
  - playbook_not_completed: qualificacao
trigger: >
  Lead em prospecção, com ou sem oportunidade criada, com dados de qualificação a coletar ou já
  coletados e ainda não confirmados. Crie a oportunidade só quando houver interesse comercial.
tools: [manage_opportunity]
exits:
  qualificado:
    kind: transition
    target: agendamento
    stage: qualified
  desqualificado:
    kind: terminal
    stage: unqualified
    fields:
      motivo: string
```

Rejected at boot by the Validator (existing + new, [state_conditions.md](./state_conditions.md)):
duplicate names or priorities; exits on a situational playbook; an unregistered tool (no private-note
tool is registered in `Tools::Registry`, so FR-004 holds structurally); a `requires` name outside
`Capabilities::Catalog`; a `needs` name outside `BusinessFacts::Catalog` (NEW, FR-020); an invalid
state condition or argument (NEW, FR-009a); an invalid pending-step marker (NEW).

Asserted by the shipped-catalog spec (not Validator rules — they describe this catalog, not every
catalog): exactly these six names (FR-001); the declared tools/requires/needs/exits of the FR-002
table; `fora_de_prospeccao` has the highest priority and `identificacao` > `agendamento` >
`qualificacao` (FR-003); the `duvida_comercial`/`fora_de_prospeccao` triggers name each other as
excluded (FR-005).

## Body obligations (FR-010 – FR-015)

| File | Must say (source in v1, research §9) | Must not |
|---|---|---|
| `identificacao` | don't address the contact by a placeholder name; ask each missing item (listed in the appended "dados de contato faltando" block) **once** — name first, phone in a later message, never both in one message; record each answer with `update_contact` as soon as it arrives; never ask again in this conversation even without an answer; once every missing item has been asked once — answered, declined or ignored — call `exit_identificado` in that same turn without waiting | ask qualification questions; mention `manage_opportunity` |
| `qualificacao` | with no opportunity: create it with `manage_opportunity` as soon as the lead shows commercial interest, never without it; ask only the pending fields listed below, one per message; record each answer immediately; don't re-ask recorded data; acknowledge volunteered extras briefly without a new line of questioning; don't invent questions (to look thorough or from knowledge-base content); unqualified stage = human review queue, never "closing"; never move a qualified opportunity backwards; end with `exit_qualificado` (no pending field, and the lead confirmed the collected data and wants to proceed), `exit_desqualificado` with `motivo` (refusal / not a fit), or `exit_handoff` (human needed); after `exit_qualificado`, follow the guidance it returns in the same turn (FR-011a) | mention `update_contact`, `move_opportunity_stage`, `handover_to_human`, "aguarde a próxima mensagem" (old step 4) |
| `agendamento` | the full path, one numbered step each: find/create the customer record by phone `[[depends: customer_registry]]`; ask the preferred day; offer at most three slots `[[depends: scheduling]]`; book the chosen slot and call `exit_agendado` `[[depends: scheduling]]`; no slot in the window → offer the next available date, `exit_sem_horario` if all refused `[[depends: scheduling]]`; reschedule rules `[[depends: politica_reagendamento]]`; transfer with `exit_handoff` when the customer asks for a person, declares a clinical urgency, or after two failed attempts to find or create the customer record (brief 07, US acceptance); an unmarked line (it must not contain the literal `PENDENTE`, so the satisfied rendering stays free of it): when offering slots is unavailable, don't start scheduling — tell the customer an attendant will continue and call `exit_handoff` in this same turn, so a qualified lead is transferred in the qualifying turn (FR-011a, v1 parity) | invent slots or confirm a booking (reinforced by the pending notice) |
| `fora_de_prospeccao` | recognize the four non-prospect situations; don't try to solve, even if simple; call `exit_handoff` immediately with the reason; a new low-complexity, preventive or recurring request is still a commercial opportunity (not this playbook) | declare or mention data-changing tools |
| `duvida_comercial` | search with `search_knowledge_base`; answer only from what it returns; never invent; nothing relevant (or no knowledge) → say so, and `exit_handoff` if the customer needs that answer | declare tools; open a line of qualification questioning |
| `pausa` | acknowledge politely, leave the door open, no pending qualification question in this turn, no pressure | declare tools or exits |

### Asserted key phrases

Literal, case-sensitive substrings each shipped body MUST contain, and strings it MUST NOT contain.
They make every obligation above observable in the system text or opening result (tasks T036,
T052, T053, T064) and turn a deleted rule into a failing example (quickstart §5). Authors word the
rest of the body freely.

| File | Must contain | Must not contain |
|---|---|---|
| `identificacao` | `não use o nome registrado`, `uma única vez`, `primeiro o nome`, `nunca os dois na mesma mensagem`, `update_contact`, `sem esperar a resposta`, `exit_identificado` | `manage_opportunity` |
| `qualificacao` | `interesse comercial`, `pergunte apenas pelos campos pendentes`, `uma pergunta por mensagem`, `não invente perguntas`, `registre cada resposta imediatamente`, `não pergunte de novo`, `reconheça brevemente`, `fila de revisão humana`, `nunca retorne uma oportunidade que já atingiu o estágio qualificado`, `exit_desqualificado`, `exit_handoff`; `exit_qualificado` and `siga no mesmo turno` from T069 | `update_contact`, `move_opportunity_stage`, `handover_to_human`, `aguarde a próxima mensagem` |
| `fora_de_prospeccao` | `já é cliente`, `alterar ou cancelar`, `reclamação`, `puramente informativa`, `não tente resolver`, `imediatamente`, `continua sendo oportunidade comercial`, `exit_handoff` | `update_contact`, `manage_opportunity` |
| `duvida_comercial` | `search_knowledge_base`, `apenas com o que a base de conhecimento retornar`, `não invente`, `diga que não tem essa informação`, `exit_handoff` | `update_contact`, `manage_opportunity` |
| `pausa` | `responda com cordialidade`, `deixe a porta aberta`, `não retome perguntas de qualificação` | `update_contact`, `manage_opportunity` |
| `agendamento` | `dia de preferência`, `no máximo três horários`, `exit_agendado`, `exit_sem_horario`, `falar com uma pessoa`, `urgência clínica`, `duas tentativas`, `exit_handoff`, `chame exit_handoff neste mesmo turno`; in the raw body exactly five markers — `[[depends: customer_registry]]` once (find/create the customer record), `[[depends: scheduling]]` three times (offer slots, book, no slot in the window), `[[depends: politica_reagendamento]]` once (reschedule rules) — and no literal `PENDENTE` (checked on the raw body, T059), so the rendered text carries five `(PENDENTE — indisponível: …)` lines while all are unsatisfied and none when all are satisfied | `update_contact`, `manage_opportunity` |

## Pending-step markers

Syntax: `[[depends: name1, name2]]` anywhere on a body line (conventionally at the end of a numbered
step). Names are comma-separated, whitespace-trimmed. Boot rejects: an empty marker, a name that is
not one of this playbook's `requires`/`needs`, or a marker in a playbook that declares neither.

Rendering (per turn, `Playbook::ContentBuilder`, satisfaction from the routing snapshot):

| Marker names vs. satisfaction | Rendered line |
|---|---|
| all satisfied | marker removed |
| some unsatisfied | marker replaced by `(PENDENTE — indisponível: <unsatisfied names, comma-separated>)` |

When at least one line is pending, `ContentBuilder::PENDING_STEPS_NOTICE` follows the body:
`Passos marcados como PENDENTE dependem de integrações ou políticas ainda indisponíveis. Não simule,
não prometa e não confirme essas ações. Se o cliente precisar delas, use exit_handoff.`
(Contains `exit_handoff`, a token the Validator already accepts in any body.)
