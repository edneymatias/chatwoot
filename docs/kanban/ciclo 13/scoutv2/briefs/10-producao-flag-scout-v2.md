# Fase 10 — Produção: Promoção por Flag `scout_v2` e Depreciação Reversível do v1 (Brief)

**Status**: Pronto para speckit
**Data**: 2026-09-24 · depreciação revista em 2026-10-01 (esconder, não apagar)
**Master doc**: `docs/kanban/ciclo 13/scoutv2/design.md` §4.11 (ativação e configuração de modelo), §6 (Fase 5 + checklist de promoção), §4.9
**Depends on**: Brief 03, que declara a flag `scout_v2` e os dois pontos de despacho que este brief
usa em produção; Briefs 06 (as seis playbooks) e 07 (capabilities), sem os quais uma conta real em
v2 perderia agendamento; Brief 12 (campos `role`/`scope`/estilo na tela, cuja visibilidade este brief
passa a condicionar); Briefs 13 e 14, que carregam a prova do agendamento contra o ERP real. Os
Briefs 08 e 09 não bloqueiam a promoção.

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

**A tela do scout mostra configuração da engine que não está rodando** (achado do usuário em
2026-10-01, conferido no código). Hoje a tela é a mesma nas duas engines:

| Na tela | Onde | Quem lê |
|---|---|---|
| "Persona e Prompt do Sistema" | `ScoutGeneralSettings.vue:147-156`; modal de criação `ScoutList.vue:340`; subtítulo do card `ScoutList.vue:255` | só o v1 (`system_prompts_service.rb:173-183`) |
| Página de Tools | `ScoutToolsList.vue`, rota `scout_tools` (`scout.routes.js:32-34`), entrada em `Sidebar.vue` | só o v1 (`call_custom_api`; design decisão 4) |
| Aba "Produtos" (`product_catalog`) | `ScoutProductsTab.vue`, aba em `ScoutDetail.vue:55` | só o v1 (`agent_runner.rb:158`) |
| "Papel e Objetivo", "Escopo e Limites", tom, tamanho de resposta, saudação | `ScoutGeneralSettings.vue:172-241` | só o v2 (brief 12) |
| Funil, Conhecimento, Público, Caixas, debounce, cota | abas e campos restantes | os dois |

Numa conta v2, o administrador escreve na persona e nada muda; numa conta v1, escreve em "Papel e
Objetivo" e nada muda. A redundância mais visível é a persona ao lado dos campos que a substituem.

Continua valendo o problema de origem: sem promoção, o v2 dos briefs 01–09 não chega a nenhuma
conversa real e as duas bases convivem por tempo indefinido.

## 2. Contexto técnico

- **A flag e o despacho já existem quando este brief começa.** O Brief 03 declara `scout_v2` em
  `config/features.yml` (`enabled: false`, `column: feature_flags_ext_1`, com MANIFEST) e faz o
  branch nos dois únicos pontos que escolhem engine: `process_message_job.rb:53` e
  `playground_messages_controller.rb:14`. Aqui a flag deixa de ser só uma chave de desenvolvimento
  e passa a ser o mecanismo de promoção em produção.
- `config/features.yml:15-16` proíbe remover ou reordenar entradas, porque a posição de bit fica
  persistida em `accounts.feature_flags_ext_1`.
- `custom/app/models/scout.rb:55-71` (`llm_chat`) lê `ScoutAccountConfig` por conta. O v2 usa o
  mesmo caminho (design decisão 13).
- As constantes de flag no frontend entram por MANIFEST em `app/javascript/dashboard/featureFlags.js`
  (`bin/sync-custom-module-hooks:122-137`); hoje só existe `SCOUT` (`featureFlags.js:59`).
- `custom/app/models/scout_tool.rb` e `custom/app/services/custom/scout/tools/call_custom_api.rb`:
  o v2 não consome nenhum dos dois (design decisão 4).
- Brief 12, decisão 6: os campos do v2 aparecem sempre, para serem preenchidos antes da promoção.
  Este brief a revê (decisão 10).
- `lib/integrations/llm_instrumentation.rb:10-64` e `llm_instrumentation_helpers.rb:54-74`:
  `metadata:` já vira atributo Langfuse. Os metadados de playbook entram por aí desde o Brief 03.

## 3. Precedente

