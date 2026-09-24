# Fase 25 — Público-Alvo do Scout (Audience Targeting)

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: nenhuma fase anterior estritamente — usa mecanismos já estáveis (`Custom::Message`,
padrão de condições flat já usado por `Custom::AutomationRules::OpportunityConditionsFilterService`
e pelos filtros do Kanban/Contatos).

---

## Objetivo

Hoje, um Scout habilitado numa inbox atende **todo mundo** que escreve — binário, sem granularidade.
Isso impede rollout controlado em produção: não há como testar com um grupo pequeno de contatos
antes de abrir para todos. Esta fase adiciona um público-alvo opcional por Scout — uma lista de
condições (telefone, e-mail, label, atributo customizado, etc.) que decide se aquele contato
específico é atendido pelo Scout ou vai direto para a fila humana normal.

## Contexto de investigação (por que este desenho)

- **Captain (Enterprise) já resolve um problema equivalente** com "audiences"
  (`enterprise/app/services/captain/audience_matcher.rb`, `enterprise/app/validators/captain/audience_validator.rb`,
  `enterprise/app/models/captain/assistant.rb` — referência de leitura, não reutilizado por política
  de licenciamento, §3). Lá, `config['audience']` é uma **árvore aninhada** de grupos AND/OR
  (profundidade ≤ 3), avaliada em memória contra o contato/conversa.
- **Gate em dois pontos, não um só** — achado crítico da investigação: Captain nunca deixa uma
  conversa fora do público-alvo ficar `pending` esquecida. `Enterprise::Conversation#determine_conversation_status`
  (override de um hook `before_create` do core) e `Enterprise::Message#reopen_resolved_conversation`
  (override de outro hook do core, para conversa resolvida reaberta) — os dois checam
  `assistant.engages?(contact, conversation)` e, se `false`, forçam `status = :open` em vez de deixar
  a conversa `pending` sem ninguém tratando.
- **Nosso equivalente aos dois hooks do core já existe e está mapeado**: `Conversation#determine_conversation_status`
  (`app/models/conversation.rb:315`, `before_create`) e `Message#reopen_resolved_conversation`
  (`app/models/message.rb:432`). Hoje **nenhum dos dois tem override do Scout** — o único gate atual
  é binário (`scout.enabled?`) dentro do `Custom::ScoutListener`, no nível de mensagem, sem contexto
  de "esta conversa já devia ter nascido `open`". Replicar só o gate por mensagem, sem tocar nesses
  dois hooks, criaria conversas `pending` abandonadas para todo contato fora do público-alvo — pior
  que o problema atual.
- **Decisão de escopo do operador**: público-alvo é **flat** (lista de condições com `query_operator`
  AND/OR sequencial), não árvore aninhada — mesmo formato já usado por
  `Custom::AutomationRules::OpportunityConditionsFilterService` e pelos filtros de Contatos/Kanban já
  existentes no fork (`components-next/filter/ConditionRow.vue`). Cobre o caso real (lista de
  telefones e/ou uma label) sem o custo de engenharia de um builder de árvore genuinamente novo.
- **Escopo de atributos: Contato/Conversa apenas, não Oportunidade** — decisão do operador, com
  motivo técnico que a reforça: o gate dispara em `determine_conversation_status`/`reopen_resolved_conversation`,
  **antes** de qualquer Oportunidade necessariamente existir (ela só nasce depois, quando o Scout
  chama `manage_opportunity` durante a conversa). Filtrar por atributo de Oportunidade nesse ponto
  seria estruturalmente inviável na maioria dos casos. Registrado como possível extensão futura, fora
  do escopo desta fase.
- **Frontend já tem a peça pronta**: `app/javascript/dashboard/components-next/filter/contactProvider.js`
  (`useContactFilterContext()`) já expõe exatamente os atributos necessários (nome, email, telefone,
  identifier, país, cidade, empresa, datas, `blocked`, labels, atributos customizados) no formato que
  `ConditionRow.vue` consome — o mesmo componente que `OpportunitiesFilter.vue` (Kanban) já usa. Não
  precisamos de nenhum provider/atributo novo, só montar um container novo reaproveitando os dois.

## Decisões de desenho

1. **Formato flat**, não árvore aninhada — `[{attribute_key, filter_operator, values, query_operator}, ...]`,
   idêntico ao já usado em automation rules e nos filtros do Kanban.
2. **Escopo Contato/Conversa apenas** nesta fase — Oportunidade fica fora, pelo motivo estrutural
   acima, não só por preferência.
3. **Novo `Custom::Scout::AudienceMatcherService`**, isolado — não estende nem reaproveita
   `Custom::AutomationRules::OpportunityConditionsFilterService` via módulo compartilhado. A
   duplicação da lógica de operadores (~40 linhas) é aceitável frente ao risco de mexer num caminho
   crítico (automation rules) já em produção só para eliminar duplicação pequena.
