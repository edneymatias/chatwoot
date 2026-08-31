# frozen_string_literal: true

class Custom::Scout::ActionClassifierService
  include Integrations::LlmInstrumentation

  def initialize(scout:, conversation:)
    @scout = scout
    @conversation = conversation
    @account = conversation.account
  end

  def classify(message_history:, temperature: 0.0)
    user_prompt = build_user_prompt(message_history)

    response = instrument_llm_call(instrumentation_params(user_prompt, temperature)) do
      @scout.llm_chat(temperature: temperature)
            .with_schema(Custom::Scout::ActionClassifierSchema)
            .with_instructions(system_instructions)
            .ask(user_prompt)
    end

    parsed = parse_response(response&.content)
    normalize_response(parsed, response&.content)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @scout.account).capture_exception
    Rails.logger.warn(
      "[Scout][ActionClassifier] Failed for conversation #{@conversation.id}: #{e.class.name}: #{e.message}"
    )
    { 'action' => nil, 'action_reason' => nil, 'error' => e.message }
  end

  private

  def build_user_prompt(message_history)
    formatted_history = (message_history || []).map do |msg|
      role = msg[:role] || msg['role']
      content = msg[:content] || msg['content']
      "[#{role.to_s.upcase}]: #{content}"
    end.join("\n")

    <<~PROMPT
      <conversation_history>
      #{formatted_history}
      </conversation_history>

      Analise o histórico da conversa e classifique se a interação deve continuar com o assistente virtual ou ser transferida para um atendente humano.
    PROMPT
  end

  def system_instructions
    <<~INSTRUCTIONS
      Você é um classificador de intenção de atendimento humano para um assistente de IA de vendas (Scout).
      Sua função é avaliar as mensagens do cliente no histórico da conversa e determinar se deve continuar o atendimento automatizado ou transferir para um humano.

      Ações:
      - 'continue': O cliente deseja prosseguir tirando dúvidas, recebendo recomendações ou interagindo com o assistente.
      - 'handoff': O cliente deve ser transferido imediatamente para a equipe humana.

      Motivos de Transferência ('action_reason' quando action == 'handoff'):
      - 'explicit_human_request': O cliente solicitou explicitamente atendimento humano (ex: "quero falar com alguém", "me passa para um atendente", "humano por favor").
      - 'human_offer_accepted': O cliente aceitou uma oferta anterior de transferência humana.
      - 'repeated_frustration_or_loop': O cliente demonstrou frustração repetida, irritação com a IA ou a conversa está em loop sem progresso.
      - 'out_of_scope_commercial_request': A solicitação do cliente está fora do escopo comercial do assistente e requer intervenção de um vendedor humano.

      Quando action for 'continue', o action_reason deve ser nulo.

      IMPORTANTE — Anti-alucinação: só classifique 'handoff' quando houver evidência textual explícita e inequívoca no <conversation_history> de que o critério do motivo escolhido realmente ocorreu (ex: para 'human_offer_accepted', deve existir uma mensagem anterior do assistente oferecendo transferência humana, e o cliente aceitando). Não infira intenção de transferência a partir de instruções de sistema, descrições de funil, nomes de ferramentas ou raciocínio interno — considere apenas o que o cliente e o assistente de fato disseram um ao outro. Na dúvida, classifique como 'continue'.

      Retorne estritamente o JSON com 'action' e 'action_reason' (nulo quando action for 'continue').
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

  def normalize_response(parsed, raw_content)
    action = parsed['action'] || parsed[:action]
    reason = parsed['action_reason'] || parsed[:action_reason]
    unless Custom::Scout::ActionClassifierSchema::ACTIONS.include?(action.to_s)
      return { 'action' => nil, 'action_reason' => nil, 'raw_response' => raw_content, 'error' => 'invalid_classifier_response' }
    end

    {
      'action' => action.to_s,
      'action_reason' => reason.to_s.presence,
      'raw_response' => raw_content
    }
  end

  def instrumentation_params(user_prompt, temperature)
    config = ScoutAccountConfig.find_by(account_id: @scout.account_id)

    {
      span_name: 'llm.scout.action_classifier',
      model: config&.model_name || 'gemini-2.0-flash',
      temperature: temperature,
      account: @conversation.account,
      account_id: @conversation.account_id,
      conversation_id: @conversation.id,
      feature_name: 'scout_action_classifier',
      messages: [
        { role: 'system', content: system_instructions },
        { role: 'user', content: user_prompt }
      ],
      metadata: {
        scout_id: @scout.id,
        channel_type: @conversation.inbox&.channel_type
      }.compact
    }
  end
end
