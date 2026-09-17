# Fase 28 — Remover Switch "Total Display" da Coluna do Kanban, Sempre Mostrar Contagem + Valor

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depende de**: nenhuma outra fase — cutover isolado num campo de configuração e num computed de
exibição já existentes.

---

## Objetivo

Remover o switch "Total Display" da configuração de Estágio do Funil (`total_display_mode`:
`value_sum` vs `count`), que hoje faz o cabeçalho de cada coluna do Kanban mostrar **ou** a soma do
valor das Oportunidades **ou** a contagem de cards — nunca as duas juntas. Passa a mostrar sempre as
duas informações combinadas, formato `"{contagem} • {valor formatado}"` (ex.: `"15 • R$ 15,5 mil"`),
eliminando a necessidade de configurar/alternar entre as duas.

## Contexto de investigação (por que este desenho)

- **Onde vive o switch hoje**: campo `total_display_mode` (`enum value_sum: 0, count: 1`,
  `custom/app/models/pipeline_stage.rb:9`), configurado por dois radio buttons em
  `EditPipelineStage.vue` (linhas 151-185, tela de configuração de Estágio do Funil), permitido em
  `custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb:89`, e consumido só num
  lugar: `KanbanColumn.vue`'s computed `displayTotal` (linhas 113-126), que decide entre
  `props.stage.count` (modo `count`) ou `formatCurrencyAmount(props.stage.value_sum, currencyCode,
  true)` (modo `value_sum`, o default).
- **A aplicação de moeda (R$/$) já funciona corretamente e não precisa de nenhuma mudança** —
  `KanbanColumn.vue` já resolve `currencyCode` via `store.getters['pipelineCurrencySetting/getCurrency']`
  (configuração de moeda do Kanban, tela `CardFieldConfig.vue`) e formata com `formatCurrencyAmount`
  (`dashboard/constants/pipelineCurrency.js`, já com `Intl.NumberFormat` por moeda: `USD`→`$`,
  `BRL`→`R$`). O mesmo padrão já é usado de forma consistente em `useOpportunityCardFields.js`,
  `OpportunityListView.vue`, `OpportunitiesViewBar.vue` e nos relatórios de Oportunidade — nenhum
  ponto do Kanban usa símbolo de moeda hardcoded. Combinar contagem + valor no mesmo texto reaproveita
  exatamente a mesma chamada `formatCurrencyAmount` já existente, sem nenhum ajuste de moeda
  necessário.
- **Nenhum teste backend cobre `total_display_mode`** (busca em `custom/spec` não encontrou nenhuma
  referência) — nenhum teste Ruby quebra com a remoção do enum/coluna.
- **Único teste frontend afetado**: `EditPipelineStage.spec.js` tem `total_display_mode: 'value_sum'`
  no fixture mockado da Oportunidade/Estágio (linha 18) — precisa só remover o campo do mock, sem
  nenhuma asserção dedicada ao switch.
- **i18n exclusivo confirmado por busca**: `PIPELINE_STAGES_MGMT.FORM.{DISPLAY_MODE_LABEL,
  DISPLAY_MODE_VALUE, DISPLAY_MODE_COUNT}` só aparecem em `EditPipelineStage.vue`, tanto em
  `en/opportunities.json` (linhas 210-212) quanto em `pt_BR/opportunities.json` (linhas 209-211).

## Decisões de desenho

1. **Cutover completo, sem coluna morta** — segue a convenção do projeto (sem shims/flags
   depreciados): remove o enum do model, o parâmetro permitido no controller, e a própria coluna
   `total_display_mode` via migration, além do switch na UI. Não faz sentido manter o dado
   configurável server-side se a UI nunca mais lê/escreve nada diferente do default.
2. **Formato do texto combinado**: `` `${count} • ${formatCurrencyAmount(value_sum, currencyCode,
   true)}` `` — contagem sempre primeiro (é o número mais rápido de ler visualmente), separador
   `•` (já usado em outros lugares do design system pra combinar dois metadados curtos), valor em
   modo compacto (`compact: true`, já o comportamento atual do modo `value_sum`).
3. **Nenhuma mudança na agregação de dados** — `stage.count`/`stage.value_sum` já chegam prontos do
   backend (endpoint de aggregates por estágio); esta fase só muda como o par já disponível é
   renderizado.

## Escopo

### 1. `app/javascript/dashboard/components-next/Opportunities/KanbanColumn.vue`

