# Fase 31 — Visão Geral do Scout: Lista de Conversas Recentes (Preview)

**Status**: Preview — desenhado em sessão de brainstorming completa (contexto, perguntas de
esclarecimento, abordagens de arquitetura); especificação completa e implementação ficam para
`/speckit-specify` a critério do operador. Este arquivo contém a decomposição em Histórias de
Usuário já pronta para alimentar esse comando.
**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Fase 30 (`30-scout-overview-metrics-and-funnel-distribution/spec-preview.md`) —
shell de página, seletores de Scout/período e definição dos 3 desfechos de funil
(qualificado/desqualificado/abandonado) reaproveitados aqui como taxonomia de status por conversa.

---

## Contexto

Durante o brainstorming da Fase 30, o operador trouxe dois precedentes concretos como inspiração
para uma seção adicional na mesma página de Visão Geral: a tela **Monitor → Conversations** do
Botpress (lista de conversas com duração, contagem de mensagens e status, com acesso ao histórico
completo) e a própria tela de **Analytics de Campanha WhatsApp** já existente neste fork
(`WhatsAppCampaignAnalyticsPage.vue` + `CampaignDeliveryTable.vue`), que já resolve exatamente o
padrão "métricas no topo, tabela detalhada com pills de filtro por status embaixo" dentro deste
mesmo código-base.

Esta fase adiciona essa tabela ao rodapé da página de Visão Geral do Scout (não uma tela/rota
separada — decisão do operador, para manter tudo numa única tela nesta primeira entrega), reaproveitando
componentes já existentes (`TabBar`, `BaseTable`/`BaseTableRow`/`BaseTableCell`, `PaginationFooter`)
em vez de construir um visualizador de chat do zero: o clique numa linha abre a conversa real do
Chatwoot em nova aba, mesmo padrão já usado pelo drilldown do Captain
(`ReportDrilldownCard.vue#openRecord`, via `conversationUrl`).

## Decisões de desenho (fechadas em brainstorming, 2026-09-16)

1. **Tabela embutida na Visão Geral**, não uma aba/rota separada — mantém a entrega em uma única
   tela nesta primeira fatia; pode virar uma tela dedicada no futuro se o volume/filtros exigirem
   mais espaço, sem quebrar a API do endpoint desta fase.
2. **Taxonomia de status = desfecho no funil, nunca "transferência"** — correção crítica feita pelo
   operador durante o brainstorming: o Scout **sempre** transfere para um humano ao final de
   qualquer atendimento, inclusive quando qualifica e agenda com sucesso. "Transferido" não é
   sinônimo de fracasso nem de categoria própria — o status exibido reflete o desfecho real no
   funil:
   - 🟢 **Qualificado** — oportunidade chegou ao `qualified_stage_id`.
   - 🔴 **Desqualificado** — oportunidade chegou ao `unqualified_stage_id`.
   - 🟠 **Abandonado** — oportunidade resgatada por inatividade (`rescue_stage_id`, Fase 22).
   - 🔵 **Em andamento** — Scout ainda atuando, conversa `pending`, sem desfecho definido.
   - ⚪ **Transferido sem oportunidade** — handoff ocorreu (ex.: pedido explícito do lead, dúvida
     fora do escopo comercial) mas nenhuma oportunidade chegou a ser criada/vinculada nesta
     conversa. Cor **neutra**, nunca vermelha/negativa — não é uma falha do Scout, é um desfecho
     legítimo (ex.: `handover_to_human` chamado por motivo não comercial).
3. **Duração** = intervalo entre a primeira e a última mensagem trocada na conversa (não é latência
   de resposta do modelo).
4. **Mensagens** = mesma contagem da Fase 30 (diálogo completo: lead + Scout).
5. **Filtro por período compartilhado** com o resto da página (seletor de período do topo, Fase 30)
   — a tabela não tem seletor de data próprio, evitando dois controles competindo na mesma tela.
   Filtro por status é local à tabela (pills), independente do período.
