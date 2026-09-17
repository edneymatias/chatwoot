# Fase 30 — Visão Geral do Scout: Métricas-Resumo e Distribuição por Etapa do Funil (Preview)

**Status**: Preview — desenhado em sessão de brainstorming completa (contexto, perguntas de
esclarecimento, abordagens de arquitetura); especificação completa e implementação ficam para
`/speckit-specify` a critério do operador. Este arquivo contém a decomposição em Histórias de
Usuário já pronta para alimentar esse comando.
**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Fase 09 (`09-required-qualification-attributes/spec74.md`) — `qualified_stage_id`/
`unqualified_stage_id`. Fase 22 (`22-scout-follow-up-nudges-and-rescue-handoff/spec85.md`) —
`rescue_stage_id`, usado aqui como definição de "abandono". Fase 26
(`26-scout-opportunity-value-estimation/spec91.md`) — `interest_attribute_definition`/
`value_by_interest`, campo de interesse reaproveitado para o card de interesse por etapa.
**Sucede**: Fase 31 (`31-scout-overview-conversations-list/spec-preview.md`) depende do shell de
página (rota, seletores de Scout/período) desenhado aqui.

---

## Contexto

O Scout nunca "conclui" uma conversa — ele sempre transfere para um humano, seja com sucesso
(oportunidade chega ao `qualified_stage`, ex.: agendou), com desqualificação explícita
(`unqualified_stage`) ou por abandono/inatividade resgatada pelo `Custom::Scout::FollowUpJob`
(`rescue_stage`, Fase 22). Hoje não existe nenhuma tela agregando esse desempenho — o operador só
enxerga oportunidades individuais no Kanban, sem visão consolidada de quantos leads o Scout
qualificou, desqualificou ou deixou esfriar, nem por qual etapa do funil elas estão passando.

Esta fase adiciona um novo item de menu **"Visão Geral"**, primeiro filho de `Scout` no sidebar
(mesma posição/nome do padrão já usado pelo Captain), com cards de métrica-resumo e dois gráficos
de distribuição por etapa. A fase seguinte (31) adiciona, na mesma página, uma tabela de conversas
recentes — separada aqui só porque é uma fatia de valor independente (endpoint e componente
próprios), não porque a UI final vá ficar em páginas diferentes.

### Precedentes internos usados como referência de arquitetura/UI

- **Captain → Visão Geral** (`app/javascript/dashboard/routes/dashboard/captain/assistants/overview/Index.vue`,
  `enterprise/app/services/captain/assistant_stats_builder.rb`): mesmo padrão de shell de página
  (seletor de assistente + seletor de período, cards de métrica, serviço de agregação sob demanda
  sem tabelas novas). Reaproveitado para o shell e para os cards de métrica-resumo desta fase.
- **Campanhas WhatsApp → Analytics** (`app/javascript/dashboard/routes/dashboard/campaigns/pages/WhatsAppCampaignAnalyticsPage.vue`):
  padrão "métricas no topo, detalhe embaixo" citado pelo operador como referência direta — usado
  aqui para os cards-resumo e, na Fase 31, para a tabela com pills de filtro por status.
- **`@chatwoot/viz`** (pacote já usado por Captain/Campanhas): expõe `BarChart`, reaproveitado para
  os dois gráficos de distribuição por etapa desta fase (nenhuma lib de gráfico nova).

## Decisões de desenho (fechadas em brainstorming, 2026-09-16)

1. **Escopo por Scout, não agregado por conta**: cada Scout tem seu próprio funil configurado
   (`qualified_stage_id`/`unqualified_stage_id`/`rescue_stage_id` podem diferir entre Scouts da
   mesma conta), então agregar todos os Scouts misturaria estágios de funis diferentes. Um seletor
   de Scout aparece no topo da página **só se a conta tiver mais de 1 Scout cadastrado**.
2. **Três desfechos de funil, não dois**:
   - **Qualificado** = oportunidade atingiu `qualified_stage_id`.
   - **Desqualificado** = oportunidade atingiu `unqualified_stage_id`.
   - **Abandonado** = oportunidade atingiu `rescue_stage_id` (resgate por inatividade, Fase 22) —
     **não** é o mesmo que desqualificado; é estagnação/silêncio do lead, não uma decisão de
     desqualificação.
   - Uma oportunidade "atendida pelo Scout" sem nenhum desses três desfechos ainda está **em
     andamento** (conversa `pending` sem transição de estágio definitiva).
3. **"Oportunidade atendida pelo Scout"** = toda `Opportunity` cujo `origin_conversation` pertence
   a uma inbox com Scout habilitado (`inbox.scout_id == scout selecionado`), criada dentro do
   período selecionado.
4. **Distribuição por etapa é snapshot atual, não filtrado por período**: mostra em qual etapa do
   funil **completo da conta** (todas as `PipelineStage`, não só as 3-4 que o Scout usa
   diretamente) cada oportunidade atendida pelo Scout está **agora** — incluindo oportunidades que
   avançaram além da qualificação, já nas mãos do time humano (negociação, fechamento, etc.). O
   seletor de período do topo não filtra este gráfico (senão "estágio atual" e "período de
   qualificação" colidiriam — uma oportunidade qualificada há 2 meses mas ainda em negociação hoje
   precisa aparecer).
