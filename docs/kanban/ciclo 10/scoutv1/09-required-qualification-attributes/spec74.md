# Fase 9 — Inteligência de Funil: Estágios & Campos de Qualificação

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap), §4.1 (Goal-Driven + Tool
Calling)
**Depends on**: Fase 02 (`manage_opportunity` / `move_opportunity_stage`), Fase 05 (UI da aba
Funil), Fase 08 (`Custom::Scout::SystemPromptsService` — esta fase adiciona uma nova seção ao
template criado ali).

---

## Contexto: o que já existe

A infraestrutura de funil e de campos obrigatórios **já está implementada e já tem enforcement
real no model** — o que faltava foi mapeado por completo durante a sessão de especificação e é
mais estreito do que o preview original sugeria.

### Estágios (`PipelineStage`)
- `has_many :pipeline_stage_required_fields` → atributos de **oportunidade** obrigatórios para
  entrar naquele estágio (`custom/app/models/pipeline_stage_required_field.rb`).
- Configurável hoje via Kanban (`PipelineStageRequiredFieldsController`) — UI já existe, fora de
  escopo desta fase.

### Fechamento (`PipelineClosingRequiredField`)
- Tabela **independente de estágio**, por conta e por `outcome` (`won`/`lost`) —
  `custom/app/models/pipeline_closing_required_field.rb`. Define quais atributos de oportunidade
  são obrigatórios para fechar como ganho ou perdido, com sua própria UI/controller já prontos.

### Enforcement já existe no model — `Custom::Concerns::OpportunityValidations`
(`custom/app/models/custom/concerns/opportunity_validations.rb`)

```ruby
validate :validate_forward_stage_move_requirements, on: :update, if: :pipeline_stage_id_changed?
validate :validate_closing_requirements, on: :update, if: :status_changed?
```

- `validate_forward_stage_move_requirements`: bloqueia `save`/`save!` quando a oportunidade se
  move para **frente** (`position` maior que o estágio anterior) e o estágio de destino tem
  `pipeline_stage_required_fields` não preenchidos em `custom_attributes`, ou exige
  `requires_deal_value?` e `value` está `nil`. Preenche `opportunity.missing_required_fields` com
  `{ custom_attribute_keys: [...], requires_value: bool }` antes de adicionar o erro.
- `validate_closing_requirements`: bloqueia mudança de `status` para `won`/`lost` se
  `PipelineClosingRequiredField` daquele outcome não estiver satisfeito.
- **Não roda em criação** (`on: :update`) — só em updates. `ManageOpportunity#create_opportunity`
  usa `Opportunity.create!` e não passa por essa validação no estágio inicial.
- **O problema real não é a ausência de enforcement — é que as tools engolem a exceção.**
  `MoveOpportunityStage#execute` e `ManageOpportunity#update_opportunity` chamam `save!` cru. Uma
  `ActiveRecord::RecordInvalid` sobe, estoura o `rescue StandardError` de
  `AgentRunner#perform`, e a conversa é jogada para `perform_fail_safe_handoff` com a mensagem
  genérica *"Erro durante execução do assistente"* — o LLM nunca recebe o motivo real nem pode
  retomar a coleta de dados. Isso é o problema #2 do preview original, mas a causa é diferente do
  que se supunha: não falta validação, falta a tool tratar o resultado dela.

### Campos globais do Scout (`ScoutRequiredField`) — zero enforcement hoje
- `Scout#required_custom_attribute_definitions` (aba Funil, já configurável via UI) é **puramente
  informativo hoje**. `Opportunity` não tem nenhuma referência a `Scout` e nenhuma validação do
  model consulta `ScoutRequiredField`. Confirmado por busca completa no código: a única tabela
  usada em `OpportunityValidations` é `pipeline_stage_required_fields`
  (`stage.required_custom_attribute_definitions`, uma associação de mesmo nome mas de
  `PipelineStage`, não de `Scout`).