O Captain V2 do upstream escolhe engine exatamente assim: pela flag **de conta**
`captain_integration_v2` (`config/features.yml:184-187`, lida em
`enterprise/app/jobs/captain/conversation/response_builder_job.rb:210-212`), e não por coluna no
assistant. Os classificadores pós-hoc rodam só no ramo V1. O que se reaproveita é o formato: uma
flag de conta decide a engine num único ponto de despacho, e o V1 continua vivo atrás dela.

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | A engine é escolhida pela **flag de conta `scout_v2`**, e cada conta roda **uma** engine: com a flag, v2 em playground e inbox; sem ela, v1 | A coluna `engine` por scout foi descartada pelas três lacunas do §1 (design §4.11). A granularidade passa a ser a conta: contas com vários scouts promovem todos juntos, o que é aceitável porque o v2 existe para substituir o v1, não para conviver com ele |
| 2 | **Só o Super Admin promove.** O administrador da conta não escolhe engine, e nenhuma tela do dashboard ganha seletor | A promoção desliga integrações (`ScoutTool`) e exige o preflight (decisão 3): é ato do operador. O checkbox do Super Admin já existe para qualquer flag de `features.yml`, sem código novo de UI. A tela mudar de campos com a flag (decisão 9) mostra configuração, não oferece escolha |
| 3 | **Preflight executável por conta antes de marcar a flag**, que chama o v2 direto, sem passar pelos pontos de despacho | O playground da conta segue a flag, então não roda v2 antes da promoção (design §4.11). A alternativa considerada era marcar a flag, testar no playground e desmarcar se falhar. Foi rejeitada porque, nessa janela, conversas reais de clientes já passariam pelo v2 sem verificação |
| 4 | **Modelo, provider e API key continuam em `ScoutAccountConfig`**, sem campo por engine | Com uma engine por conta não há conflito de configuração (design decisão 13). Se o modelo da conta falhar no tool calling do v2 (visível no Langfuse), o primeiro remédio é trocar o modelo da conta |
| 5 | Numa conta com `scout_v2`, as `ScoutTool` **não são oferecidas ao modelo** | Design decisão 4. A configuração continua salva |
| 6 | **A depreciação é esconder, não apagar.** Nenhuma coluna, dado, rota de API, serviço do v1, branch de despacho ou entrada de `features.yml` é removido nesta fase | Decisão do usuário em 2026-10-01. Tudo continua reversível pela flag, por conta e sem deploy. A remoção de código do v1 fica para quando houver decisão explícita (§6) |
| 7 | `activation_reason` legível em toda conversa é **critério de conclusão da fase**, não observabilidade opcional | É a contrapartida em produção do roteamento híbrido: mede a inversão assumida de `fora_de_prospeccao` e alimenta o item 6.7 (design §4.4, §4.9 e §8) |
| 8 | A promoção **não reintroduz nenhuma auditoria** | A verificação estrutural substitui a estocástica. Uma reintrodução só acontece de forma cirúrgica, com classe de erro observada, e avalia antes a rede fora do turno no formato do `InboxPendingConversationsResolutionJob` do Captain (design §4.10 e §6.7) |
| 9 | **A tela do scout segue a engine da conta, nos dois sentidos.** Com `scout_v2`: some o que só o v1 lê — persona (configuração, modal de criação, subtítulo do card, que passa a mostrar `role`), página de Tools (entrada no menu e rota) e aba Produtos. Sem `scout_v2`: some o que só o v2 lê — papel, escopo, tom, tamanho de resposta e saudação. O que os dois leem aparece sempre | Marcar e desmarcar a flag troca a tela junto com a engine. Esconder é só apresentação: os dados continuam no banco, a API continua aceitando e devolvendo todos os campos, e salvar a tela não apaga o que está escondido |
| 10 | Revê o brief 12, decisão 6 (campos do v2 sempre visíveis). Antes da promoção, `role`/`scope` são preenchidos pelo operador pela API (que aceita os campos com qualquer valor da flag) ou logo depois de marcar a flag; o preflight lista os scouts com `role`/`scope` vazios e imprime a `persona` para a reescrita | Custo aceito da decisão 9: o administrador da conta não vê os campos do v2 antes da promoção. Com `role`/`scope` vazios, o v2 usa a moldura fixa de `Identity` (brief 12, decisão 2), não quebra |
| 11 | A constante `SCOUT_V2` entra em `featureFlags.js` com entrada de MANIFEST; a visibilidade é decidida no frontend pela flag da conta, sem endpoint novo | Mesmo mecanismo das demais flags de conta no dashboard |
| 12 | **Produtos no v2: a aba some e o conteúdo vai para Conhecimento** como fonte `kind: faq` (design §4.7), levado pelo operador ou pelo administrador antes da promoção; o preflight imprime o `product_catalog` de cada scout para isso. O v2 não passa a ler `product_catalog` | Decisão do usuário em 2026-10-01 (opção (a)). O v2 não lê o catálogo; sem esse passo, preços e ofertas deixariam de chegar ao modelo numa conta promovida. Fazer o v2 ler o formato do v1 perpetuaria um formato que o usuário não quer manter (§6) |

