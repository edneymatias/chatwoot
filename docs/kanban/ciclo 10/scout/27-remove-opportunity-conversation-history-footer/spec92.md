# Fase 27 — Remover Lista Duplicada de Conversas no Rodapé do Modal de Oportunidade

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depende de**: Fase (ciclo 11) `15-unified-card-click-and-history-links` (`specs/043-card-click-history-links`) —
é o que torna a lista do rodapé redundante, ao tornar clicável o histórico já existente na Activity
tab do drawer.

---

## Objetivo

Remover a seção "Conversas Associadas" do rodapé do `OpportunityBackfillModal.vue` (modal de edição
de Oportunidade). É uma lista simples e duplicada: o mesmo histórico de conversas de uma Oportunidade
já existe, de forma mais completa e navegável, na aba "Activity" do `OpportunityConversationDrawer.vue`
(`OpportunityActivityLog.vue`), entregue pela fase `15-unified-card-click-and-history-links`
(ciclo 11). Manter os dois é manutenção duplicada de UI para o mesmo propósito, com a versão do
modal sendo estritamente inferior.

## Contexto de investigação (por que este desenho)

- **Origem da lista removida**: `specs/039-multi-conversation-opportunities` (T014) adicionou a seção
  "Conversation History" em `OpportunityBackfillModal.vue`, renderizando
  `opportunity.associated_conversations` (serializado por
  `Opportunity#associated_conversations_json`, em
  `custom/app/models/custom/concerns/opportunity_conversation_management.rb`). Mostra só as
  conversas **atualmente** ligadas à Oportunidade, com tags de "Ativa"/"Origem" e status
  Aberta/Resolvida, sem histórico de transferência ou desvinculação.
- **Substituto já existe e é superior**: `OpportunityConversationDrawer.vue` (aberto ao clicar num
  link de conversa a partir do Kanban, `opportunities_conversation` route) tem uma aba "Activity"
  (`activeTab === 'activity'`, alternável via botão dedicado) que renderiza
  `OpportunityActivityLog.vue`, alimentada por `OpportunityActivity` — que registra
  `conversation_linked`/`conversation_detached` (`custom/app/models/opportunity_conversation.rb`,
  `after_create`/`after_destroy`) com `conversation_display_id`, `is_origin`,
  `transferred_from_opportunity_id`/`transferred_from_opportunity_title`. Cada entrada de conversa é
  clicável (`@select-conversation="onSelectConversation"`), recurso entregue especificamente pela
  fase `15-unified-card-click-and-history-links` (`specs/043-card-click-history-links`, ciclo 11)
  para tornar esse log navegável. Isso cobre tudo que a lista do rodapé mostra, mais transferências e
  desvinculações — que a lista do rodapé nunca mostrou.
- **O dado (`associated_conversations`) não é exclusivo dessa UI removida** — continua sendo
  necessário:
  - `store/modules/opportunities/getters.js#opportunityByConversationId` varre
    `associated_conversations` para resolver "qual Oportunidade pertence à conversa X", getter
    consumido pelo próprio `OpportunityConversationDrawer.vue#currentOpportunity` (linhas 42-53) —
    ou seja, é o mecanismo que decide qual Oportunidade abrir no drawer. Remover o campo do backend
    quebraria o próprio substituto que motiva esta remoção.
  - `specs/043-card-click-history-links` (research.md) registra explicitamente que
    `associated_conversations_json` "já tem tudo que seria necessário se isso for desejado depois" —
    reserva de uso futuro, não código morto.
- **Sem teste dedicado a `OpportunityBackfillModal.vue`** — busca em
  `app/javascript/dashboard/components-next/Opportunities/specs/` não encontrou nenhum spec para
  esse componente; nenhum teste quebra com a remoção.
- **i18n exclusivo confirmado por busca**: as chaves
  `OPPORTUNITIES.BACKFILL_MODAL.{CONVERSATIONS_HISTORY_LABEL,NO_CONVERSATIONS,ACTIVE_CONVERSATION_TAG,ORIGIN_CONVERSATION_TAG,RESOLVED_STATUS}`
  só aparecem em `OpportunityBackfillModal.vue`, tanto em `en/opportunities.json` quanto em
  `pt_BR/opportunities.json` (o `NO_CONVERSATIONS` de `report.json`, em outro namespace, é
  coincidência de nome, não a mesma chave).
