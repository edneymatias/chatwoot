# frozen_string_literal: true

class Custom::Scout::ClaimConsistencyService
  include Integrations::LlmInstrumentation

  def initialize(scout:, conversation:)
    @scout = scout
    @conversation = conversation
    @account = conversation.account
  end

  def check(message_history:, assistant_response:, recorded_tool_calls: [], available_tool_names: [])
    user_prompt = build_user_prompt(message_history, assistant_response, recorded_tool_calls, available_tool_names)

    response = instrument_llm_call(instrumentation_params(user_prompt)) do
      @scout.llm_chat(temperature: 0.0)
            .with_schema(Custom::Scout::ClaimConsistencySchema)
            .with_instructions(system_instructions)
            .ask(user_prompt)
    end

    parsed = parse_response(response&.content)
    normalize_response(parsed, response&.content)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @scout.account).capture_exception
    Rails.logger.warn(
      "[Scout][ClaimConsistency] Failed for conversation #{@conversation.id}: #{e.class.name}: #{e.message}"
    )
    { 'decision' => nil, 'reason' => nil, 'error' => e.message }
  end

  private

  def build_user_prompt(message_history, assistant_response, recorded_tool_calls, available_tool_names)
    <<~PROMPT
      <conversation_history>
      #{format_message_history(message_history)}
      </conversation_history>

      <available_tools>
      #{format_available_tools(available_tool_names)}
      </available_tools>

      <recorded_tool_calls>
      #{format_recorded_tools(recorded_tool_calls)}
      </recorded_tool_calls>

      <assistant_response_to_check>
      #{assistant_response}
      </assistant_response_to_check>

      Analise se a resposta do assistente (<assistant_response_to_check>) é consistente com o histórico da conversa e com as ferramentas realmente executadas (<recorded_tool_calls>), considerando apenas as ferramentas listadas em <available_tools>.
    PROMPT
  end

  def format_available_tools(available_tool_names)
    return 'Nenhuma ferramenta disponível informada.' if available_tool_names.blank?

    available_tool_names.join(', ')
  end

  def format_message_history(message_history)
    (message_history || []).map do |msg|
      role = msg[:role] || msg['role']
      content = msg[:content] || msg['content']
      "[#{role.to_s.upcase}]: #{content}"
    end.join("\n")
  end

  def format_recorded_tools(recorded_tool_calls)
    return 'Nenhuma ferramenta foi executada neste turno.' if recorded_tool_calls.blank?

    recorded_tool_calls.map.with_index(1) do |tool, idx|
      status = tool[:error].present? ? "FAILED (Error: #{tool[:error]})" : "SUCCESS (Result: #{tool[:result].to_json})"
      "#{idx}. Tool: #{tool[:tool_name]} | Args: #{tool[:arguments].to_json} | Status: #{status}"
    end.join("\n")
  end

  def system_instructions
    <<~INSTRUCTIONS
      Você é um auditor de consistência de respostas para um assistente de IA de vendas (Scout).
      Sua tarefa é avaliar se a resposta rascunhada pelo assistente para o cliente é factual e coerente com as ações efetivamente executadas no turno atual.

      Diretrizes de Classificação:
      1. 'safe': A resposta é totalmente consistente. Ela não faz promessas de ações futuras não cumpridas, nem afirma falsamente que uma ação já foi realizada. Respostas comuns de conversa, dúvidas ou respostas cujas ações foram executadas com sucesso pelas ferramentas são 'safe'.
      2. 'false_completed_action': A resposta afirma ou sugere que uma ação (ex: atualização de oportunidade, mudança de estágio no pipeline, atualização de contato, envio de dados) já foi concluída, mas nenhuma ferramenta correspondente foi executada com sucesso neste turno (ou a ferramenta foi chamada e falhou/retornou erro).
      3. 'false_promise': A resposta promete que realizará uma ação futura (ex: transferir para atendente humano, verificar informações, enviar notificação posterior) sem que a ferramenta necessária tenha sido acionada.

      IMPORTANTE — Não presuma ferramentas inexistentes: este assistente é configurável por conta e cada uma tem seu próprio conjunto de ferramentas — o que conta como "ação concluída" varia de negócio para negócio (agendar uma avaliação, marcar uma reunião, registrar um interesse, disparar um e-mail, etc.). Avalie a consistência somente em relação às ferramentas listadas em <available_tools>. Nunca classifique como 'false_completed_action' ou 'false_promise' presumindo a existência de uma ferramenta mais específica ou completa (ex: uma integração de agenda, envio de e-mail, sistema externo) que não esteja entre as disponíveis. Se a ação relatada na resposta corresponde ao que as ferramentas realmente disponíveis são capazes de fazer — mesmo que de forma mais simples do que um sistema externo faria (ex: apenas registrar um dado como preferência do cliente, em vez de executar a ação final por completo) — e a resposta não afirma algo além disso (ex: não afirma que um horário específico foi confirmado quando só a data foi registrada), isso é 'safe'.

      Retorne estritamente o JSON no formato definido pelo schema, contendo 'decision' e 'reason'.
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
    decision = parsed['decision'] || parsed[:decision]
    reason = parsed['reason'] || parsed[:reason]
    unless Custom::Scout::ClaimConsistencySchema::DECISIONS.include?(decision.to_s)
      return { 'decision' => nil, 'reason' => nil, 'raw_response' => raw_content, 'error' => 'invalid_consistency_decision' }
    end

    {
      'decision' => decision.to_s,
      'reason' => reason.to_s.presence,
      'raw_response' => raw_content
    }
  end

  def instrumentation_params(user_prompt)
    config = ScoutAccountConfig.find_by(account_id: @scout.account_id)

    {
      span_name: 'llm.scout.claim_consistency_detector',
      model: config&.model_name || 'gemini-2.0-flash',
      temperature: 0.0,
      account: @conversation.account,
      account_id: @conversation.account_id,
      conversation_id: @conversation.id,
      feature_name: 'scout_claim_consistency_detector',
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