## 5. Escopo preliminar

- Preflight por conta (rake task, ex.: `scout_v2:preflight[account_id]`), executado pelo operador no
  container `rails` (`docker compose exec rails bundle exec rake …` no dev; o equivalente no
  container de produção). A saída é o **stdout do terminal** de quem roda a task: nada é gravado em
  arquivo, banco, log de aplicação ou tela do dashboard. Conteúdo:
  - `ScoutTool` ativas da conta que deixam de ser oferecidas;
  - por playbook, as capabilities de `requires` insatisfeitas para a conta, via `CapabilityRegistry`
    (Brief 07);
  - para cada scout ativo da conta, sonda de `exit_handoff` sem playbook ativa: um pedido explícito
    de atendente executado no v2 em modo playground, sem enviar mensagem a contato e sem gravar
    estado de conversa real;
  - scouts ativos com `role`/`scope` vazios, com a `persona` atual impressa para a reescrita
    (Brief 12);
  - o `product_catalog` de cada scout que tem catálogo, para ser levado ao Conhecimento como fonte
    `kind: faq` (decisão 12). Scout com catálogo vazio (`{}` ou `[]`, default da coluna,
    `db/schema.rb:1394`) não gera linha nenhuma; conta sem nenhum catálogo não gera a seção
    (nem título, nem "nenhum catálogo").
- Tela condicionada à flag (decisões 9–11): `ScoutGeneralSettings.vue` (persona × campos do v2),
  `ScoutList.vue` (modal de criação e subtítulo do card), `Sidebar.vue` e `scout.routes.js`
  (página de Tools), `ScoutDetail.vue` (aba Produtos); constante `SCOUT_V2` em
  `featureFlags.js` + MANIFEST; textos de ajuda de `role`/`scope` sem "para a nova versão do Scout",
  que deixa de fazer sentido numa tela que só os mostra no v2 (`scout.json`, `en` e `pt_BR`).
- Payload de salvamento da tela: só os campos visíveis; o controller atualiza só o que recebe, então
  o escondido não é sobrescrito.

## 6. Fora de escopo

- Declarar a flag `scout_v2` e o despacho nos dois pontos: já feito no Brief 03.
- Coluna `engine` por scout e seletor de engine no dashboard: descartados (decisões 1 e 2).
- Configuração de modelo por engine (decisão 4).
- **Remoção de código e dados do v1** (serviços de comportamento, tools mortas, `persona`,
  `product_catalog`, `ScoutTool`, branches de despacho, `deprecated: true` na flag): decisão do
  usuário em 2026-10-01 de não apagar nada por ora (decisão 6). Volta como brief próprio quando
  houver decisão explícita.
- `ScoutTool` como provider de capability (design §6.1). O gatilho é o primeiro cliente sem adapter
  para a capability de que precisa, e isso não é pré-requisito da promoção.
- Materialização das playbooks em banco e UI de enable/disable por conta (design §6.3).
- Rede de auditoria fora do turno (design §6.7): avaliada com evidência de produção, depois desta
  fase.
- Janela de histórico de conversa (`agent_runner.rb:165-167` carrega todas as mensagens
  não-privadas sem limite). É pré-existente e ortogonal; vira spec própria se aparecer no Langfuse
  estourando orçamento (design §8).
- Mudar o default de `scout_v2` para `enabled: true`. Enquanto houver contas no v1, uma conta nova
  recebe o v2 só se o operador marcar a flag.
- **Novo tratamento de produtos e ofertas.** Nem o formato do v1 (`product_catalog` em JSON,
  despejado inteiro no prompt, `agent_runner.rb:158`) nem FAQ em Conhecimento são o desenho
  desejado; a decisão 12 é a ponte para a promoção. Vira brief próprio, que define formato, tela e
  como o v2 consulta o catálogo.

## 7. Critérios de aceite (rascunho)

### US1 — Promoção por conta, só pelo Super Admin, com rollback imediato

- Marcar `scout_v2` na tela da conta no Super Admin faz as próximas mensagens de todos os scouts da
  conta passarem pelo `TurnRunner`, e o playground da conta também passa a rodar v2.
- Desmarcar a flag devolve a conta ao v1 sem deploy e sem perda de dados de conversa. O estado v2
  gravado (`ichatr_scout_conversation_states`) permanece e é ignorado pelo v1.
- Nenhuma tela acessível ao administrador da conta permite trocar a engine.
- O v2 responde com o provider, o modelo e a API key configurados em Scout → Configurações, os
  mesmos que o v1 usava na conta.

### US2 — Preflight antes de promover

