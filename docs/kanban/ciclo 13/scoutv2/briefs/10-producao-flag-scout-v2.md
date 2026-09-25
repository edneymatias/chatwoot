# Fase 10 — Produção: Promoção por Flag `scout_v2` e Depreciação do v1 (Brief)

**Status**: Pronto para speckit
**Data**: 2026-09-24
**Master doc**: `docs/kanban/ciclo 13/scoutv2/design.md` §4.11 (ativação e configuração de modelo), §6 (Fase 5 + checklist de promoção), §4.9
**Depends on**: Brief 03, que declara a flag `scout_v2` e os dois pontos de despacho que este brief
usa em produção; Briefs 06 (as seis playbooks) e 07 (capabilities), sem os quais uma conta real em
v2 perderia agendamento. Os Briefs 08 e 09 não bloqueiam a promoção.

---

## 1. Problema

Revisão do design em 2026-09-24: a seleção de engine estava prevista como **coluna `engine` por
scout**, "exposta no super admin / configuração do scout" (versão anterior deste brief, §5). Essa
decisão nunca foi fechada, e a revisão encontrou três lacunas:

- **O Super Admin não tem tela de scout.** O que existe é o checkbox de feature por conta
  (`app/views/super_admin/accounts/show.html.erb:36-52`, alimentado por `config/features.yml`).
  "Expor no super admin" significaria construir um dashboard novo.
- **Exposta na configuração do scout, a coluna deixaria qualquer administrador da conta promover o
  v2** sem passar pelo checklist. E o checklist existe justamente porque ligar o v2 desativa as
  `ScoutTool`: hoje são 4 ativas no ambiente de dev (`pesquisar_cliente`, `cadastrar_pessoa`,
  `obter_horarios_livres`, `agendar`), todas integrações com o ERP do cliente.
- **Com v1 e v2 na mesma conta, as duas engines dividiriam uma única configuração de modelo**
  (`ichatr_scout_account_configs`, uma linha por conta, `db/schema.rb:1282-1290`). O v2 depende
  mais de tool calling confiável que o v1 e não teria como usar outro modelo.

Continua valendo o problema de origem: sem promoção, o v2 dos briefs 01–09 não chega a nenhuma
conversa real, o churn do v1 continua (24 commits no módulo) e as duas bases convivem por tempo
indefinido.

## 2. Contexto técnico

- **A flag e o despacho já existem quando este brief começa.** O Brief 03 declara `scout_v2` em
  `config/features.yml` (`enabled: false`, `column: feature_flags_ext_1`, com MANIFEST) e faz o
  branch nos dois únicos pontos que escolhem engine: `process_message_job.rb:53` e
  `playground_messages_controller.rb:14`. Aqui a flag deixa de ser só uma chave de desenvolvimento
  e passa a ser o mecanismo de promoção em produção.
- `config/features.yml:10` define a convenção `deprecated:` ("purpose of feature flag is done").
  `:15-16` proíbe remover ou reordenar entradas, porque a posição de bit fica persistida em
  `accounts.feature_flags_ext_1`.
- `custom/app/models/scout.rb:55-71` (`llm_chat`) lê `ScoutAccountConfig` por conta. O v2 usa o
  mesmo caminho (design decisão 13).
- `app/javascript/dashboard/routes/dashboard/scout/pages/ScoutToolsList.vue` é a UI das tools
  configuradas por conta. As constantes de flag no frontend entram por MANIFEST em
  `app/javascript/dashboard/featureFlags.js` (`bin/sync-custom-module-hooks:122-137`).
- `custom/app/models/scout_tool.rb` e `custom/app/services/custom/scout/tools/call_custom_api.rb`:
  o v2 não consome nenhum dos dois (design decisão 4).
- O conjunto do v1 que a depreciação remove é `custom/app/services/custom/scout/agent_runner.rb`,
  `playground_runner.rb`, `response_auditor.rb`, `system_prompts_service.rb`,
  `system_prompts/funnel_section_builder.rb`, `action_classifier_service.rb`,
  `claim_consistency_service.rb`, `opportunity_stage_transition_service.rb`,
  `tools/move_opportunity_stage.rb`, `tools/handover_to_human.rb` e `tools/call_custom_api.rb`.
- `lib/integrations/llm_instrumentation.rb:10-64` e `llm_instrumentation_helpers.rb:54-74`:
  `metadata:` já vira atributo Langfuse. Os metadados de playbook entram por aí desde o Brief 03.

## 3. Precedente

