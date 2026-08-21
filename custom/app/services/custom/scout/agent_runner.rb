# frozen_string_literal: true

class Custom::Scout::AgentRunner
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

    @conversation.bot_handoff!
    alert_content = if reason.present?
                      "⚠️ [IA Pausada]: A conversa foi transferida para atendimento humano. Motivo: #{reason}"
                    else
                      '⚠️ [IA Pausada]: A conversa foi transferida para atendimento humano devido a esgotamento de saldo/limite de API.'
                    end
    Messages::MessageBuilder.new(nil, @conversation, { content: alert_content, private: true }).perform

    Custom::Scout::ContactNotesService.new(@scout, @conversation).generate_and_update_notes if @scout.feature_memory?
  end

  def generate_and_process_response
    tools, handover_tool = build_tools
    chat = @scout.llm_chat
    chat.with_instructions(build_system_instructions)
    tools.each { |tool| chat = chat.with_tool(tool) }

    history_messages = conversation_messages
    last_user_message = history_messages.reverse.find(&:incoming?) || history_messages.last
    add_history_to_chat(chat, history_messages, last_user_message)

    response = execute_chat(chat, last_user_message)
    process_response(response, handover_tool)
  end

  def process_response(response, handover_tool)
    return if handover_tool.handoff_executed
    return unless conversation_pending?

    parsed = parse_structured_response(response&.content)
    if parsed.blank?
      perform_fail_safe_handoff('Falha ao interpretar resposta estruturada do modelo.')
      return
    end

    dispatch_outgoing_reply(parsed[:response])
  end

  def parse_structured_response(content)
    if content.blank?
      Rails.logger.warn '[Scout AgentRunner] Structured response parsing failed: content is blank'
      return nil
    end

    sanitized = content.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
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
    manage_opp = Custom::Scout::Tools::ManageOpportunity.new(@scout, @conversation)
    move_stage = Custom::Scout::Tools::MoveOpportunityStage.new(@scout, @conversation)
    update_contact = Custom::Scout::Tools::UpdateContact.new(@scout, @conversation)
    create_note = Custom::Scout::Tools::CreatePrivateNote.new(@scout, @conversation)
    handover = Custom::Scout::Tools::HandoverToHuman.new(@scout, @conversation)
    call_custom_api = Custom::Scout::Tools::CallCustomApi.new(@scout, @conversation)
    search_kb = Custom::Scout::Tools::SearchKnowledgeBase.new(@scout, @conversation)

    [[manage_opp, move_stage, update_contact, create_note, handover, call_custom_api, search_kb], handover]
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
    @conversation.messages
                 .where(private: false, message_type: %i[incoming outgoing])
                 .reorder(created_at: :asc, id: :asc)
                 .to_a
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

    if attachments.any?
      chat.ask(prompt_text, with: attachments)
    else
      chat.ask(prompt_text)
    end
  end

  def extract_attachment_urls(message)
    return [] if message.blank?

    message.attachments.where(file_type: %i[image audio]).filter_map do |attachment|
      attachment.download_url.presence ||
        attachment.external_url.presence ||
        (attachment.file.attached? ? attachment.file_url : nil)
    end
  end

  def dispatch_outgoing_reply(reply_content)
    params = { content: reply_content, message_type: 'outgoing', private: false }
    Messages::MessageBuilder.new(nil, @conversation, params).perform

    @scout.with_lock do
      @scout.update!(responses_consumed: @scout.responses_consumed + 1)
    end
  end
end