- **Código órfão confirmado por leitura completa do arquivo**: `associatedConversations` (computed),
  `openConversation`, `getInbox`, `getInboxIcon`, `inboxes` (computed) e `formatTime` só são usados
  dentro do bloco de template removido — nenhuma outra parte de `OpportunityBackfillModal.vue` os
  referencia.

## Decisões de desenho

1. **Remoção é só de UI e código-morto do frontend, nunca do dado/model.** `associated_conversations`
   continua sendo servido por `Opportunity#as_json` — outro consumidor real
   (`opportunityByConversationId`, usado pelo próprio drawer substituto) depende dele.
2. **Nenhuma migração, mudança de contrato de API, nem alteração em
   `OpportunityActivityLog.vue`/`OpportunityConversationDrawer.vue`** — o substituto já funciona
   como está; esta fase só remove a duplicata, não reforça o substituto.
3. **Fase adicionada ao roadmap mestre** (`spec60.md` §11), seguindo o precedente da Fase 24
   (anotada como não exclusiva do Scout).

## Escopo

### 1. `app/javascript/dashboard/components-next/Opportunities/OpportunityBackfillModal.vue`

- Remover o bloco de template "Associated Conversations History" (comentário `<!-- Associated
  Conversations History -->` até o fechamento da `<div>` correspondente).
- Remover do `<script setup>`, por serem exclusivos desse bloco: computed `associatedConversations`;
  função `openConversation`; função `getInbox`; função `getInboxIcon`; computed `inboxes`; função
  `formatTime`.
- Remover o import `dynamicTime` de `shared/helpers/timeHelper` (usado só por `formatTime`) se ficar
  sem nenhum outro uso no arquivo.
- Import `Icon` de `dashboard/components-next/icon/Icon.vue` **permanece** — usado pelos ícones de
  chevron dos `<select>` no restante do modal.

### 2. i18n

Remover as 5 chaves abaixo, sob `OPPORTUNITIES.BACKFILL_MODAL`, em:
- `app/javascript/dashboard/i18n/locale/en/opportunities.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json`

```
CONVERSATIONS_HISTORY_LABEL
NO_CONVERSATIONS
ACTIVE_CONVERSATION_TAG
ORIGIN_CONVERSATION_TAG
RESOLVED_STATUS
```

### 3. Documentação

Adicionar entrada "Fase 27" em `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap de
Implementação), no mesmo padrão das fases anteriores.

## Fora de escopo

- Qualquer mudança em `Opportunity#as_json` / `associated_conversations_json`
  (`custom/app/models/custom/concerns/opportunity_conversation_management.rb`).
- Qualquer mudança no model `OpportunityConversation` ou na tabela
  `ichatr_opportunity_conversations`.
- Qualquer mudança em `OpportunityActivityLog.vue` ou `OpportunityConversationDrawer.vue` — o
  substituto já cobre o caso de uso, não precisa de reforço aqui.
- `opportunityByConversationId` (getter) e qualquer código que dependa de `associated_conversations`
  — continuam intocados.
- Qualquer alteração de rota (`opportunities_conversation`) ou do fluxo de clique em conversa a
  partir do Kanban/card — inalterado.

## Testes

- Nenhum teste dedicado existe hoje para `OpportunityBackfillModal.vue` (confirmado por busca) —
  nenhum teste automatizado quebra com esta remoção.
- Smoke manual (a ser executado na implementação):
  1. Abrir o modal de edição de uma Oportunidade que tenha mais de uma conversa associada —
     confirmar que a seção "Conversas Associadas" não aparece mais, e que título, assignee, status,
     estágio, campos obrigatórios e valor do negócio continuam editáveis e salvando normalmente.
  2. Abrir o drawer da mesma Oportunidade (clique num card/link de conversa) e conferir que a aba
     "Activity" continua mostrando o histórico completo de conversas ligadas/desvinculadas, com os
     links clicáveis funcionando.

## Critérios de aceite

- A seção "Conversas Associadas" não aparece mais no rodapé do modal de edição de Oportunidade
  (`OpportunityBackfillModal.vue`).
- Nenhuma chave i18n órfã relacionada permanece em `en/opportunities.json` ou
  `pt_BR/opportunities.json`.
- `Opportunity#as_json` continua expondo `associated_conversations` sem alteração, e
  `opportunityByConversationId` continua resolvendo a Oportunidade corretamente a partir de uma
  conversa — nenhuma mudança de comportamento fora do modal.
- Nenhum outro componente ou teste quebra (confirmado nesta spec: nenhum outro consumidor do bloco
  removido existe).
