# frozen_string_literal: true

class Custom::Scout::AgentRunner
  include Integrations::LlmInstrumentation

  attr_reader :scout, :conversation, :account, :inbox, :contact

  def initialize(scout:, conversation:)
    @scout = scout
    @conversation = conversation
    @account = conversation.account
    @inbox = conversation.inbox
    @contact = conversation.contact
  end

  def perform
    return if @conversation.blank?
    return unless conversation_pending?

    unless pre_call_checks_pass?
      perform_fail_safe_handoff('Quota esgotada ou chave de API ausente.')
      return
    end

    generate_and_process_response
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    Rails.logger.error "[Scout AgentRunner] Error: #{e.message}\n#{e.backtrace&.join("\n")}"
    perform_fail_safe_handoff("Erro durante execução do assistente: #{e.message}")
  end

  private

  def conversation_locale
    @conversation.language.presence || @account.locale.presence || I18n.default_locale.to_s
  end

  def conversation_pending?
    status = Conversation.uncached { Conversation.where(id: @conversation.id).pick(:status) }
    status == 'pending' || status == Conversation.statuses[:pending]
  end

  def pre_call_checks_pass?
    return false unless @scout.quota_available?

    config = ScoutAccountConfig.find_by(account_id: @scout.account_id)
    config&.api_key.present?
  end

  def perform_fail_safe_handoff(reason = nil)
    return unless conversation_pending?

    handoff_params = { content: I18n.t('conversations.scout.handoff', locale: conversation_locale), message_type: 'outgoing', private: false }
    Messages::MessageBuilder.new(nil, @conversation, handoff_params).perform

    @conversation.bot_handoff!
    alert_suffix = reason.present? ? ". Motivo: #{reason}" : ' devido a esgotamento de saldo/limite de API.'
    alert_content = "⚠️ [IA Pausada]: A conversa foi transferida para atendimento humano#{alert_suffix}"
    Messages::MessageBuilder.new(nil, @conversation, { content: alert_content, private: true }).perform

    Custom::Scout::ContactNotesService.new(@scout, @conversation).generate_and_update_notes if @scout.feature_memory?
  end

  def generate_and_process_response
    tools, handover_tool = build_tools
    chat = @scout.llm_chat
    chat = chat.with_schema(Custom::Scout::ResponseSchema)
    chat.with_instructions(build_system_instructions)
    tools.each { |tool| chat = chat.with_tool(tool) }

    history_messages = conversation_messages
    last_user_message = history_messages.reverse.find(&:incoming?) || history_messages.last
    add_history_to_chat(chat, history_messages, last_user_message)

    response = execute_chat(chat, last_user_message)
    process_response(response, handover_tool, tools)
  end

  def process_response(response, handover_tool, tools)
    return if handover_tool.handoff_executed
    return unless conversation_pending?

    parsed = parse_structured_response(response&.content)
    if parsed.blank?
      perform_fail_safe_handoff('Falha ao interpretar resposta estruturada do modelo.')
      return
    end

    dispatch_outgoing_reply(parsed[:response])
    trigger_qualification_handoff if qualification_handoff_needed?(tools)
  end

  def qualification_handoff_needed?(tools)
    tools.any? { |tool| tool.respond_to?(:handoff_needed) && tool.handoff_needed }
  end

  def trigger_qualification_handoff
    service = Custom::Scout::HandoffService.new(scout: @scout, conversation: @conversation)
    service.perform(reason: 'Oportunidade movida para o estágio qualificado')
  end

  def parse_structured_response(content)
    if content.blank?
      Rails.logger.warn '[Scout AgentRunner] Structured response parsing failed: content is blank'
      return nil
    end

    return parse_structured_hash(content) if content.is_a?(Hash)

    parse_structured_json_string(content)
  end

  def parse_structured_hash(hash)
    response_text = hash['response'] || hash[:response]
    if response_text.blank?
      Rails.logger.warn "[Scout AgentRunner] Structured response missing 'response' key: #{hash.inspect}"
      return nil
    end

    reasoning_text = hash['reasoning'] || hash[:reasoning]
    Rails.logger.info "[Scout AgentRunner] reasoning: #{reasoning_text}"
    { response: response_text }
  end

  def parse_structured_json_string(content)
    sanitized = content.to_s.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
    json = JSON.parse(sanitized)
    if json['response'].blank?
      Rails.logger.warn "[Scout AgentRunner] Structured response missing 'response' key: #{sanitized}"
      return nil
    end

    Rails.logger.info "[Scout AgentRunner] reasoning: #{json['reasoning']}"
    { response: json['response'] }
  rescue JSON::ParserError => e
    Rails.logger.warn "[Scout AgentRunner] JSON parsing failed: #{e.message} | raw content: #{content}"
    nil
  end

  def build_tools
    tools = [
      Custom::Scout::Tools::ManageOpportunity.new(@scout, @conversation),
      Custom::Scout::Tools::MoveOpportunityStage.new(@scout, @conversation),
      Custom::Scout::Tools::UpdateContact.new(@scout, @conversation),
      Custom::Scout::Tools::CreatePrivateNote.new(@scout, @conversation),
      (handover = Custom::Scout::Tools::HandoverToHuman.new(@scout, @conversation)),
      Custom::Scout::Tools::CallCustomApi.new(@scout, @conversation),
      Custom::Scout::Tools::SearchKnowledgeBase.new(@scout, @conversation)
    ]
    [tools, handover]
  end

  def build_system_instructions
    Custom::Scout::SystemPromptsService.build(
      scout: @scout,
      contact: @contact,
      inbox: @inbox,
      catalog_instructions: build_catalog_instructions,
      knowledge_available: @scout.scout_knowledge_sources.ready.exists?
    )
  end

  def build_catalog_instructions
    return if @scout.product_catalog.blank? || @scout.product_catalog == {}

    "Catálogo de Produtos e Ofertas:\n#{@scout.product_catalog.to_json}"
  end

  def conversation_messages
    @conversation.messages.where(private: false, message_type: %i[incoming outgoing]).reorder(created_at: :asc, id: :asc).to_a
  end

  def add_history_to_chat(chat, messages, last_message)
    prior_messages = messages.reject { |m| m.id == last_message&.id }
    prior_messages.each do |msg|
      role = msg.incoming? ? :user : :assistant
      attachments = extract_attachment_urls(msg)
      content = attachments.any? ? RubyLLM::Content.new(msg.content.to_s, attachments) : msg.content.to_s
      chat.add_message(role: role, content: content)
    end
  end

  def execute_chat(chat, last_message)
    prompt_text = last_message&.content.presence || 'Mensagem recebida.'
    attachments = extract_attachment_urls(last_message)
    params = instrumentation_params(chat, prompt_text)

    instrument_agent_session(params) do
      instrument_llm_call(params) do
        attachments.any? ? chat.ask(prompt_text, with: attachments) : chat.ask(prompt_text)
      end
    end
  end

  def instrumentation_params(chat, prompt_text)
    messages = chat.respond_to?(:messages) && chat.messages.present? ? chat.messages.map { |m| { role: m.role.to_s, content: m.content.to_s } } : []
    messages << { role: 'user', content: prompt_text.to_s }
    config = ScoutAccountConfig.find_by(account_id: @scout.account_id)

    {
      span_name: 'llm.scout.agent_runner', account: @account, account_id: @account.id, conversation_id: @conversation.id,
      feature_name: 'scout_agent_runner', model: config&.model_name || 'gemini-2.0-flash', messages: messages,
      metadata: { scout_id: @scout.id, channel_type: @inbox&.channel_type }.compact
    }
  end

  def extract_attachment_urls(message)
    return [] if message.blank?

    message.attachments.where(file_type: %i[image audio]).filter_map do |attachment|
      attachment.download_url.presence || attachment.external_url.presence || (attachment.file.attached? ? attachment.file_url : nil)
    end
  end

  def dispatch_outgoing_reply(reply_content)
    Messages::MessageBuilder.new(nil, @conversation, { content: reply_content, message_type: 'outgoing', private: false }).perform
    @scout.with_lock { @scout.update!(responses_consumed: @scout.responses_consumed + 1) }
  end
end
