# Fase 03 — TurnRunner de Playground e Primeira Playbook (Brief)

**Status**: Pronto para speckit
**Data**: 2026-09-24
**Master doc**: `docs/kanban/scoutv2/design.md` §4.2 (ciclo do turno), §4.9 (observabilidade), §6 (Fase 0)
**Depends on**: Brief 01 (catálogo carregado) e Brief 02 (roteador + estado por conversa) — este
brief é o que fecha a Fase 0 do design, provando o conjunto num turno real de playground.

---

## 1. Problema

A Fase 0 só se prova executando: roteador e loader podem passar em spec e ainda assim não produzir
um turno utilizável. Hoje o único caminho de execução do Scout é
`custom/app/services/custom/scout/agent_runner.rb`, que monta prompt e tools uma vez antes do
`chat.ask` (`:145-163`) e, com o auditor ligado, gasta no piso 3 chamadas de LLM por turno e ~8 no
pior caso (design §1.1). Não há nenhum caminho de execução alternativo onde uma playbook possa ser
exercitada sem tocar nesse serviço — e tocá-lo está proibido por desenho (design decisão 5: os
serviços de comportamento do v1 não recebem uma linha de diff enquanto o v2 é construído).

## 2. Contexto técnico

- `custom/app/services/custom/scout/playground_runner.rb` — já existe um caminho de execução para
  verificação comportamental fora da produção, usado nas fases anteriores do Scout v1.
- `agent_runner.rb:71-74` — o chat é montado com `with_schema(...).with_instructions(...)` e tools
  encadeadas; `scout.rb:55-71` expõe `llm_chat`.
- **RubyLLM 1.15.0, verificado no container** (design §4.2 e §9): `Chat#complete` passa `@messages`
  e `@tools` **por referência a cada iteração**; `handle_tool_calls` termina em
  `halt_result || complete(&)`; `with_tool` escreve em `@tools`; `with_instructions` sobrescreve a
  mensagem de sistema no lugar. É o equivalente ao getter-por-iteração do llmz — a base do
  `open_playbook` do brief 04.
- `lib/integrations/llm_instrumentation.rb:10-64` — `instrument_llm_call`,
  `instrument_agent_session`, `instrument_tool_call` (OpenTelemetry → Langfuse) já existem; o v1 os
  usa em `agent_runner.rb:180-186` e em toda tool (`tools/base_tool.rb:16`).
- `llm_instrumentation_helpers.rb:54-74` — `metadata:` em `instrumentation_params` vira atributo
  Langfuse arbitrário: é por onde os metadados de playbook entram no trace, sem código novo de
  observabilidade.

## 3. Precedente

`Captain::Concerns::Agentable#agent` (upstream 4.18.0,
`enterprise/app/models/concerns/agentable.rb:6-33`) monta
`Agents::Agent.new(instructions: ->(context) { … }, tools:, model:, temperature:)` — **instruções
como lambda por execução**. Confirma que montar o prompt por turno, a partir de contexto, é o
padrão já disponível em Ruby no próprio repositório. Não se aplica o resto do arranjo do Captain
(gem `ai-agents`, orquestrador + sub-agentes por scenario): o v2 usa RubyLLM, que o Scout já usa.

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | **Playground primeiro**, produção só na Fase 5 | v1 vai ao ar e continua recebendo correções enquanto o v2 é construído; rollback é flipar uma coluna (design decisão 5) |
| 2 | Namespace `Custom::ScoutV2::*`, com `AgentRunner`, `ResponseAuditor` e `SystemPromptsService` do v1 **sem diff** | Duas bases convivem sem interferência; a depreciação é explícita e posterior (brief 10) |
| 3 | Instrumentação **desde o primeiro turno**, não como fase posterior | Já existe e o v1 já a usa; herdar custa pouco e é o que torna a Fase 1 observável desde o início (design §4.9) |
| 4 | `qualificacao` é a **primeira e única** playbook deste brief, com zero capability | É a que tem origem mais direta no v1 (`FunnelSectionBuilder`) e não depende de integração externa (design §6, Fase 0) |
| 5 | Neste brief, o corpo de `qualificacao` **não referencia exits** | Exits são mecanismo do brief 05; a validação de boot do brief 01 reprova exit citado e não declarado, então o corpo termina respondendo ao lead — o desfecho tipado entra com o mecanismo |

