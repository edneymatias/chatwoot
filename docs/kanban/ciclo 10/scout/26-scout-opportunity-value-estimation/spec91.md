# Fase 26 — Estimativa de Valor da Oportunidade por Interesse

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Fase 02 (`Custom::ReferralAttributionService`, `manage_opportunity`/`create_opportunity`),
Fase 12 (`Custom::Scout::ActionClassifierService`/`ActionClassifierSchema` — padrão de classificador
de escolha forçada reaproveitado aqui).

---

## Objetivo

Hoje, `Opportunity#value` só é preenchido se um humano digitar manualmente ou se o modelo passar
`estimated_value` ao `manage_opportunity` — parâmetro que existe na tool
(`custom/app/services/custom/scout/tools/manage_opportunity.rb:9`) mas nunca é usado, porque nenhuma
instrução no system prompt diz em que basear esse número. Consequência prática:
`Reports::SalesForecastCalculator` trata valor ausente como `0.0`
(`sales_forecast_calculator.rb:113`), então toda oportunidade criada pelo Scout hoje contribui zero
pro forecast, distorcendo o relatório pra baixo. Esta fase preenche `value` automaticamente,
deterministicamente, a partir de um sinal de qualificação que a clínica já configura (interesse no
tratamento) e, quando disponível, do próprio conteúdo do anúncio de origem — nunca de um número
inventado pelo modelo.

## Contexto de investigação (por que este desenho)

- **O hook mecânico já existe, só não é usado.** `manage_opportunity`'s `estimated_value` já é
  persistido em `Opportunity#value` tanto na criação (`manage_opportunity.rb:63`) quanto na
  atualização (`manage_opportunity.rb:99`) — o problema nunca foi "como o Scout escreve o valor", foi
  "em que ele basearia esse número".
- **Não é seguro pedir pro modelo estimar livremente.** O guardrail de anti-alucinação já proíbe
  "inventar... preços... sem base no contexto fornecido" (`system_prompts_service.rb`). Um Scout sem
  catálogo de preços (caso comum, ver Fase de brainstorm sobre catálogo de produtos) não tem de onde
  tirar um número — pedir uma estimativa livre seria pedir alucinação.
- **O sinal certo já existe no funil**: o atributo de qualificação "interesse" (nome varia por
  clínica) já é, na prática, uma categoria que humanos já sabem mapear pra um valor mentalmente
  ("implante = 2500 mínimo"). Isso não é estimativa livre — é **consulta a uma tabela configurada
  pelo operador**, nunca um número inventado pelo modelo.
- **Isso é puramente interno.** Não tem nenhuma relação com o guardrail de "nunca informar preço ao
  cliente" (decisão de outra sessão de brainstorming) — o valor fica só no registro da Oportunidade,
  usado pra relatório/forecast, nunca dito ao cliente.
- **Mapa manual de campanha (`campaign_source_id` → interesse) foi considerado e descartado.**
  Campanhas são voláteis (mudam mês a mês); exigir que o operador lembre de recadastrar toda vez que
  troca de anúncio é receita pra atribuir valores errados quando ele esquecer. Decisão: classificar a
  partir do **conteúdo** do anúncio (`campaign_headline`/`campaign_body`/`campaign_name`/
  `campaign_adset_name`/`campaign_ad_name`, todos já persistidos em `Opportunity` por
  `Custom::ReferralAttributionService`), não do ID do anúncio.
- **Classificação de escolha forçada, não geração livre — e "não identificado" é distinto de uma
  opção real de negócio.** O atributo de qualificação "interesse", sendo tipo `list`
  (`CustomAttributeDefinition#attribute_values`, jsonb), já tem um conjunto fixo e pequeno de opções.
  Um classificador (mesmo padrão de `Custom::Scout::ActionClassifierService`/`ActionClassifierSchema`,
  Fase 12) só pode escolher entre essas opções **ou** um resultado distinto "não identificado" — nunca
  cai numa opção real (ex.: "Outro") só por incerteza. Isso evita contaminar um valor de negócio real
  com incerteza técnica do classificador.
- **"Outro" sem valor configurado não é um caso especial** — já resolvido de graça pela própria forma
  da tabela interesse→valor: se o operador não configurar uma entrada pra "Outro", nenhum valor é
  atribuído nesse caso; se configurar um valor simbólico, é isso que é usado. Nenhuma lógica
  condicional extra necessária.

## Decisões de desenho