- Isso é o problema #5 do preview: os campos globais de qualificação do Scout não têm efeito
  nenhum hoje, em lugar nenhum.

### `Scout` — configuração de funil (já 100% funcional na UI, `ScoutFunnelTab.vue`)
- `default_pipeline_stage_id`, `qualified_stage_id`, `unqualified_stage_id`,
  `handover_team_id`, `required_custom_attribute_definitions` — todos editáveis hoje pelo
  operador. Nenhum desses valores, porém, chega ao system prompt nem é lido por
  `MoveOpportunityStage`/`ManageOpportunity`. O LLM não sabe quais IDs de estágio existem, então
  ou nunca move a oportunidade, ou move para IDs arbitrários — problema #1 do preview,
  confirmado: **zero informação de estágios chega ao prompt hoje.**

### `MoveOpportunityStage` — comportamento de `lost` inconsistente com a decisão desta fase
```ruby
opportunity.pipeline_stage_id = stage.id
if lost_reason.present?
  opportunity.lost_reason = lost_reason
  opportunity.status = :lost if opportunity.respond_to?(:status)
end
opportunity.save!
```
Hoje, qualquer `lost_reason` não vazio fecha a oportunidade como `lost` **imediatamente**,
independente de qual `stage_id` foi passado, sem revisão humana e sem consultar
`PipelineClosingRequiredField`. Isso contradiz a decisão de design tomada nesta sessão (ver
abaixo) e precisa ser removido.

### `HandoverToHuman` — lógica de handoff hoje só existe dentro da tool
(`custom/app/services/custom/scout/tools/handover_to_human.rb`) Atribui time/assignee, chama
`conversation.bot_handoff!`, cria nota privada de transferência e gera memória de contato. Essa
lógica precisa ser reutilizável fora da tool (ver Escopo §3) para o handoff automático ao
qualificar.

---

## Decisões de design resolvidas nesta sessão

1. **Desqualificação = estágio de revisão humana (Opção A do preview).** O Scout move a
   oportunidade para `unqualified_stage_id`; `status` permanece `open`. O Scout **nunca** marca
   `status: lost` — isso é sempre um evento humano, feito depois via Kanban UI (que já passa pela
   validação `validate_closing_requirements` existente, sem nenhuma mudança necessária). Isso
   resolve o problema #4 do preview (campos obrigatórios ao marcar como perdido): como o Scout não
   fecha como `lost`, `PipelineClosingRequiredField` para o outcome `lost` está inteiramente fora
   do alcance desta fase.
2. **`won` está fora do escopo do Scout.** Um SDR qualifica e entrega para um humano fechar a
   venda — o Scout nunca chama `status: won`. `PipelineClosingRequiredField` para o outcome `won`
   também fica fora do alcance desta fase.
3. **Handoff automático ao qualificar.** Quando a oportunidade entra em `qualified_stage_id`, o
   handoff para `handover_team_id` é disparado deterministicamente pelo backend (mesmo mecanismo
   de `HandoverToHuman`, extraído para um serviço reutilizável) — não depende do LLM lembrar de
   chamar `handover_to_human` como uma segunda ação separada.
4. **Campos globais do Scout (`ScoutRequiredField`) fazem parte do gate de qualificação**, não de
   todo estágio. Eles se somam (união) aos `pipeline_stage_required_fields` do estágio qualificado
   especificamente — não se aplicam a estágios intermediários genéricos. Resolve o problema #5.

---

## Escopo

### 1. Nova seção `funnel_section` em `Custom::Scout::SystemPromptsService`

Adiciona uma seção ao template (mesmo padrão aditivo de `identity_section`/`guardrails_section`,
Fase 08), injetando:

- **Catálogo de estágios** da conta (`scout.account.pipeline_stages`, já ordenados por
  `position`): `ID`, nome, e papel semântico quando aplicável (`default_pipeline_stage_id` /
  `qualified_stage_id` / `unqualified_stage_id`).
