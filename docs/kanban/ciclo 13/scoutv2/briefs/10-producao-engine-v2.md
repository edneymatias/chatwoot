# Fase 10 — Produção: `engine: v2`, Promoção e Depreciação do v1 (Brief)

**Status**: Pronto para speckit
**Data**: 2026-09-24
**Master doc**: `docs/kanban/scoutv2/design.md` §6 (Fase 5 + checklist de promoção), §4.9
**Depends on**: Brief 06 (as seis playbooks) e Brief 07 (capabilities) — sem eles um scout real em
v2 perderia agendamento. Briefs 08 e 09 são independentes e não bloqueiam a promoção.

---

## 1. Problema

Todo o v2 dos briefs 01–09 roda **apenas no playground**, por decisão de desenho (design decisão 5:
o v1 vai ao ar e continua recebendo correções enquanto o v2 é construído). Sem um mecanismo de
seleção por scout, o trabalho não chega a nenhuma conversa real e as duas bases convivem
indefinidamente — que é o pior dos dois mundos: o churn do v1 continua (24 commits no módulo) e o
v2 não produz evidência de produção.

Há também um risco concreto de promoção: ligar o v2 num scout **desativa as `ScoutTool` daquele
scout**, porque no primeiro corte não existe provider HTTP de capability (design decisão 4 e §6).
Promover sem verificar isso quebra silenciosamente integrações em uso — hoje, 4 tools ativas no
ambiente de dev (`pesquisar_cliente`, `cadastrar_pessoa`, `obter_horarios_livres`, `agendar`).

## 2. Contexto técnico

- `custom/app/models/scout.rb` e o job de processamento de mensagem do módulo (ambos **arquivos do
  fork**) são os dois pontos onde entra a coluna `engine` e o branch de despacho — **não há diff
  upstream** envolvido (design decisão 5).
- `custom/app/services/custom/scout/agent_runner.rb`, `response_auditor.rb`,
  `system_prompts_service.rb`, `action_classifier_service.rb`, `claim_consistency_service.rb`,
  `opportunity_stage_transition_service.rb`, `tools/move_opportunity_stage.rb`,
  `tools/handover_to_human.rb`, `tools/call_custom_api.rb`, `system_prompts/funnel_section_builder.rb`
  — o conjunto do v1 que a depreciação remove, depois de nenhum scout usar `engine: v1`.
- `lib/integrations/llm_instrumentation.rb:10-64` + `llm_instrumentation_helpers.rb:54-74` — o
  `metadata:` já vira atributo Langfuse arbitrário; os metadados de playbook entram por aí desde o
  brief 03.
- `custom/app/models/scout_tool.rb` — as tools configuradas por conta, que o v2 não consome.
- Precedente interno de bifurcação de engine no próprio repositório:
  `enterprise/app/jobs/captain/conversation/response_builder_job.rb:22` bifurca por
  `captain_integration_v2` e roda os classificadores pós-hoc só no ramo V1 (`:45-46` vs `:50-61`).

## 3. Precedente

Além da bifurcação V1/V2 do Captain (acima), o próprio fork já opera promoção gradual por flag de
scout nas fases anteriores do Scout v1. O que este brief acrescenta é o **checklist de promoção
obrigatório**, porque aqui a promoção tem um efeito colateral não óbvio (desligar `ScoutTool`) que
nenhuma flag anterior tinha.

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | Seleção de engine é **coluna `engine` por scout**, com rollback por flip de coluna | Duas bases convivendo em namespaces separados; o v1 permanece sem diff até a depreciação (design decisão 5) |
| 2 | **Checklist obrigatório de promoção por scout** antes de ligar `engine: v2` | Ligar o v2 desativa as `ScoutTool` daquele scout; e é preciso confirmar que `exit_handoff` responde a pedido explícito de atendente **sem playbook ativa** — o caminho crítico do §4.1 (design §6) |
| 3 | A depreciação do v1 é **remoção de código**, não flag morta deixada no lugar | `AGENTS.md`: cutover limpo, sem shims nem caminhos deprecados; código obsoleto pelo cutover está em escopo |
| 4 | `activation_reason` legível em toda conversa é **critério de conclusão da fase**, não item de observabilidade opcional | É a contrapartida em produção da decisão de roteamento híbrido: mede a inversão assumida de `fora_de_prospeccao` e alimenta o item 6.7 (design §4.4, §4.9 e §8) |
| 5 | Nenhuma reintrodução de auditoria acompanha a promoção | A verificação estrutural substitui a estocástica; reintrodução é cirúrgica, com classe de erro observada, e avalia **antes** a rede fora do turno no formato do `InboxPendingConversationsResolutionJob` do Captain (design §4.10 e §6.7) |

