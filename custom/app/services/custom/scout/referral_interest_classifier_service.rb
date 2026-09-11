# frozen_string_literal: true

class Custom::Scout::ReferralInterestClassifierService
  include Integrations::LlmInstrumentation

  def initialize(scout:, conversation:)
    @scout = scout
    @conversation = conversation
    @account = conversation.account
  end

  def classify(opportunity:, temperature: 0.0)
    options = available_options
    return nil if options.blank? || opportunity.blank?

    user_prompt = build_user_prompt(opportunity)
    return nil if user_prompt.blank?

    response = execute_classification(user_prompt, options, temperature)
    extract_matched_interest(response&.content, options)
  rescue StandardError => e
    handle_classification_error(e)
  end

  private

  def available_options
    @scout.interest_attribute_definition&.attribute_values || []
  end

  def execute_classification(user_prompt, options, temperature)
    schema_class = Custom::Scout::ReferralInterestClassifierSchema.for_options(options)

    instrument_llm_call(instrumentation_params(user_prompt, temperature, options)) do
      @scout.llm_chat(temperature: temperature)
            .with_schema(schema_class)
            .with_instructions(system_instructions(options))
            .ask(user_prompt)
    end
  end

  def extract_matched_interest(content, options)
    parsed = parse_response(content)
    interest = parsed['interest'] || parsed[:interest]
    options.include?(interest.to_s) ? interest.to_s : nil
  end

  def handle_classification_error(error)
    ChatwootExceptionTracker.new(error, account: @scout.account).capture_exception
    Rails.logger.warn(
      "[Scout][ReferralInterestClassifier] Failed for conversation #{@conversation.id}: #{error.class.name}: #{error.message}"
    )
    nil
  end

  def build_user_prompt(opportunity)
    ad_elements = [
      ("Campanha: #{opportunity.campaign_name}" if opportunity.campaign_name.present?),
      ("Conjunto de anúncios: #{opportunity.campaign_adset_name}" if opportunity.campaign_adset_name.present?),
      ("Anúncio: #{opportunity.campaign_ad_name}" if opportunity.campaign_ad_name.present?),
      ("Título do anúncio: #{opportunity.campaign_headline}" if opportunity.campaign_headline.present?),
      ("Texto do anúncio: #{opportunity.campaign_body}" if opportunity.campaign_body.present?)
    ].compact

    return nil if ad_elements.blank?

    <<~PROMPT
      <ad_content>
      #{ad_elements.join("\n")}
      </ad_content>

      Identifique qual opção de interesse o anúncio acima promove, ou retorne null se não for possível identificar com segurança.
    PROMPT
  end

  def system_instructions(options)
    formatted_options = options.map { |opt| "- #{opt}" }.join("\n")

    <<~INSTRUCTIONS
      Você é um classificador especializado em identificar o interesse ou serviço anunciado a partir do conteúdo textual de anúncios pagos.

      Sua tarefa é analisar os dados do anúncio (título, texto, nome da campanha ou anúncio) e determinar qual opção de interesse da lista de opções válidas o anúncio promove de forma clara e inequívoca.

      Opções válidas de interesse:
      #{formatted_options}

      Regras estritas (Anti-alucinação):
      1. Só selecione uma opção se houver evidência textual explícita e clara no anúncio de que o produto ou serviço promovido corresponde a ela.
      2. Se o conteúdo do anúncio for genérico, institucional, ambíguo, ou se não corresponder com clareza a nenhuma das opções válidas, retorne 'interest' como null.
      3. NUNCA adivinhe ou selecione uma opção por aproximação ou conveniência quando o anúncio não for claro.
      4. Retorne estritamente o JSON com a propriedade 'interest'.
    INSTRUCTIONS
  end

  def parse_response(content)
    return {} if content.blank?
    return content if content.is_a?(Hash)

    sanitized = content.to_s.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
    JSON.parse(sanitized)
  rescue JSON::ParserError
    {}
  end

  def instrumentation_params(user_prompt, temperature, options)
    config = ScoutAccountConfig.find_by(account_id: @scout.account_id)

    {
      span_name: 'llm.scout.referral_interest_classifier',
      model: config&.model_name || 'gemini-2.0-flash',
      temperature: temperature,
      account: @conversation.account,
      account_id: @conversation.account_id,
      conversation_id: @conversation.id,
      feature_name: 'scout_referral_interest_classifier',
      messages: [
        { role: 'system', content: system_instructions(options) },
        { role: 'user', content: user_prompt }
      ],
      metadata: {
        scout_id: @scout.id,
        channel_type: @conversation.inbox&.channel_type
      }.compact
    }
  end
end
