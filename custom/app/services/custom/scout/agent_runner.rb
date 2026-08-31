# frozen_string_literal: true

class Custom::Scout::AgentRunner
  include Integrations::LlmInstrumentation
  include Custom::Scout::Tools::CallRecorder

  attr_reader :scout, :conversation, :account, :inbox, :contact

  def initialize(scout:, conversation:)
    @scout = scout
    @conversation = conversation
    @account = conversation.account
    @inbox = conversation.inbox
    @contact = conversation.contact
  end

  def perform
    return if @conversation.blank? || !conversation_pending?

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
    @scout.quota_available? && ScoutAccountConfig.find_by(account_id: @scout.account_id)&.api_key.present?
  end

  def perform_fail_safe_handoff(reason = nil)
    return unless conversation_pending?

    Messages::MessageBuilder.new(
      nil, @conversation, { content: I18n.t('conversations.scout.handoff', locale: conversation_locale), message_type: 'outgoing', private: false }
    ).perform
    @conversation.bot_handoff!
    alert_suffix = reason.present? ? ". Motivo: #{reason}" : ' devido a esgotamento de saldo/limite de API.'
    Messages::MessageBuilder.new(
      nil, @conversation, { content: "⚠️ [IA Pausada]: A conversa foi transferida para atendimento humano#{alert_suffix}", private: true }
    ).perform
    Custom::Scout::ContactNotesService.new(@scout, @conversation).generate_and_update_notes if @scout.feature_memory?
  end

  def generate_and_process_response
    tools = build_tools
    chat = setup_chat(tools)
    history = conversation_messages
    last_user_message = history.reverse.find(&:incoming?) || history.last
    add_history_to_chat(chat, history, last_user_message)
    response = execute_chat(chat, last_user_message)
    process_response(response, tools, chat: chat)
  end

  def setup_chat(tools)
    chat = @scout.llm_chat.with_schema(Custom::Scout::ResponseSchema).with_instructions(build_system_instructions)
    tools.reduce(chat) { |c, tool| c.with_tool(tool) }
  end

  def process_response(response, tools, chat: nil)
    return unless conversation_pending?

    parsed = parse_structured_response(response&.content)
    return perform_fail_safe_handoff('Falha ao interpretar resposta estruturada do modelo.') if parsed.blank?

    process_audited_reply(parsed[:response], tools, chat)
  end

  def process_audited_reply(reply_text, tools, chat)
    if @scout.feature_response_auditor?
      audit_result = Custom::Scout::ResponseAuditor.new(scout: @scout, conversation: @conversation).audit(
        chat: chat, response_text: reply_text, message_history: audit_message_history(chat), recorded_tool_calls: recorded_tool_calls
      )
      return if handle_auditor_non_proceed(audit_result)

      reply_text = audit_result[:reply]
    end

    tool = handoff_requested_tool(tools)
    return trigger_handoff(tool, reply_text) if tool.present?

    dispatch_outgoing_reply(reply_text)
  end

  def handle_auditor_non_proceed(audit_result)
    return true if audit_result[:action] == :handoff

    if audit_result[:action] == :escalate
      perform_fail_safe_handoff(audit_result[:reason] || 'Resposta inconsistente com as ações executadas.')
      return true
    end

    false
  end

  def handoff_requested_tool(tools)
    tools.find { |tool| tool.respond_to?(:handoff_needed) && tool.handoff_needed }
  end

  def trigger_handoff(tool, reply_text)
    Custom::Scout::HandoffService.new(scout: @scout, conversation: @conversation).perform(
      message: reply_text, assignee_id: handoff_param(tool, :handoff_assignee_id),
      team_id: handoff_param(tool, :handoff_team_id),
      reason: handoff_param(tool, :handoff_reason) || 'Oportunidade movida para o estágio qualificado'
    )
  end

  def handoff_param(tool, method_name)
    tool.public_send(method_name) if tool.respond_to?(method_name)
  end

  def parse_structured_response(content)
    return nil if content.blank?

    hash = content.is_a?(Hash) ? content : parse_json(content)
    return nil if hash.blank? || (hash['response'].blank? && hash[:response].blank?)

    Rails.logger.info "[Scout AgentRunner] reasoning: #{hash['reasoning'] || hash[:reasoning]}"
    { response: hash['response'] || hash[:response] }
  end

  def parse_json(content)
    sanitized = content.to_s.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
    JSON.parse(sanitized)
  rescue JSON::ParserError => e
    Rails.logger.warn "[Scout AgentRunner] JSON parsing failed: #{e.message} | raw content: #{content}"
    nil
  end

  def build_tools
    [
      Custom::Scout::Tools::ManageOpportunity.new(@scout, @conversation),
      Custom::Scout::Tools::MoveOpportunityStage.new(@scout, @conversation),
      Custom::Scout::Tools::UpdateContact.new(@scout, @conversation),
      Custom::Scout::Tools::CreatePrivateNote.new(@scout, @conversation),
      Custom::Scout::Tools::HandoverToHuman.new(@scout, @conversation),
      Custom::Scout::Tools::CallCustomApi.new(@scout, @conversation),
      Custom::Scout::Tools::SearchKnowledgeBase.new(@scout, @conversation)
    ].map { |tool| wrap_tool(tool, simulated: false) }
  end

  def build_system_instructions
    catalog = "Catálogo de Produtos e Ofertas:\n#{@scout.product_catalog.to_json}" if @scout.product_catalog.present? && @scout.product_catalog != {}
    Custom::Scout::SystemPromptsService.build(
      scout: @scout, contact: @contact, inbox: @inbox,
      catalog_instructions: catalog, knowledge_available: @scout.scout_knowledge_sources.ready.exists?
    )
  end

  def conversation_messages
    @conversation.messages.where(private: false, message_type: %i[incoming outgoing]).reorder(created_at: :asc, id: :asc).to_a
  end

  def add_history_to_chat(chat, messages, last_message)
    messages.reject { |m| m.id == last_message&.id }.each do |msg|
      attachments = extract_attachment_urls(msg)
      content = attachments.any? ? RubyLLM::Content.new(msg.content.to_s, attachments) : msg.content.to_s
      chat.add_message(role: msg.incoming? ? :user : :assistant, content: content)
    end
  end

  def execute_chat(chat, last_message)
    prompt_text = last_message&.content.presence || 'Mensagem recebida.'
    attachments = extract_attachment_urls(last_message)
    params = instrumentation_params(chat, prompt_text)

    instrument_agent_session(params) do
      instrument_llm_call(params) { attachments.any? ? chat.ask(prompt_text, with: attachments) : chat.ask(prompt_text) }
    end
  end

  def chat_message_history(chat, prompt_text = nil)
    messages = chat.respond_to?(:messages) && chat.messages.present? ? chat.messages.map { |m| { role: m.role.to_s, content: m.content.to_s } } : []
    messages << { role: 'user', content: prompt_text.to_s } if prompt_text.present?
    messages
  end

  # The auditor's "conversation history" must only contain actual customer/assistant/tool turns —
  # RubyLLM's chat.messages also carries the system instructions as a role: :system entry, and
  # dumping the full system prompt (which itself discusses handoff criteria/stage descriptions) into
  # the classifier/consistency-check prompt as if it were part of the conversation caused it to
  # misread guardrail text as evidence of an actual handoff-related exchange.
  def audit_message_history(chat)
    chat_message_history(chat).reject { |m| m[:role] == 'system' }
  end

  def instrumentation_params(chat, prompt_text)
    messages = chat_message_history(chat, prompt_text)
    config = ScoutAccountConfig.find_by(account_id: @scout.account_id)

    {
      span_name: 'llm.scout.agent_runner', account: @account, account_id: @account.id, conversation_id: @conversation.id,
      feature_name: 'scout_agent_runner', model: config&.model_name || 'gemini-2.0-flash', messages: messages,
      metadata: { scout_id: @scout.id, channel_type: @inbox&.channel_type }.compact
    }
  end

  def extract_attachment_urls(message)
    return [] if message.blank?

    message.attachments.where(file_type: %i[image audio]).filter_map do |a|
      a.download_url.presence || a.external_url.presence || (a.file.attached? ? a.file_url : nil)
    end
  end

  def dispatch_outgoing_reply(reply_content)
    Messages::MessageBuilder.new(nil, @conversation, { content: reply_content, message_type: 'outgoing', private: false }).perform
    @scout.with_lock { @scout.update!(responses_consumed: @scout.responses_consumed + 1) }
  end
end