4. **Dois gates, replicando a dualidade do Captain**: `custom/app/models/custom/conversation.rb`
   (arquivo novo — primeiro override de `Conversation` no fork) e `custom/app/models/custom/message.rb`
   (arquivo existente, estendido).
5. **Vazio = atende todo mundo** — comportamento atual preservado por padrão; público-alvo é opt-in,
   nunca reduz o alcance de um Scout que não configurou nada.
6. **UI reaproveita `ConditionRow.vue` + `useContactFilterContext()`** — nenhum componente/atributo
   novo no provider de filtro; só um container novo (nova aba "Público-Alvo" na configuração do
   Scout).

## Escopo

### 1. Migration — `audience` no Scout

```ruby
class AddAudienceToScouts < ActiveRecord::Migration[7.1]
  def change
    add_column :ichatr_scouts, :audience, :jsonb, null: false, default: []
  end
end
```

### 2. `Custom::Scout::AudienceMatcherService` (novo)

```ruby
# custom/app/services/custom/scout/audience_matcher_service.rb
class Custom::Scout::AudienceMatcherService
  def initialize(audience, contact:, conversation:)
    @audience = audience
    @contact = contact
    @conversation = conversation
  end

  def matches?
    return true if @audience.blank?

    evaluate_conditions
  rescue StandardError => e
    Rails.logger.error "[Scout AudienceMatcherService] Error: #{e.message}"
    true # fail open: um erro de avaliação não deve travar o atendimento normal.
  end

  private

  def evaluate_conditions
    result = nil

    @audience.each_with_index do |condition, index|
      condition = condition.with_indifferent_access
      condition_match = evaluate_single_condition(condition)
      query_operator = condition[:query_operator]&.downcase || 'and'

      result = if index.zero?
                 condition_match
               elsif query_operator == 'or'
                 result || condition_match
               else
                 result && condition_match
               end
    end

    result || false
  end

  def evaluate_single_condition(condition)
    key = condition[:attribute_key].to_s
    operator = condition[:filter_operator].to_s
    values = condition[:values]

    match_operator(extract_attribute_value(key), operator, values)
  end

  def extract_attribute_value(key)
    extract_contact_attr(key) || extract_conversation_attr(key) || extract_custom_attribute_value(key)
  end

  def extract_contact_attr(key)
    return nil unless @contact

    case key
    when 'name' then @contact.name
    when 'email' then @contact.email
    when 'phone_number' then @contact.phone_number
    when 'identifier' then @contact.identifier
    when 'blocked' then @contact.blocked
    when 'country_code' then @contact.additional_attributes&.dig('country_code')
    when 'city' then @contact.additional_attributes&.dig('city')
    when 'company_name' then @contact.additional_attributes&.dig('company_name')
    when 'labels' then @contact.label_list
    end
  end

  def extract_conversation_attr(key)
    return nil unless @conversation

    @conversation.additional_attributes&.dig('browser_language') if key == 'browser_language'
  end

  def extract_custom_attribute_value(key)
    @contact&.custom_attributes&.dig(key)
  end

  # Mesma lógica de match_operator/match_equality_ops/match_text_ops/match_numeric_ops de
  # Custom::AutomationRules::OpportunityConditionsFilterService — ver Decisão de desenho #3 sobre
  # por que não foi extraída para um módulo compartilhado.
  def match_operator(value, operator, target_values)
    targets = Array(target_values).map(&:to_s)
    str_val = value.is_a?(Array) ? value.map(&:to_s) : value.to_s

    match_equality_ops(value, str_val, operator, targets) ||
      match_text_ops(str_val, operator, targets) ||
      match_numeric_ops(value, operator, targets)
  end

  def match_equality_ops(value, str_val, operator, targets)
    case operator
    when 'equal_to' then match_equality(str_val, targets)
    when 'not_equal_to' then !match_equality(str_val, targets)
    when 'is_present' then value.present?
    when 'is_not_present' then value.blank?
    end
  end

  def match_text_ops(str_val, operator, targets)
    case operator
    when 'contains' then str_val.to_s.downcase.include?(targets.first.to_s.downcase)
    when 'does_not_contain' then str_val.to_s.downcase.exclude?(targets.first.to_s.downcase)
    when 'starts_with' then str_val.to_s.downcase.start_with?(targets.first.to_s.downcase)
    end
  end

  def match_numeric_ops(value, operator, targets)
    case operator
    when 'greater_than' then value.to_f > targets.first.to_f
    when 'less_than' then value.to_f < targets.first.to_f
    else false
    end
  end

  def match_equality(actual, targets)
    actual.is_a?(Array) ? targets.any? { |t| actual.include?(t) } : targets.include?(actual)
  end
end
```

### 3. `Scout#engages?`

```ruby
# custom/app/models/scout.rb
def engages?(contact, conversation)
  Custom::Scout::AudienceMatcherService.new(audience, contact: contact, conversation: conversation).matches?
end
```