## 5. Escopo preliminar

- `custom/app/services/custom/scout_v2/turn_runner.rb`: monta o contexto (brief 02), consulta o
  roteador, monta o prompt do turno, executa `chat.ask`, persiste o estado e despacha a resposta.
- Instrumentação no `TurnRunner`: `instrument_agent_session` + `instrument_llm_call`, com
  `metadata:` carregando `playbook`, `activation_reason` e `unsatisfied_flags`.
- Caminho de playground para o v2 (novo runner ou seleção de engine dentro do existente, sem
  alterar o comportamento do playground do v1).
- `custom/playbooks/qualificacao.md`: corpo derivado de `system_prompts/funnel_section_builder.rb`,
  `when_state: [opportunity_open, pending_required_fields]`, `tools: [manage_opportunity]`.
- Tool `manage_opportunity` disponível ao v2 em versão escopada (declarada pela playbook, não
  sempre-on).

## 6. Fora de escopo

- `open_playbook`, índice de playbooks e Instructions tipadas — brief 04.
- Exits, Escalation e remoção do auditor — brief 05. Neste brief o v2 simplesmente **não tem**
  auditor: não há o que remover, porque nada dele é chamado.
- As outras cinco playbooks — brief 06.
- Produção, coluna `engine`, despacho por scout — brief 10.
- Qualquer diff em `agent_runner.rb`, `response_auditor.rb`, `system_prompts_service.rb`.

## 7. Critérios de aceite (rascunho)

### US1 — Um turno v2 executa no playground

- Dado um scout e uma conversa de playground, o turno monta o prompt a partir da playbook resolvida
  pelo roteador e responde em **uma única chamada de LLM de topo** (sem auditor, sem classificador,
  sem reparo).
- O prompt do turno contém o corpo da playbook ativa e **não** contém o bloco de 11 bullets do v1.
- As únicas tools disponíveis ao modelo são as declaradas pela playbook ativa, mais a leitura
  (`search_knowledge_base`); `move_opportunity_stage`, `handover_to_human` e `call_custom_api` não
  são oferecidas.
- O estado da conversa (playbook ativa, `activation_reason`) fica persistido ao fim do turno.

### US2 — O turno é legível no Langfuse desde o primeiro dia

- Cada turno v2 gera uma sessão instrumentada com uma geração de LLM, sem as 3–8 gerações aninhadas
  do caminho v1 com auditor.
- O trace carrega `playbook` e `activation_reason` como atributos.
- Cada tool executada no turno aparece como tool call instrumentada.

### US3 — `qualificacao` qualifica um lead no playground

- Com oportunidade aberta e campos obrigatórios pendentes, o roteador ativa `qualificacao` por
  estado (`activation_reason: state`) e o Scout conduz a coleta seguindo os passos do corpo.
- O Scout usa `manage_opportunity` para registrar o que coletou.
- Preenchidos os campos, a conversa segue sem re-roteamento espúrio a cada mensagem (continuidade
  do brief 02, exercitada num diálogo real).
- O comportamento de funil observado é equivalente ao do v1 para o mesmo cenário, sem as diretrizes
  globais de funil no prompt.

## 8. Testes (rascunho)

- `custom/spec/services/custom/scout_v2/turn_runner_spec.rb`: composição do prompt e do catálogo de
  tools a partir de uma playbook fixa, com o cliente LLM dublado — verifica **o que foi montado**,
  não texto de resposta.
- Verificação comportamental via playground (mesmo padrão das fases anteriores do Scout): diálogo
  de qualificação ponta a ponta, com trace conferido no Langfuse.

---

> **Nota de proveniência**: decomposto de `docs/kanban/scoutv2/design.md` §4.2, §4.9 e §6; o
> comportamento de `Chat#complete`/`handle_tool_calls`/`with_tool` foi lido no gem
> `ruby_llm-1.15.0` dentro do container durante o design (§9).
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