Reescrever o computed `displayTotal` (linhas 113-126) para, quando `count`/`value_sum` estiverem
definidos, retornar sempre a string combinada — remove o `if (total_display_mode === 'count')` e o
`return` isolado de contagem; mantém o guard de retornar `null` quando `count`/`value_sum` ainda não
chegaram (evita "0 • R$ 0" piscando antes do primeiro fetch de aggregates).

### 2. `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/EditPipelineStage.vue`

- Remove o ref `totalDisplayMode` (linha 26).
- Remove a atribuição `totalDisplayMode.value = currentStage.total_display_mode || 'value_sum'` no
  `onMounted` (linha 45).
- Remove `total_display_mode: totalDisplayMode.value` do payload de `submit()` (linha 66).
- Remove o bloco de template inteiro do switch (linhas 151-185: label "Lane Total Display"/"Column
  Total Display" + os dois radio buttons `value_sum`/`count`).

### 3. i18n

Remove as 3 chaves abaixo, sob `PIPELINE_STAGES_MGMT.FORM`, em:
- `app/javascript/dashboard/i18n/locale/en/opportunities.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/opportunities.json`

```
DISPLAY_MODE_LABEL
DISPLAY_MODE_VALUE
DISPLAY_MODE_COUNT
```

### 4. Backend

- `custom/app/models/pipeline_stage.rb`: remove `enum total_display_mode: { value_sum: 0, count: 1
  }, _prefix: true`.
- `custom/app/controllers/api/v1/accounts/pipeline_stages_controller.rb`: remove `:total_display_mode`
  da lista de `permit`.
- Nova migration (`db/migrate/`, timestamp `21260...`, seguindo o padrão do fork) removendo a coluna:
  ```ruby
  class RemoveTotalDisplayModeFromIchatrPipelineStages < ActiveRecord::Migration[7.1]
    def change
      remove_column :ichatr_pipeline_stages, :total_display_mode, :integer, default: 0, null: false
    end
  end
  ```
  (assinatura completa da coluna no `remove_column` permite rollback determinístico, mesmo padrão
  de outras migrations reversíveis do fork).

### 5. Teste frontend

- `app/javascript/dashboard/routes/dashboard/settings/pipelineStages/specs/EditPipelineStage.spec.js`:
  remover `total_display_mode: 'value_sum'` do fixture mockado (linha 18) — nenhuma asserção dedicada
  a atualizar, só o dado morto do mock.

## Fora de escopo

- Qualquer mudança em `pipelineCurrencySetting`/`formatCurrencyAmount`/`getCurrencyConfig` — a
  aplicação de moeda já está correta e é só reaproveitada.
- Qualquer mudança na agregação backend de `count`/`value_sum` por estágio (endpoint de aggregates).
- Qualquer mudança em outros campos de `PipelineStage` (`requires_deal_value`,
  `campaign_report_milestone`, `accent_color`, `stale_after_days`, etc.) ou no restante do formulário
  de `EditPipelineStage.vue`.
- Formato de exibição de data em componentes Kanban/Scout — descartado nesta rodada de
  brainstorming (fora de escopo por decisão do usuário, não relacionado a esta fase).

## Testes

- `EditPipelineStage.spec.js`: atualizar o fixture removendo o campo morto (ver Escopo #5) —
  suite deve continuar passando sem nenhuma asserção nova necessária.
- Nenhum teste backend existente referencia `total_display_mode` — nenhuma atualização necessária
  além de rodar a suite depois da migration/remoção do enum, pra garantir que nada mais dependia
  implicitamente da coluna.
- Smoke manual: abrir o board Kanban, confirmar que toda coluna mostra `"{contagem} • {valor}"`
  (com `R$` ou `$` de acordo com a moeda configurada em Configurações → Kanban); abrir "Editar
  Estágio" e confirmar que o switch de Total Display não aparece mais, e que salvar o estágio (outros
  campos) continua funcionando.

## Critérios de aceite

- Toda coluna do Kanban mostra contagem e valor combinados no cabeçalho, sempre, independente de
  qualquer configuração por estágio.
- O switch "Total Display" não existe mais na tela de edição de Estágio do Funil.
- A coluna `total_display_mode` não existe mais em `ichatr_pipeline_stages` (migration aplicada) e o
  model/controller não referenciam mais o campo.
- Nenhuma chave i18n órfã relacionada ao switch permanece em `en/opportunities.json` ou
  `pt_BR/opportunities.json`.
- O valor exibido usa o símbolo de moeda correto (`R$`/`$`) de acordo com a configuração de moeda do
  Kanban, sem regressão em relação ao comportamento atual do modo `value_sum`.