### 4. `custom/app/models/custom/conversation.rb` (novo arquivo — primeiro override de `Conversation`)

```ruby
# frozen_string_literal: true

module Custom::Conversation
  private

  def determine_conversation_status
    super
    return unless pending?

    scout = inbox.scout
    self.status = :open if scout.present? && scout.enabled? && !scout.engages?(contact, self)
  end
end
```

Requer wiring no core (`app/models/conversation.rb`, já existe `prepend_mod_with('Conversation')`
mas nenhum arquivo `custom/app/models/custom/conversation.rb` ainda) — mesma convenção já usada por
`Custom::Message`/`Custom::Inbox`.

### 5. `custom/app/models/custom/message.rb` (arquivo existente, estendido)

```ruby
module Custom::Message
  private

  def mark_pending_conversation_as_open_for_human_response
    # ...inalterado...
  end

  def reopen_resolved_conversation
    scout = conversation.inbox.scout
    return super if scout.blank? || !scout.enabled?
    return conversation.open! unless scout.engages?(conversation.contact, conversation)

    super
  end

  # ...scout_pending_conversation? inalterado...
end
```

### 6. `Api::V1::Accounts::ScoutsController` — permitir `audience`

```ruby
# custom/app/controllers/api/v1/accounts/scouts_controller.rb
scout_source.permit(*allowed, audience: [%i[attribute_key filter_operator query_operator] + [values: []]], ...)
```

(ajustar a sintaxe exata de `permit` para array de hashes conforme o restante do controller já faz
para `enabled_tools`/`product_catalog`.)

### 7. Frontend — nova aba "Público-Alvo"

Novo `app/javascript/dashboard/components-next/Scout/pageComponents/ScoutAudienceTab.vue`, reaproveitando:
- `ConditionRow.vue` (mesmo componente do `OpportunitiesFilter.vue`)
- `useContactFilterContext()` (`contactProvider.js`) — já expõe todos os atributos de contato
  necessários, sem mudança.

Estrutura próxima de `OpportunitiesFilter.vue`, mas como painel persistente de configuração (salva no
Scout via `ScoutAPI`), não popover de filtro temporário. Adicionar a aba em `ScoutDetail.vue`, ao
lado de Produtos/Base de Conhecimento/Funil/Ferramentas/Playground.

### 8. i18n

Novo grupo de chaves em `scout.json` (en/pt_BR) para o título/descrição da aba e o estado vazio
("Sem público-alvo configurado — o Scout atende todos os contatos desta inbox.").

## Fora de escopo

- Filtro por atributo de Oportunidade — estruturalmente inviável no ponto de gate atual (ver
  Contexto de investigação); possível extensão futura se um caso de uso real aparecer em outro ponto
  do fluxo (ex: dentro do próprio `AgentRunner`, não na criação da conversa).
- Árvore de condições aninhada (grupos AND dentro de OR) — decisão explícita pelo formato flat.
- Extrair lógica de operador compartilhada com `OpportunityConditionsFilterService` — ver Decisão de
  desenho #3.
- Qualquer UI de "modo de teste"/rollout percentual (ex: "atenda 10% aleatório") — não pedido; o
  público-alvo é sempre determinístico por atributo, não amostragem.

## Testes

- `custom/spec/services/custom/scout/audience_matcher_service_spec.rb`: audiência vazia sempre
  retorna `true`; condição única `equal_to`/`contains`/`is_present` etc.; múltiplas condições com
  `query_operator` AND e OR; atributo customizado; erro de avaliação retorna `true` (fail open).
- `custom/spec/models/custom/conversation_spec.rb` (novo, ou estender existente): conversa criada
  numa inbox com Scout habilitado e público-alvo configurado nasce `pending` para contato dentro do
  público, `open` para contato fora.
- `custom/spec/models/custom/message_spec.rb` (novo, ou estender existente): conversa resolvida
  reaberta por nova mensagem de contato fora do público-alvo abre como `open`, não `pending`.
- `custom/spec/models/scout_spec.rb`: `engages?` delega corretamente ao `AudienceMatcherService`.
- `custom/spec/controllers/api/v1/accounts/scouts_controller_spec.rb`: `audience` aceito nos
  parâmetros permitidos.
- Frontend: `ScoutAudienceTab.spec.js` cobrindo adicionar/remover condição e salvar.

## Critérios de aceite

- Um Scout sem público-alvo configurado continua atendendo todo mundo, sem regressão.
- Um Scout com público-alvo configurado só engaja contatos que casam com as condições; conversas de
  contatos fora do público nascem `open` (fila humana normal), nunca `pending` abandonada.
- O mesmo vale para conversas resolvidas reabertas por um contato fora do público-alvo.
- A configuração de público-alvo é editável pela UI, reaproveitando o mesmo componente de condição
  já usado nos filtros de Contatos/Kanban — sem inconsistência visual com o resto do produto.
