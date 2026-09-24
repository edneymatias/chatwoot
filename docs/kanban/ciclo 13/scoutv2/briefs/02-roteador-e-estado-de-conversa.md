# Fase 02 — Roteador Determinístico e Estado por Conversa (Brief)

**Status**: Pronto para speckit
**Data**: 2026-09-24
**Master doc**: `docs/kanban/scoutv2/design.md` §4.4 (roteador), §6 (Fase 0)
**Depends on**: Brief 01 — fornece o catálogo de playbooks carregado e os predicados registrados que
o roteador avalia. **Este brief é o critério de corte do épico**: se o roteador não passar nas specs
sem LLM, o restante não vale a pena (design §6, Fase 0).

---

## 1. Problema

Hoje não existe roteamento: `AgentRunner#build_system_instructions` e `#build_tools`
(`custom/app/services/custom/scout/agent_runner.rb:145-163`) montam o mesmo prompt e o mesmo
catálogo de 7 tools em todo turno, para toda conversa, em todo estágio. A consequência medida é a
correção estocástica empilhada: com o auditor ligado, um turno custa no piso 3 chamadas de LLM e no
pior caso ~8 (design §1.1, `response_auditor.rb:29,61,71-82,84-93`), e a dupla confirmação existe
porque o classificador alucina — *"a customer picking one of several offered options … gets misread
as 'accepted a human-handoff offer' — confirmed 5/5 times"* (`response_auditor.rb:46-56`).

Não há também como responder *por que* o Scout fez o que fez: nenhuma decisão de comportamento é
persistida, então toda depuração é releitura de transcrição.

## 2. Contexto técnico

- `agent_runner.rb:145-155` — as 7 tools são encadeadas incondicionalmente no chat.
- `agent_runner.rb:145-163` — instruções e tools são calculadas **uma vez, antes** do `chat.ask`.
- `agent_runner.rb:20-23,43-45` — debounce, `AudienceMatcherService`, quota e API key rodam antes
  disso: são porteiros de **execução**, não de comportamento, e não mudam neste épico.
- Nenhuma tabela do módulo guarda estado de comportamento por conversa; o que existe é estado de
  negócio (oportunidade, estágio).
- Estado de negócio confiável já disponível no banco: estágio da oportunidade, campos obrigatórios
  pendentes, telefone do contato, nome-placeholder — tudo que os predicados do brief 01 leem.

## 3. Precedente

- **Botpress** roteia por playbook de triagem no próprio LLM (`Intent Triage → Lead Scoring | Team
  Routing`, design §2.3). **Captain V2** roteia 100% por LLM, via `handoff_to_*` registrado
  bidirecionalmente (`enterprise/app/services/captain/assistant/agent_runner_service.rb:136-141`) e
  índice no prompt do orquestrador (`lib/captain/prompts/assistant.liquid:82-84`).
- **Divergimos dos dois** (design §5): quando existe estado no banco, Ruby decide; o modelo só
  decide o resíduo de intenção. Motivo: só nós temos o modo de falha de classificação medido em
  produção (5/5 acima). O que se reaproveita do Captain é o formato do índice — uma linha por
  procedimento, com o trigger legível.

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | **Ativação híbrida**, com `when_state` determinístico tendo precedência sobre `trigger` textual | Estado já existe e é confiável; trigger cobre o resíduo de intenção que nenhum estado expressa. Trigger puro reintroduz a estocasticidade que causou o dobro-classificador (design decisão 1) |
| 2 | Contexto de roteamento montado **uma vez por turno** | Evita reconsulta por predicado; é também o objeto único que as specs injetam para testar roteamento sem banco nem LLM |
| 3 | Troca de playbook exige `priority` **estritamente maior** que a ativa | Empate mantém a ativa: é o que produz continuidade ("terça de manhã", dentro de `agendamento`, não re-roteia) sem conceito novo (design §4.4) |
| 4 | Limite de **2 transições por turno**, contado no `TurnRunner` e zerado a cada execução | O `transition_count` persistido é acumulado histórico, para observabilidade; reaproveitá-lo como limite faria um retry do Sidekiq herdar o saldo do turno que falhou e matar o roteamento na segunda tentativa (design §4.4) |
| 5 | `activation_reason` (`:state \| :trigger \| :transition`) é persistido em toda ativação | É o que torna a depuração possível — hoje não há como saber por que o modelo fez o que fez — e é o instrumento de medição da inversão assumida em `fora_de_prospeccao` (design §4.4 e §8) |
| 6 | O roteador expõe **uma interface única** `ctx → (playbook \| nil, confidence)` | Mantém a metade por-trigger como componente substituível (por classificador tipado com limiar em Ruby) sem reescrita; a substituição não entra neste corte, só a costura (design §4.4) |