- **Campos obrigatórios por estágio**, só para estágios que de fato têm
  `pipeline_stage_required_fields` configurados — `attribute_key`, `attribute_display_name`,
  `attribute_display_type`, e `attribute_values` quando o tipo for `list`.
- **Campos globais de qualificação do Scout** (`scout.required_custom_attribute_definitions`),
  rotulados explicitamente como adicionais e obrigatórios para mover para o estágio qualificado.
- **Semântica operacional**, em texto direto para o LLM:
  - Mover para o estágio qualificado dispara handoff automático para o time humano — o Scout não
    precisa (e não deve) chamar `handover_to_human` nesse caso.
  - Mover para o estágio desqualificado é uma fila de revisão humana, não um encerramento — o
    Scout deve registrar o motivo via `create_private_note` antes ou junto dessa movimentação, em
    vez de tentar preencher um "motivo de perda".
- Se o Scout não tiver `qualified_stage_id`/`unqualified_stage_id`/estágios com campos
  configurados, as sub-seções correspondentes são omitidas (mesmo padrão `compact`/`presence` já
  usado no restante do template) — sem forçar o operador a configurar tudo.

`AgentRunner#build_system_instructions` passa a repassar `account:` (ou os estágios já
carregados) para `SystemPromptsService.build`, que hoje já recebe `scout:` — o acesso aos estágios
pode ser feito via `scout.account.pipeline_stages`, sem novo parâmetro obrigatório.

### 2. `Custom::Scout::HandoffService` (extraído de `HandoverToHuman`)

```ruby
Custom::Scout::HandoffService.new(scout:, conversation:).perform(assignee_id: nil, team_id: nil, reason: nil)
```
Move para cá as quatro responsabilidades hoje privadas em `HandoverToHuman`: atribuir
time/assignee, chamar `bot_handoff!` (só se a conversa estiver `pending`), criar nota privada de
transferência (só se `reason` presente) e gerar memória de contato (só se
`scout.feature_memory?`). `HandoverToHuman#execute` passa a ser um wrapper fino que chama esse
serviço e mantém seu próprio `@handoff_executed = true` (estado de fluxo da tool, não do domínio).

### 3. `Custom::Scout::OpportunityStageTransitionService` (novo)

```ruby
Custom::Scout::OpportunityStageTransitionService.new(scout:, conversation:, opportunity:).call(stage_id:)
```

Usado por `MoveOpportunityStage` e `ManageOpportunity` sempre que `stage_id` for alterado — ponto
único de enforcement, fechando a brecha de contornar `move_opportunity_stage` via
`manage_opportunity`.

Fluxo:
1. Resolve `stage = scout.account.pipeline_stages.find_by(id: stage_id)` — `stage_id` inválido
   retorna mensagem descritiva sem tocar o banco.
2. Se `stage.id == scout.qualified_stage_id`: verifica proativamente
   `scout.required_custom_attribute_definitions` contra `opportunity.custom_attributes` (os
   campos do próprio estágio continuam cobertos pela validação já existente no model — não
   duplicada aqui). Falta algum campo global → retorna mensagem descritiva com os
   `attribute_display_name` faltantes, **sem chamar `save`**.
3. Atribui `opportunity.pipeline_stage_id = stage.id` (a oportunidade pode já carregar outras
   mudanças em memória — título, valor, `custom_attributes` — atribuídas pelo chamador antes de
   invocar o serviço; ver §4/§5) e chama `opportunity.save` (não `save!`).
4. Se `save` falhar (`opportunity.errors.any?`): monta mensagem descritiva a partir de
   `opportunity.missing_required_fields` (resolvendo `custom_attribute_keys` para
   `attribute_display_name` via `CustomAttributeDefinition`) — nunca deixa a exceção subir.