## 5. Escopo preliminar

- Migração + coluna `engine` em `scouts` (default `v1`), exposta no super admin / configuração do
  scout.
- Branch de despacho no job de processamento de mensagem do módulo: `engine: v2` →
  `Custom::ScoutV2::TurnRunner`; `v1` → `Custom::Scout::AgentRunner` (inalterado).
- `ScoutTool`: não oferecida quando `engine: v2`; sinalização clara na UI de tools do scout.
- Verificação/checklist de promoção executável (rake task ou tela), cobrindo tools cobertas,
  capabilities satisfeitas e resposta de `exit_handoff` sem playbook ativa.
- Depreciação: remoção dos serviços de comportamento do v1 e das tools mortas, após nenhum scout
  restar em `engine: v1`.
- i18n dos rótulos novos (`en.json`/`pt_BR.json`) e do que for de backend (`en.yml`/`pt_BR.yml`).

## 6. Fora de escopo

- `ScoutTool` como provider de capability (design §6.1) — o gatilho é o primeiro cliente sem adapter
  para a capability de que precisa, e não é pré-requisito da promoção.
- Materialização das playbooks em banco e UI de enable/disable por conta (design §6.3).
- Rede de auditoria fora do turno (design §6.7) — avaliada com evidência de produção, depois desta
  fase.
- Janela de histórico de conversa (`agent_runner.rb:165-167` carrega todas as mensagens não-privadas
  sem limite): pré-existente e ortogonal, vira spec própria se aparecer no Langfuse estourando
  orçamento (design §8).

## 7. Critérios de aceite (rascunho)

### US1 — Engine selecionável por scout, com rollback imediato

- Um scout em `engine: v2` processa mensagens reais pelo `TurnRunner`; um scout em `engine: v1`
  continua no `AgentRunner`, com comportamento idêntico ao de hoje.
- Voltar o scout para `v1` restaura o comportamento anterior sem deploy e sem perda de dados de
  conversa.
- Os serviços de comportamento do v1 não têm diff nesta entrega.

### US2 — Promoção só depois de checklist verificado

- Antes de ligar `engine: v2` num scout, é possível verificar: quais `ScoutTool` daquele scout serão
  desativadas e se alguma cobre necessidade não atendida pelas capabilities; se as capabilities
  exigidas pelas playbooks estão satisfeitas para a conta.
- Um scout em `engine: v2` não oferece `ScoutTool` ao modelo, e isso é visível na UI — não um
  silêncio.
- No playground do scout candidato, um pedido explícito de atendente **sem playbook ativa** resulta
  em transferência — verificação obrigatória do checklist.

### US3 — Toda conversa em produção explica a si mesma

- Para qualquer conversa de scout em v2 é possível ler qual playbook esteve ativa, por que ativou
  (`state` | `trigger` | `transition`), qual foi o desfecho e que pendências existiam.
- Os mesmos campos estão no trace do Langfuse (`playbook`, `activation_reason`, `exit_action`,
  `unsatisfied_flags`), sem o laço de reparo e sem 3–8 gerações aninhadas.
- A taxa de ativação de `fora_de_prospeccao` por trigger é mensurável — é o instrumento da inversão
  assumida em §4.4.

### US4 — O v1 é removido, não deixado para trás

- Com nenhum scout em `engine: v1`, os serviços de comportamento do v1 e as tools mortas
  (`move_opportunity_stage`, `handover_to_human`, `call_custom_api`) são removidos do código,
  junto com suas specs e traduções órfãs.
- A coluna `engine` e o branch de despacho saem junto, ou permanecem apenas se houver decisão
  explícita do operador de manter mais de um engine.
- A suíte completa passa após a remoção; nenhuma referência pendente ao namespace `Custom::Scout::`
  de comportamento resta no código.

## 8. Testes (rascunho)

- `custom/spec/models/scout_spec.rb` (extensão): default de `engine`, e `ScoutTool` indisponível em
  `v2`.
- Spec do job de processamento de mensagem: despacho para o runner correto por `engine`.
- Verificação no playground do scout candidato, conforme o checklist da US2, antes da promoção real.
- Suíte completa (`bundle exec rspec`, `pnpm test`) após a remoção da US4 — é a prova de que a
  depreciação não deixou referência pendente.

---

> **Nota de proveniência**: decomposto de `docs/kanban/scoutv2/design.md` §6 (Fase 5, checklist de
> promoção) e §4.9; o efeito colateral de desativar `ScoutTool` está declarado na decisão 4 e na
> tabela de riscos (§8).
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