1. **Uma única tabela de dinheiro** (`value_by_interest`, jsonb no Scout): `{opção_do_atributo =>
   valor}`. Usada tanto quando o interesse vem de classificação automática do anúncio quanto quando
   vem de resposta real do lead na conversa — uma fonte de verdade só, sem duplicar configuração.
2. **Classificação automática do conteúdo do anúncio**, não mapa manual por `campaign_source_id` —
   ver Contexto de investigação acima.
3. **"Não identificado" é um resultado distinto de qualquer opção real** — nunca escolhe uma opção de
   negócio (nem "Outro") só por incerteza; nesse caso nada é preenchido, a conversa segue perguntando
   normalmente, igual hoje.
4. **Determinístico no código, não dependente do modelo lembrar** — mesmo princípio já usado em toda
   essa fase do Scout. O código decide quando classificar e quando sincronizar o valor; o modelo
   principal da conversa nunca precisa saber que isso existe.
5. **Configuração opcional** — sem configurar qual atributo representa "interesse", nada muda do
   comportamento atual.

## Escopo

### 1. Migration — `interest_attribute_definition_id` e `value_by_interest` no Scout

```ruby
class AddValueEstimationToScouts < ActiveRecord::Migration[7.1]
  def change
    add_reference :ichatr_scouts, :interest_attribute_definition, foreign_key: { to_table: :custom_attribute_definitions, on_delete: :nullify }, index: true
    add_column :ichatr_scouts, :value_by_interest, :jsonb, null: false, default: {}
  end
end
```

### 2. `Scout` model

```ruby
belongs_to :interest_attribute_definition, class_name: 'CustomAttributeDefinition', optional: true
```

### 3. `Custom::Scout::ReferralInterestClassifierSchema` (novo)

```ruby
# custom/app/services/custom/scout/referral_interest_classifier_schema.rb
class Custom::Scout::ReferralInterestClassifierSchema < RubyLLM::Schema
  def self.for_options(options)
    Class.new(self) do
      any_of :interest, description: 'The matched interest option, or null when not confidently identifiable from the ad content' do
        string enum: options
        null
      end
    end
  end
end
```

(schema dinâmico — as opções válidas vêm de `scout.interest_attribute_definition.attribute_values`,
diferentes por conta; mesmo truque `any_of`/`null` já usado em `ActionClassifierSchema` pra manter o
campo obrigatório no modo estrito de Structured Outputs, permitindo valor nulo.)

### 4. `Custom::Scout::ReferralInterestClassifierService` (novo)

```ruby
# custom/app/services/custom/scout/referral_interest_classifier_service.rb
class Custom::Scout::ReferralInterestClassifierService
  include Integrations::LlmInstrumentation

  def initialize(scout:, opportunity:)
    @scout = scout
    @opportunity = opportunity
  end

  def classify
    options = @scout.interest_attribute_definition&.attribute_values
    return nil if options.blank? || referral_content.blank?

    response = instrument_llm_call(instrumentation_params) do
      @scout.llm_chat(temperature: 0.0)
            .with_schema(Custom::Scout::ReferralInterestClassifierSchema.for_options(options))
            .with_instructions(system_instructions(options))
            .ask(referral_content)
    end

    parse_response(response&.content)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @scout.account).capture_exception
    nil
  end

  private

  def referral_content
    [
      @opportunity.campaign_name, @opportunity.campaign_adset_name, @opportunity.campaign_ad_name,
      @opportunity.campaign_headline, @opportunity.campaign_body
    ].compact_blank.join("\n")
  end

  def system_instructions(options)
    <<~INSTRUCTIONS
      Você classifica o conteúdo de um anúncio de origem em uma das opções de interesse configuradas
      pela clínica: #{options.join(', ')}.
      Escolha 'interest' apenas quando o conteúdo indicar claramente uma dessas opções. Se o conteúdo
      for ambíguo, genérico, ou não permitir identificar com confiança, retorne null — nunca escolha
      uma opção só por eliminação ou palpite.
    INSTRUCTIONS
  end

  def parse_response(content)
    hash = content.is_a?(Hash) ? content : JSON.parse(content.to_s)
    hash['interest'] || hash[:interest]
  rescue JSON::ParserError
    nil
  end

  def instrumentation_params
    { span_name: 'llm.scout.referral_interest_classifier', account: @scout.account, account_id: @scout.account_id,
      feature_name: 'scout_referral_interest_classifier', metadata: { scout_id: @scout.id }.compact }
  end
end
```