## 5. Escopo preliminar

- `custom/app/services/custom/scout_v2/router.rb`: interface `ctx → (playbook, confidence)` e a
  regra de decisão.
- `custom/app/services/custom/scout_v2/routing_context.rb`: `conversation`, `contact`, `inbox`,
  `scout`, `opportunity` (com `stage_role`), `pending_fields`, `active_playbook`, `transitions`,
  `satisfied_capabilities`.
- Migração + modelo de `ichatr_scout_conversation_states`: `conversation_id`, `active_playbook`,
  `activated_at`, `activation_reason`, `transition_count`, `last_exit`, `unsatisfied_flags`.

## 6. Fora de escopo

- Montagem de prompt e execução de turno — brief 03.
- `open_playbook` (a metade por-trigger em runtime) — brief 04: aqui o roteador apenas devolve
  "nenhuma playbook forçada por estado", e a decisão do modelo é exercitada no brief seguinte.
- Classificador de intenção com saída tipada e limiar: explicitamente adiado (design §4.4) — custa
  chamada extra por turno e não há evidência de que `open_playbook` erre.
- Debounce, audiência, quota e API key: porteiros de execução, permanecem como estão.
- Janela de histórico de conversa: pré-existente ao v2 e ortogonal (design §8).

## 7. Critérios de aceite (rascunho)

### US1 — Contexto de roteamento montado uma vez por turno

- O contexto carrega conversa, contato, inbox, scout, oportunidade com `stage_role`, campos
  pendentes, playbook ativa, transições do turno e capabilities satisfeitas.
- Todos os predicados do turno leem esse mesmo objeto; nenhum predicado consulta o banco por conta
  própria.
- O contexto pode ser construído em memória numa spec, sem LLM e sem rede.

### US2 — Regra de decisão determinística

- Entre as playbooks cujo `when_state` casa, vence a de maior `priority`.
- A vencedora é a ativa → permanece; não há ativa → a vencedora é ativada; a vencedora supera a
  ativa (prioridade **estritamente** maior) → interrompe e troca; não supera → a ativa permanece.
- Nenhuma playbook casa e não há ativa → o roteador devolve "nenhuma", e a escolha fica para o
  modelo via índice (exercitado no brief 04).
- Playbook sem `when_state` nunca é ativada por estado, qualquer que seja sua `priority` — inclui
  `fora_de_prospeccao`, que tem prioridade máxima e ativação só por trigger (inversão assumida,
  design §4.4).

### US3 — Estado de comportamento persistido por conversa

- Toda ativação grava `active_playbook`, `activated_at` e `activation_reason`
  (`state` | `trigger` | `transition`).
- Um exit terminal zera a playbook ativa e registra `last_exit`.
- A terceira transição dentro do mesmo turno não acontece: o turno encerra e o fato fica registrado.
- Um retry do mesmo turno (Sidekiq) começa com o contador de transições do turno zerado, sem herdar
  o saldo da execução anterior; o `transition_count` persistido continua acumulando.

## 8. Testes (rascunho)

- `custom/spec/services/custom/scout_v2/router_spec.rb`: **sem LLM e sem rede** — uma tabela de
  estado → playbook esperada cobrindo continuidade, interrupção por prioridade estritamente maior,
  empate mantendo a ativa, e nenhuma casando.
- `custom/spec/models/custom/scout_v2/conversation_state_spec.rb`: `activation_reason` por caminho,
  exit terminal zerando a ativa, teto de 2 transições por turno e não-herança em retry.

---

> **Nota de proveniência**: decomposto de `docs/kanban/scoutv2/design.md` §4.4 e §6; o modo de falha
> 5/5 do classificador e o custo de 3–8 chamadas por turno estão medidos em
> `custom/app/services/custom/scout/response_auditor.rb:29,46-56,61,71-93`.
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