6. **Paginação por página** (`PaginationFooter`, 25 por página), não "carregar mais" — segue o
   padrão já estabelecido em `WhatsAppCampaignAnalyticsPage.vue`, citado como referência direta pelo
   operador, e não o padrão de gaveta lateral (`AssistantDrilldownDrawer`) do Captain, mais adequado
   a drilldown pontual por métrica do que a uma seção permanente da página.
7. **Clique na linha abre a conversa real do Chatwoot em nova aba** — reaproveita
   `conversationUrl`/`frontendURL`, mesmo padrão do `ReportDrilldownCard.vue`. Sem reconstrução de
   visualizador de histórico de chat próprio.

## Histórias de Usuário (para `/speckit-specify`)

### História de Usuário 1 — Ver lista de conversas recentes do Scout com status (Priority: P1)

Como operador/gestor comercial, quero ver, no rodapé da Visão Geral, uma lista paginada das
conversas recentes atendidas pelo Scout selecionado, com contato, duração, número de mensagens e
status (qualificado/desqualificado/abandonado/em andamento/transferido sem oportunidade), filtrável
por status, para auditar rapidamente o comportamento do agente conversa a conversa sem precisar
abrir o Kanban ou a caixa de entrada.

**Why this priority**: é o valor central desta fase — sem a lista em si, não há nada a filtrar nem
a abrir; é o equivalente direto ao exemplo do Botpress que motivou a fase.

**Independent Test**: pode ser testada isoladamente populando conversas atendidas pelo Scout com os
cinco status possíveis e conferindo que a tabela lista corretamente contato, duração, contagem de
mensagens e status de cada uma, respeitando o filtro de status (pills) e o período selecionado no
topo da página.

**Acceptance Scenarios**:

1. **Given** um Scout com conversas atendidas cobrindo os cinco status possíveis dentro do período
   selecionado, **When** o operador visualiza a seção "Conversas recentes", **Then** a tabela lista
   cada conversa com contato, horário de início, duração, contagem de mensagens (lead + Scout) e
   badge de status correspondente.
2. **Given** a tabela populada, **When** o operador seleciona uma pill de status (ex.: "Abandonado"),
   **Then** a tabela mostra apenas conversas com aquele desfecho, mantendo a contagem visível na
   própria pill.
3. **Given** mais de 25 conversas no período, **When** o operador navega para a próxima página via
   `PaginationFooter`, **Then** a tabela carrega a próxima página de resultados sem recarregar a
   página inteira.
4. **Given** o operador troca o seletor de período no topo da página, **When** a seleção muda,
   **Then** a lista de conversas é recarregada para refletir o novo período, mesmo comportamento
   dos cards-resumo da Fase 30.
5. **Given** uma conversa transferida pelo Scout sem nenhuma oportunidade vinculada (ex.: pergunta
   fora do escopo comercial), **When** o operador visualiza a tabela, **Then** essa conversa aparece
   com o status "Transferido sem oportunidade" em cor neutra, nunca como "Desqualificado".

---

### História de Usuário 2 — Abrir o histórico completo de uma conversa a partir da lista (Priority: P2)

Como operador, ao encontrar uma conversa de interesse na lista (ex.: um abandono inesperado), quero
clicar nela e ver o histórico completo de mensagens trocadas, para entender exatamente o que
aconteceu e decidir se precisa de ação.

**Why this priority**: é o complemento natural da História 1 (auditoria só é útil se dá para
investigar o caso específico), mas depende da lista já existir — por isso P2, não P1.

**Independent Test**: pode ser testada isoladamente clicando numa linha da tabela populada e
confirmando que a conversa real correspondente abre em nova aba no Chatwoot, com o histórico
completo de mensagens (não uma cópia/reconstrução do histórico).

**Acceptance Scenarios**:

1. **Given** uma linha da tabela de conversas recentes, **When** o operador clica nela, **Then** a
   conversa real correspondente abre em nova aba do Chatwoot (rota nativa de conversa), mostrando o
   histórico completo de mensagens trocadas.