O Captain V2 do upstream escolhe engine exatamente assim: pela flag **de conta**
`captain_integration_v2` (`config/features.yml:184-187`, lida em
`enterprise/app/jobs/captain/conversation/response_builder_job.rb:210-212`), e não por coluna no
assistant. Os classificadores pós-hoc rodam só no ramo V1. O que se reaproveita é o formato: uma
flag de conta decide a engine num único ponto de despacho. O que não se aplica: o upstream mantém o
V1 vivo e a flag é `premium`, enquanto aqui a flag é temporária e o v1 é removido na depreciação.

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | A engine é escolhida pela **flag de conta `scout_v2`**, e cada conta roda **uma** engine: com a flag, v2 em playground e inbox; sem ela, v1 | A coluna `engine` por scout foi descartada pelas três lacunas do §1 (design §4.11). A granularidade passa a ser a conta: contas com vários scouts promovem todos juntos, o que é aceitável porque o v2 existe para substituir o v1, não para conviver com ele |
| 2 | **Só o Super Admin promove.** O administrador da conta não vê nem escolhe engine, e nenhuma tela do dashboard ganha seletor | A promoção desliga integrações (`ScoutTool`) e exige o preflight (decisão 3): é ato do operador. O checkbox do Super Admin já existe para qualquer flag de `features.yml`, sem código novo de UI |
| 3 | **Preflight executável por conta antes de marcar a flag**, que chama o v2 direto, sem passar pelos pontos de despacho | O playground da conta segue a flag, então não roda v2 antes da promoção (design §4.11). A alternativa considerada era marcar a flag, testar no playground e desmarcar se falhar. Foi rejeitada porque, nessa janela, conversas reais de clientes já passariam pelo v2 sem verificação |
| 4 | **Modelo, provider e API key continuam em `ScoutAccountConfig`**, sem campo por engine | Com uma engine por conta não há conflito de configuração (design decisão 13). Se o modelo da conta falhar no tool calling do v2 (visível no Langfuse), o primeiro remédio é trocar o modelo da conta |
| 5 | Numa conta com `scout_v2`, as `ScoutTool` **não são oferecidas ao modelo e isso aparece na UI de tools**, sem silêncio | A configuração continua salva: desmarcar a flag devolve as tools ao v1 sem perda. Sinalizar evita que o administrador da conta edite tools achando que estão em uso |
| 6 | A depreciação é **remoção de código**. A flag fica em `features.yml` com `deprecated: true` e sem nenhuma leitura no código | O `AGENTS.md` pede cutover limpo, sem caminho deprecado. Apagar a entrada deslocaria a posição de bit das flags seguintes (`features.yml:15-16`); `deprecated: true` é a convenção do próprio arquivo (`:10`) |
| 7 | `activation_reason` legível em toda conversa é **critério de conclusão da fase**, não observabilidade opcional | É a contrapartida em produção do roteamento híbrido: mede a inversão assumida de `fora_de_prospeccao` e alimenta o item 6.7 (design §4.4, §4.9 e §8) |
| 8 | A promoção **não reintroduz nenhuma auditoria** | A verificação estrutural substitui a estocástica. Uma reintrodução só acontece de forma cirúrgica, com classe de erro observada, e avalia antes a rede fora do turno no formato do `InboxPendingConversationsResolutionJob` do Captain (design §4.10 e §6.7) |

## 5. Escopo preliminar

- Preflight por conta (rake task, ex.: `scout_v2:preflight[account_id]`) com saída legível ao
  operador:
  - `ScoutTool` ativas da conta que deixam de ser oferecidas;
  - por playbook, as capabilities de `requires` insatisfeitas para a conta, via `CapabilityRegistry`
    (Brief 07);
  - para cada scout ativo da conta, sonda de `exit_handoff` sem playbook ativa: um pedido explícito
    de atendente executado no v2 em modo playground, sem enviar mensagem a contato e sem gravar
    estado de conversa real;
  - scouts ativos com `role`/`scope` vazios, com a `persona` atual impressa para a reescrita
    (Brief 12).
- Sinalização na UI de tools (`ScoutToolsList.vue`) quando a conta tem `scout_v2`: as tools
  configuradas não são usadas pelo Scout. Inclui a constante `SCOUT_V2` em `featureFlags.js` com
  entrada de MANIFEST e i18n em `en.json`/`pt_BR.json`.
- Depreciação, depois que todas as contas tiverem `scout_v2`:
  - remover o conjunto do v1 listado no §2, com specs e traduções órfãs;
  - remover `persona` (coluna, `alias_attribute :system_prompt`, `scout_params`, campo da tela e
    traduções), que só o v1 lê (Brief 12, decisão 3);
  - remover os branches de despacho, deixando o v2 incondicional;
  - marcar `scout_v2` com `deprecated: true`, removendo todas as leituras (backend, frontend e
    constante `SCOUT_V2`) e as entradas de MANIFEST que as sustentavam.

## 6. Fora de escopo

- Declarar a flag `scout_v2` e o despacho nos dois pontos: já feito no Brief 03.
- Coluna `engine` por scout e seletor de engine no dashboard: descartados (decisões 1 e 2).
- Configuração de modelo por engine (decisão 4).
- `ScoutTool` como provider de capability (design §6.1). O gatilho é o primeiro cliente sem adapter
  para a capability de que precisa, e isso não é pré-requisito da promoção.