5. **Interesse por etapa é opcional e depende de configuração por Scout**: o campo de interesse
   (`scout.interest_attribute_definition`, mesmo campo já usado pela Fase 26 para estimativa de
   valor) é opcional — nem toda conta/Scout o configura. Quando ausente, o card correspondente
   **permanece visível** com estado de configuração (call-to-action "Configurar no Funil" →
   `scout_funnel` route), em vez de sumir da tela — ajuda a descoberta da funcionalidade em vez de
   escondê-la.
6. **"Mensagens por conversa"** conta o diálogo completo (mensagens do lead + respostas do Scout),
   não só as respostas da IA — mede o tamanho real da conversa, não o volume de trabalho do modelo.

## Histórias de Usuário (para `/speckit-specify`)

### História de Usuário 1 — Ver métricas-resumo de desempenho do Scout (Priority: P1)

Como operador/gestor comercial, ao entrar em Scout → Visão Geral, quero ver de imediato quantas
oportunidades o Scout atendeu no período selecionado e como elas se distribuem entre qualificadas,
desqualificadas e abandonadas, para avaliar o desempenho do agente sem precisar vasculhar o Kanban
oportunidade por oportunidade.

**Why this priority**: é o valor central da fase — sem os cards-resumo não há "visão geral"
nenhuma; as demais histórias são aprofundamento sobre esses mesmos números.

**Independent Test**: pode ser testada isoladamente populando oportunidades atendidas por um Scout
de teste com os três desfechos (qualificado/desqualificado/abandonado) e conferindo que os cards
mostram as contagens/taxas corretas para o período selecionado, incluindo o card de mensagens por
conversa.

**Acceptance Scenarios**:

1. **Given** um Scout com oportunidades atendidas no período selecionado com os três desfechos
   possíveis, **When** o operador abre Scout → Visão Geral, **Then** os cards mostram: total de
   oportunidades atendidas, taxa de qualificação, taxa de desqualificação, taxa de abandono e média
   de mensagens por conversa, todos recalculados para o período.
2. **Given** o operador troca o seletor de período (7 dias / 30 dias / este mês / mês passado),
   **When** a seleção muda, **Then** todos os cards-resumo são recalculados para a nova janela,
   sem recarregar a página inteira.
3. **Given** uma conta com mais de um Scout cadastrado, **When** o operador troca o seletor de
   Scout, **Then** todos os cards passam a refletir apenas o Scout selecionado, sem misturar dados
   de outro agente.
4. **Given** um Scout que ainda não tem `qualified_stage_id`/`unqualified_stage_id`/
   `rescue_stage_id` configurados (setup incompleto), **When** o operador abre a Visão Geral,
   **Then** os cards correspondentes mostram um estado neutro ("—"), sem erro nem divisão por
   zero.

---

### História de Usuário 2 — Ver onde as oportunidades atendidas estão no funil (Priority: P2)

Como operador, quero ver um gráfico mostrando em qual etapa do funil completo (não só as etapas
próprias do Scout) as oportunidades que o Scout já atendeu estão **hoje**, para entender quanto
avança além da qualificação inicial nas mãos do time humano.

**Why this priority**: aprofunda o resumo da História 1 com granularidade por etapa; depende do
mesmo endpoint/serviço de agregação, mas é uma segunda pergunta que o operador faz depois de olhar
os números totais — não bloqueia o valor central.

**Independent Test**: pode ser testada isoladamente criando oportunidades atendidas pelo Scout em
etapas variadas do funil (incluindo etapas além das 3-4 próprias do Scout, como uma etapa de
"Negociação" só usada por humanos) e conferindo que o gráfico reflete a contagem correta por etapa,
como snapshot atual — sem depender do período selecionado no topo.

**Acceptance Scenarios**:

1. **Given** oportunidades atendidas pelo Scout distribuídas em várias etapas do funil da conta
   (incluindo etapas posteriores à qualificação, geridas por humanos), **When** o operador visualiza
   o gráfico de distribuição, **Then** cada etapa mostra a contagem correta de oportunidades
   atendidas pelo Scout atualmente ali.
2. **Given** o operador troca o seletor de período no topo da página, **When** a seleção muda,
   **Then** o gráfico de distribuição por etapa permanece inalterado (é snapshot, não filtrado por
   período).

---

### História de Usuário 3 — Ver interesse por etapa do funil (Priority: P3)

Como operador com o campo de interesse configurado no Scout, quero ver como os diferentes
interesses (ex.: produtos/serviços) se distribuem pelas etapas do funil, para identificar quais
interesses avançam mais e quais estagnam.

**Why this priority**: é a métrica mais específica/opcional das três — só existe valor quando o
campo de interesse está configurado, e mesmo assim é um refinamento sobre a História 2, não um
bloqueador de MVP.