- Para uma conta ainda sem a flag, o operador obtém do preflight:
  - quais `ScoutTool` ativas deixarão de ser oferecidas;
  - quais capabilities exigidas pelas playbooks estão insatisfeitas;
  - para cada scout ativo, se um pedido explícito de atendente **sem playbook ativa** resulta em
    `exit_handoff`;
  - quais scouts ativos estão com `role`/`scope` vazios, e a `persona` de cada um;
  - o catálogo de produtos de cada scout que tem catálogo; sem catálogo em nenhum scout da conta, a
    saída não tem seção nem menção a catálogo.
- O preflight não envia mensagem a nenhum contato e não altera nenhuma conversa real.
- Numa conta com `scout_v2`, nenhuma `ScoutTool` é oferecida ao modelo.

### US3 — Toda conversa em produção explica a si mesma

- Para qualquer conversa de uma conta em v2 é possível ler qual playbook esteve ativa, por que ativou
  (`state` | `trigger` | `transition`), qual foi o desfecho e que pendências existiam.
- Conversa transferida depois de uma transição no mesmo turno (`qualificacao` → `agendamento` →
  `exit_handoff`) mostra as pendências de `agendamento`, nomeadas como dela, mesmo com a ativa
  zerada pelo exit (design §4.9).
- Os mesmos campos estão no trace do Langfuse (`playbook`, `activation_reason`, `exit_action`,
  `unsatisfied_flags`), sem o laço de reparo e sem as 3–8 gerações aninhadas do v1.
- A taxa de ativação de `fora_de_prospeccao` por trigger é mensurável: é o instrumento da inversão
  assumida no design §4.4.

### US4 — A tela do scout segue a engine, e nada se perde ao alternar

- Com `scout_v2`: configuração sem "Persona e Prompt do Sistema"; modal de criação sem persona; card
  da lista com `role`; menu sem a página de Tools e a rota inacessível pela navegação; sem a aba
  Produtos; papel, escopo, tom, tamanho e saudação visíveis.
- Sem `scout_v2`: persona, Tools e Produtos visíveis como hoje; papel, escopo, tom, tamanho e saudação
  escondidos.
- Funil, Conhecimento, Público, Caixas, debounce e cota visíveis nas duas engines.
- Ida e volta: persona, tools e catálogo gravados no v1 continuam intactos depois de marcar e
  desmarcar a flag; `role`, `scope` e estilo gravados no v2 continuam intactos depois de desmarcar e
  marcar de novo. Salvar a tela numa engine não altera os campos da outra.

## 8. Testes (rascunho)

- Spec do preflight: relatório com `ScoutTool` ativas, capabilities insatisfeitas por playbook e
  resultado da sonda de `exit_handoff`, com cliente LLM dublado. Também verifica que nenhuma
  mensagem é criada e nenhum estado de conversa real é gravado. Catálogo: conta com um scout com
  catálogo e outro vazio imprime só o primeiro; conta sem catálogo não imprime nada sobre catálogo.
- Specs de componente de `ScoutGeneralSettings.vue` e `ScoutList.vue`: campos de cada engine
  visíveis só com a flag correspondente; payload de salvamento sem os campos escondidos.
- Spec de request de `scouts_controller`: atualizar só os campos de uma engine preserva os da outra.
- Spec do menu do Scout (`Sidebar.vue` ou o helper que monta os itens): Tools ausente com
  `scout_v2`, presente sem.
- Verificação operacional antes da primeira promoção real: preflight da conta candidata, marcação
  no Super Admin, tela conferida nos dois estados da flag, primeira conversa conferida no Langfuse
  (`activation_reason` presente).
- Suíte completa (`bundle exec rspec`, `pnpm test`, `pnpm eslint`, `bundle exec rubocop`) e
  `bin/sync-custom-module-hooks --check`/`--audit` com a nova entrada de MANIFEST de `SCOUT_V2`.

---

> **Nota de proveniência**: substitui `10-producao-engine-v2.md`. A seleção por coluna `engine` por
> scout foi trocada pela flag de conta `scout_v2` depois da revisão de 2026-09-24, que confrontou o
> design com o mecanismo de ativação do v1 (`config/features.yml:276-279` + checkbox do Super Admin)
> e com a configuração de modelo por conta (`ichatr_scout_account_configs`). A decisão está
> registrada no design (decisões 5 e 13, §4.11, §6 Fase 5 e §8). Em 2026-10-01 o usuário trocou a
> depreciação por remoção de código pela depreciação reversível (esconder por flag, nos dois
> sentidos) e trouxe para cá a limpeza da tela, levantada no brief 14; leitores de cada campo
> conferidos por busca em `custom/app/services/custom/scout_v2/` e `custom/app/services/custom/scout/`.
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