- Materialização das playbooks em banco e UI de enable/disable por conta (design §6.3).
- Rede de auditoria fora do turno (design §6.7): avaliada com evidência de produção, depois desta
  fase.
- Janela de histórico de conversa (`agent_runner.rb:165-167` carrega todas as mensagens
  não-privadas sem limite). É pré-existente e ortogonal; vira spec própria se aparecer no Langfuse
  estourando orçamento (design §8).
- Mudar o default de `scout_v2` para `enabled: true` antes da depreciação. Enquanto houver contas no
  v1, uma conta nova recebe o v2 só se o operador marcar a flag.

## 7. Critérios de aceite (rascunho)

### US1 — Promoção por conta, só pelo Super Admin, com rollback imediato

- Marcar `scout_v2` na tela da conta no Super Admin faz as próximas mensagens de todos os scouts da
  conta passarem pelo `TurnRunner`, e o playground da conta também passa a rodar v2.
- Desmarcar a flag devolve a conta ao v1 sem deploy e sem perda de dados de conversa. O estado v2
  gravado (`ichatr_scout_conversation_states`) permanece e é ignorado pelo v1.
- Nenhuma tela acessível ao administrador da conta permite ver ou trocar a engine.
- O v2 responde com o provider, o modelo e a API key configurados em Scout → Configurações, os
  mesmos que o v1 usava na conta.

### US2 — Preflight antes de promover, e tools fora de uso visíveis

- Para uma conta ainda sem a flag, o operador obtém do preflight quatro respostas:
  - quais `ScoutTool` ativas deixarão de ser oferecidas;
  - quais capabilities exigidas pelas playbooks estão insatisfeitas;
  - para cada scout ativo, se um pedido explícito de atendente **sem playbook ativa** resulta em
    `exit_handoff`;
  - quais scouts ativos estão com `role`/`scope` vazios, e a `persona` de cada um.
- O preflight não envia mensagem a nenhum contato e não altera nenhuma conversa real.
- Numa conta com `scout_v2`, a tela de tools mostra que as tools configuradas não são usadas pelo
  Scout, e nenhuma `ScoutTool` é oferecida ao modelo.

### US3 — Toda conversa em produção explica a si mesma

- Para qualquer conversa de uma conta em v2 é possível ler qual playbook esteve ativa, por que ativou
  (`state` | `trigger` | `transition`), qual foi o desfecho e que pendências existiam.
- Os mesmos campos estão no trace do Langfuse (`playbook`, `activation_reason`, `exit_action`,
  `unsatisfied_flags`), sem o laço de reparo e sem as 3–8 gerações aninhadas do v1.
- A taxa de ativação de `fora_de_prospeccao` por trigger é mensurável: é o instrumento da inversão
  assumida no design §4.4.

### US4 — O v1 é removido, não deixado para trás

- Com todas as contas marcadas com `scout_v2`, os serviços de comportamento do v1 e as tools mortas
  (`move_opportunity_stage`, `handover_to_human`, `call_custom_api`) saem do código, junto com suas
  specs e traduções órfãs.
- Os branches de despacho saem e o v2 passa a ser incondicional. `scout_v2` fica com
  `deprecated: true` em `features.yml`, deixa de aparecer no Super Admin e não tem nenhuma leitura
  restante no código.
- A suíte completa passa após a remoção, e não resta nenhuma referência ao namespace de
  comportamento `Custom::Scout::` removido.

## 8. Testes (rascunho)

- Spec do preflight: relatório com `ScoutTool` ativas, capabilities insatisfeitas por playbook e
  resultado da sonda de `exit_handoff`, com cliente LLM dublado. Também verifica que nenhuma
  mensagem é criada e nenhum estado de conversa real é gravado.
- Spec de componente de `ScoutToolsList.vue`: sinalização presente com `scout_v2`, ausente sem.
- Verificação operacional antes da primeira promoção real: preflight da conta candidata, marcação
  no Super Admin, primeira conversa conferida no Langfuse (`activation_reason` presente).
- Suíte completa (`bundle exec rspec`, `pnpm test`, `pnpm eslint`, `bundle exec rubocop`) e
  `bin/sync-custom-module-hooks --check`/`--audit` após a remoção da US4. É a prova de que a
  depreciação não deixou referência pendente nem entrada de MANIFEST órfã.

---

> **Nota de proveniência**: substitui `10-producao-engine-v2.md`. A seleção por coluna `engine` por
> scout foi trocada pela flag de conta `scout_v2` depois da revisão de 2026-09-24, que confrontou o
> design com o mecanismo de ativação do v1 (`config/features.yml:276-279` + checkbox do Super Admin)
> e com a configuração de modelo por conta (`ichatr_scout_account_configs`). A decisão está
> registrada no design (decisões 5 e 13, §4.11, §6 Fase 5 e §8).
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