2. **Given** uma conversa cujo `origin_conversation` foi deletado/inacessível (caso raro), **When**
   o operador clica na linha, **Then** o sistema não quebra — mostra um estado de erro/indisponível
   em vez de uma navegação para página inexistente.

### Edge Cases

- Conversa "em andamento" cujo desfecho muda (ex.: qualifica) enquanto a tabela está aberta: não
  precisa de atualização em tempo real nesta fase (paginação estática, mesmo padrão da tabela de
  campanhas) — o operador atualiza a página/reaplica o filtro para ver o estado mais recente.
- Zero conversas no período/filtro selecionado: estado vazio da tabela (mensagem + sem quebra de
  layout), não uma tabela em branco sem explicação.
- Conversa com uma única mensagem (ex.: lead escreveu e nunca mais respondeu, sem nenhuma resposta
  do Scout): duração aparece como "—" ou "0min" (a definir na especificação completa), nunca erro.

## Escopo preliminar (a confirmar na especificação completa)

- Novo endpoint paginado `GET /api/v1/accounts/:account_id/scouts/:id/conversations?range=...&status=...&page=...`.
- Novo serviço `Custom::Scout::ConversationsQuery`, operando sobre `Opportunity`/
  `OpportunityConversation`/`Conversation`/`Message` existentes — sem novas tabelas.
- Nova seção de UI na página de Visão Geral (Fase 30): pills de filtro por status (`TabBar`),
  tabela (`BaseTable`/`BaseTableRow`/`BaseTableCell`), badge de status por linha (componente novo,
  mesmo padrão visual de `DeliveryStatusBadge.vue`), paginação (`PaginationFooter`).
- Navegação da linha para a conversa real via `conversationUrl`/`frontendURL` (nova aba).

## Fora de escopo

- Qualquer reconstrução de visualizador de histórico de chat dentro do Chatwoot — sempre abre a
  conversa nativa existente.
- Tela/rota dedicada só para conversas (fora da Visão Geral) — decisão explícita do operador nesta
  fase; pode ser revisitada depois sem quebrar o endpoint.
- Atualização em tempo real da tabela (ActionCable) — paginação estática nesta primeira entrega,
  mesmo padrão da tabela de campanhas já existente.
- Ordenação customizável por coluna — ordenação fixa (mais recente primeiro) nesta primeira fatia.

## Testes (rascunho)

- Spec de request/serviço para `Custom::Scout::ConversationsQuery`: classificação correta nos 5
  status (incluindo "transferido sem oportunidade" para handoffs sem `Opportunity` vinculada),
  cálculo de duração (primeira → última mensagem), contagem de mensagens, filtro por status,
  paginação, filtro por período.
- Spec de frontend cobrindo a tabela com dados mockados: renderização de badges por status, pills
  de filtro, navegação de página, e o clique na linha abrindo a URL de conversa esperada (sem
  navegar de fato em teste, apenas verificando a URL construída).

## Critérios de aceite (rascunho, só valem se a fase avançar)

- Um operador consegue, na própria Visão Geral, listar e filtrar por status as conversas recentes
  do Scout selecionado, sem sair da tela.
- Nenhuma conversa qualificada com sucesso (que envolveu transferência) aparece rotulada como
  "transferido sem oportunidade" ou em cor negativa — a distinção entre desfecho e mecanismo de
  transferência é preservada em toda a UI.
- Clicar numa conversa sempre leva ao histórico real e completo, nunca a uma reconstrução parcial.

---

> **Nota**: Preview criado a partir de sessão de brainstorming completa com o operador
> (2026-09-16), incluindo correção explícita do operador sobre a semântica de "transferência" vs.
> "desqualificação" (ver Decisão de desenho #2) — ponto crítico para não rotular erroneamente
> atendimentos bem-sucedidos. Próxima entrega via `/speckit-specify`, mesmo fluxo das fases
> 23/26/29.