**Independent Test**: pode ser testada isoladamente configurando `interest_attribute_definition`
num Scout de teste, atribuindo interesses diferentes a oportunidades em etapas diferentes, e
conferindo a distribuição no gráfico; e separadamente testando um Scout sem o campo configurado
para confirmar o estado de call-to-action.

**Acceptance Scenarios**:

1. **Given** um Scout com `interest_attribute_definition` configurado e oportunidades atendidas com
   diferentes valores de interesse espalhadas por etapas distintas, **When** o operador visualiza o
   card de interesse por etapa, **Then** cada etapa mostra a repartição por interesse
   correspondente.
2. **Given** um Scout **sem** `interest_attribute_definition` configurado, **When** o operador
   visualiza a Visão Geral, **Then** o card de interesse permanece visível com uma mensagem
   explicativa e um botão que leva à configuração do campo na aba Funil do Scout (`scout_funnel`).

### Edge Cases

- Conta com um único Scout: seletor de Scout não aparece (evita dropdown com uma única opção
  inútil).
- Conta/Scout sem nenhuma oportunidade atendida no período: estado vazio reaproveitando
  `EmptyStateLayout` já usado nas demais telas do Scout, não uma tela em branco.
- Oportunidade atendida pelo Scout mas cujo `origin_conversation`/inbox foi posteriormente
  desvinculado do Scout (`ScoutInbox` removido): continua contando normalmente — a atribuição é
  fixada no momento da criação da oportunidade, não recalculada retroativamente.
- Scout desabilitado (`enabled: false`) mas com histórico de oportunidades: a Visão Geral continua
  acessível e mostrando dados históricos — desabilitar não é o mesmo que arquivar/deletar.

## Escopo preliminar (a confirmar na especificação completa)

- Rota nova `scout_overview_index` (`GET /accounts/:accountId/scout/overview` ou
  `/accounts/:accountId/scout/:scoutId/overview`, a definir no `/speckit-plan`), primeiro item do
  submenu `Scout` no sidebar.
- Novo shell de página (`components-next/Scout/PageLayout.vue` ou equivalente) com seletor de Scout
  (condicional) e seletor de período (`RangeSelector`, mesmo componente do Captain).
- Novo endpoint `GET /api/v1/accounts/:account_id/scouts/:id/overview?range=...` e serviço
  `Custom::Scout::AnalyticsService`, agregando sobre `Opportunity`/`OpportunityStageChange`
  existentes — sem novas tabelas, sem jobs de agregação.
- 5 cards de métrica-resumo (atendidas, taxa qualificado, taxa desqualificado, taxa abandonado,
  mensagens por conversa) reaproveitando o componente `MetricCard` do Captain.
- Gráfico de distribuição por etapa (`BarChart` de `@chatwoot/viz`, horizontal, uma barra por
  `PipelineStage` da conta).
- Card de interesse por etapa (`BarChart` empilhado) com estado de call-to-action quando não
  configurado.

## Fora de escopo

- Tabela de conversas recentes — Fase 31.
- Qualquer nova tabela de agregação/snapshot diário, cache Redis, ou job de cron — agregação é
  sempre sob demanda (decisão de arquitetura já validada com o operador; pode ser revisitada como
  otimização futura sem mudar a API/UI).
- Métricas agregadas entre múltiplos Scouts da mesma conta.
- Edição de configuração do funil (`qualified_stage_id` etc.) a partir desta tela — só leitura,
  edição continua na aba Funil já existente (`scout_funnel`).

## Testes (rascunho)

- Spec de request/serviço para `Custom::Scout::AnalyticsService`: contagens corretas por desfecho
  (qualificado/desqualificado/abandonado/em andamento), cálculo de taxas, agregação de mensagens
  por conversa (lead + Scout), distribuição por etapa como snapshot (não filtrado por período),
  distribuição de interesse presente/ausente conforme `interest_attribute_definition`.
- Spec de frontend cobrindo os cards com dados mockados, incluindo o estado "—" para Scout sem
  funil configurado e o call-to-action do card de interesse.

## Critérios de aceite (rascunho, só valem se a fase avançar)

- Um operador consegue, em Scout → Visão Geral, identificar quantas oportunidades o Scout atendeu,
  qualificou, desqualificou e abandonou num período escolhido, sem precisar abrir o Kanban.
- A distribuição por etapa reflete o estado atual do funil completo da conta, incluindo etapas
  geridas por humanos após a qualificação.
- O card de interesse por etapa nunca quebra ou some silenciosamente quando o Scout não tem o campo
  configurado — sempre orienta o operador a configurá-lo.
- Trocar Scout ou período nunca mistura dados de escopos diferentes nos cards.

---

> **Nota**: Preview criado a partir de sessão de brainstorming completa com o operador
> (2026-09-16), incluindo pesquisa de precedentes internos (Captain Overview, Campanhas WhatsApp
> Analytics) e de referência externa (Botpress Monitor → Conversations, citada pelo operador como
> inspiração para a Fase 31). Decisões de desenho acima já validadas; próxima entrega via
> `/speckit-specify`, mesmo fluxo das fases 23/26/29.