5. Se `save` for bem-sucedido e `stage.id == scout.qualified_stage_id`: chama
   `Custom::Scout::HandoffService.new(scout:, conversation:).perform` (sem `reason` — o motivo já
   está implícito no template do prompt; se o Scout quiser registrar contexto adicional, usa
   `create_private_note` antes).
6. Retorna string de sucesso (`"Opportunity moved to stage #{stage.name} successfully."`) — mesmo
   contrato de retorno que as tools já usam hoje.

### 4. `MoveOpportunityStage`

- Remove o parâmetro `lost_reason` e todo o bloco que seta `status: :lost`.
- `execute(stage_id:)` passa a delegar inteiramente para
  `OpportunityStageTransitionService#call`.
- Modo `playground?` mantém a simulação textual, apenas sem menção a `lost_reason`.

### 5. `ManageOpportunity`

- `update_opportunity`: continua atribuindo `title`/`value`/`custom_attributes` em memória como
  hoje; se `stage_id` presente, delega a atribuição do estágio + o `save` para
  `OpportunityStageTransitionService#call(stage_id: stage_id)` **em vez de** `opp.save!` direto —
  um único save atômico cobre estágio + demais campos, então `custom_attributes` passados no mesmo
  `manage_opportunity(action: 'update', ...)` já contam para o gate de qualificação. Se `stage_id`
  ausente, comportamento inalterado (`opp.save!` direto).
- `create_opportunity`: **sem mudança** — criação inicial não passa pelo gate (mesma exceção
  `on: :update` já existente no model; criar diretamente no estágio qualificado não é um caso
  realista de uso e não faz parte do escopo desta fase).

---

## Fora de escopo desta fase

- UI de configuração de campos obrigatórios (por estágio ou de fechamento) — já existe.
- UI da aba Funil do Scout (estágios/campos globais) — já existe.
- Criação do estágio de desqualificação em si — configuração de conta, não do Scout.
- `PipelineClosingRequiredField` para os outcomes `won`/`lost` — permanece exclusivamente um fluxo
  humano via Kanban UI, sem nenhuma mudança nesta fase.
- Scout marcar `won` ou `lost` diretamente — decidido como fora do papel de SDR nesta sessão.
- Integração Meta CAPI ao qualificar (spec60 §2.4 — fase futura).

---

## Critérios de aceite

- O system prompt do Scout passa a incluir o catálogo de estágios da conta com IDs, nomes e
  papéis semânticos (default/qualificado/desqualificado), mais os campos obrigatórios por estágio
  e os campos globais de qualificação do Scout.
- `move_opportunity_stage` não aceita mais `lost_reason` nem seta `status: lost` em nenhuma
  circunstância.
- Mover para o estágio qualificado sem os campos globais de qualificação preenchidos retorna uma
  mensagem descritiva ao LLM (nomes de exibição dos campos faltantes) e **não** altera o estágio
  da oportunidade nem dispara handoff.
- Mover para frente (posição maior que o estágio atual) para um estágio sem os campos exigidos
  por ele (`PipelineStageRequiredField`) retorna mensagem descritiva ao LLM em vez de estourar
  exceção / acionar fail-safe handoff genérico — tanto via `move_opportunity_stage` quanto via
  `manage_opportunity` com `stage_id`. Movimentos para trás ou laterais mantêm o comportamento já
  existente no model (sem enforcement de campos) — esta fase não muda essa regra.
- Mover com sucesso para o estágio qualificado dispara automaticamente o handoff para
  `handover_team_id` (atribuição de time, `bot_handoff!`, memória de contato se aplicável) sem
  exigir uma chamada separada a `handover_to_human`.
- Mover para o estágio desqualificado apenas altera o estágio (status permanece `open`) — nenhum
  fechamento automático ocorre.
- `ManageOpportunity` com `stage_id` passa pelo mesmo enforcement que `MoveOpportunityStage`
  (nenhuma tool permite contornar o gate de qualificação).