### 5. `Custom::Scout::ValueEstimationService` (novo) — ponto único de sincronização

```ruby
# custom/app/services/custom/scout/value_estimation_service.rb
class Custom::Scout::ValueEstimationService
  def initialize(scout:)
    @scout = scout
  end

  # Chamado sempre que o atributo de interesse muda (classificação automática ou resposta real do
  # lead) — nunca sobrescreve um valor já existente com "nenhum resultado"; só atribui quando há
  # correspondência configurada.
  def sync!(opportunity)
    attribute_key = @scout.interest_attribute_definition&.attribute_key
    return if attribute_key.blank?

    interest = opportunity.custom_attributes&.dig(attribute_key)
    return if interest.blank?

    mapped_value = @scout.value_by_interest[interest]
    opportunity.value = mapped_value if mapped_value.present?
  end
end
```

### 6. `Custom::Scout::Tools::ManageOpportunity` — dois pontos de chamada

```ruby
# create_opportunity, logo após Custom::ReferralAttributionService.process
referral_message = find_referral_message
Custom::ReferralAttributionService.process(opp, referral_message) if referral_message
classify_and_apply_referral_interest(opp) if referral_message
```

```ruby
def classify_and_apply_referral_interest(opp)
  return if scout.interest_attribute_definition.blank?

  interest = Custom::Scout::ReferralInterestClassifierService.new(scout: scout, opportunity: opp).classify
  return if interest.blank?

  attribute_key = scout.interest_attribute_definition.attribute_key
  opp.custom_attributes = (opp.custom_attributes || {}).merge(attribute_key => interest)
  Custom::Scout::ValueEstimationService.new(scout: scout).sync!(opp)
  opp.save!
end
```

```ruby
# update_opportunity / apply_opportunity_fields, depois que custom_attributes são aplicados
Custom::Scout::ValueEstimationService.new(scout: scout).sync!(opp)
```

## Fora de escopo

- Mapa manual `campaign_source_id` → interesse — descartado explicitamente (Contexto de
  investigação).
- Qualquer exposição desse valor ao cliente na conversa — permanece puramente interno.
- Reclassificar/reestimar valor quando o operador edita `value_by_interest` depois — oportunidades já
  criadas não são retroativamente recalculadas nesta fase.
- Suporte a atributo de interesse que não seja tipo `list` — o desenho depende de um conjunto fixo de
  opções; outros tipos ficam fora.

## Testes

- `custom/spec/services/custom/scout/referral_interest_classifier_service_spec.rb`: conteúdo de
  anúncio claro retorna a opção correta; conteúdo ambíguo/vazio retorna `nil`; sem
  `interest_attribute_definition` configurado retorna `nil` sem chamar a LLM.
- `custom/spec/services/custom/scout/value_estimation_service_spec.rb`: interesse presente e mapeado
  seta `value`; interesse presente mas sem entrada no mapa não altera `value`; sem
  `interest_attribute_definition` configurado, no-op.
- `custom/spec/services/custom/scout/tools/manage_opportunity_spec.rb`: criação de oportunidade com
  referral e classificação bem-sucedida já nasce com `custom_attributes[interesse]` e `value`
  preenchidos; atualização de oportunidade com resposta real de interesse sincroniza `value`
  igualmente, independente da classificação de anúncio.
- `custom/spec/models/scout_spec.rb`: validação de `interest_attribute_definition` (associação
  opcional, `on_delete: :nullify`).

## Critérios de aceite

- Um Scout sem `interest_attribute_definition` configurado não tem nenhuma mudança de comportamento.
- Uma Oportunidade criada a partir de um lead de anúncio cujo conteúdo identifica claramente uma
  opção de interesse configurada nasce já com `custom_attributes[interesse]` e `Opportunity#value`
  preenchidos, antes de qualquer resposta do lead.
- Quando o conteúdo do anúncio for ambíguo ou não identificável, nenhum valor é atribuído
  automaticamente — a conversa segue perguntando o interesse normalmente.
- Quando o lead responde a pergunta de interesse durante a qualificação (sem vir de anúncio, ou
  corrigindo o que a classificação automática preencheu), `Opportunity#value` é sincronizado a partir
  da mesma tabela `value_by_interest`.
- Uma opção de interesse sem entrada configurada em `value_by_interest` (ex.: "Outro" sem valor
  definido) nunca atribui um valor — nem zero, nem um placeholder não intencional.
- Nenhum valor numérico é gerado livremente pelo modelo em nenhum ponto deste fluxo.
