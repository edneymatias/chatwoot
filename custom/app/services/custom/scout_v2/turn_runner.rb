# frozen_string_literal: true

class Custom::ScoutV2::TurnRunner
  include Integrations::LlmInstrumentation
  include Custom::Scout::Tools::CallRecorder

  attr_reader :scout, :conversation, :message, :message_history

  def initialize(scout:, conversation:, message: nil, message_history: nil, playground: nil)
    @scout = scout
    @conversation = conversation
    @message_history = message_history
    @playground = playground.nil? ? !message_history.nil? : playground
    @message = message.presence || resolve_last_user_message_content
  end

  def perform
    return handle_infra_failure unless pre_call_checks_pass?

    catalog = Custom::ScoutV2::Playbook::Loader.load_all
    ctx = build_routing_context(catalog)
    decision = Custom::ScoutV2::Router.call(ctx, catalog)

    persist_state_activation_if_needed(decision, ctx)
    dispatch_turn(decision, ctx, catalog)
  end

  private

  def build_routing_context(catalog)
    Custom::ScoutV2::RoutingSnapshot::Builder.call(conversation: @conversation, catalog: catalog, turn_transition_count: 0)
  end

  def dispatch_turn(decision, ctx, catalog)
    chat = setup_chat(decision, ctx, catalog)
    last_user_message = resolve_last_user_message_record
    add_history_to_chat(chat, last_user_message)

    attachments = extract_attachment_urls(last_user_message)
    response = execute_chat(chat, decision, ctx, attachments)
    persist_unsatisfied_items!

    reply = response&.content.to_s
    if reply.blank?
      return handle_unreadable_output unless @turn_scope.ended?
      return { reply: I18n.t('conversations.scout.handoff'), tool_calls: recorded_tool_calls } if @turn_scope.escalated?
    end

    { reply: reply, tool_calls: recorded_tool_calls }
  end

  def playground?
    @playground == true
  end

  def pre_call_checks_pass?
    @scout.quota_available? && ScoutAccountConfig.find_by(account_id: @scout.account_id)&.api_key.present?
  end

  def handle_infra_failure
    error_msg = 'Quota esgotada ou chave de API ausente.'
    if playground?
      { reply: "Erro ao executar simulação: #{error_msg}", tool_calls: [], error: error_msg }
    else
      Custom::Scout::HandoffService.new(scout: @scout, conversation: @conversation).perform(message: nil, reason: error_msg)
      { reply: '', tool_calls: [] }
    end
  end

  def persist_state_activation_if_needed(decision, ctx)
    return unless decision.playbook.present? && decision.playbook != ctx.active_playbook

    conversation_state.record_state_activation!(decision.playbook.name)
  end

  def conversation_state
    @conversation_state ||= ScoutConversationState.for_conversation(@conversation)
  end

  def build_instructions(playbook, ctx, openable)
    blocks = [
      Custom::ScoutV2::Instructions::Builder.call(scout: @scout),
      Custom::ScoutV2::Playbook::IndexBuilder.call(openable),
      Custom::ScoutV2::Instructions::Builder::ESCALATION_SECTION
    ]
    blocks << Custom::ScoutV2::Playbook::ContentBuilder.call(playbook: playbook, ctx: ctx) if playbook.present?

    blocks.join("\n\n")
  end

  def setup_chat(decision, ctx, catalog)
    openable = Custom::ScoutV2::Playbook::OpenableSet.call(catalog: catalog, pinned: decision.playbook)
    baseline_instructions = build_instructions(nil, ctx, openable)
    instructions = decision.playbook.present? ? build_instructions(decision.playbook, ctx, openable) : baseline_instructions
    chat = @scout.llm_chat.with_instructions(instructions)

    # Wire real TurnScope with all initialization infrastructure
    tool_wrapper = proc { |tool| wrap_tool(tool, simulated: false) }
    scope = Custom::ScoutV2::TurnScope.new(
      chat: chat,
      catalog: catalog,
      baseline_instructions: baseline_instructions,
      tool_wrapper: tool_wrapper,
      playground: @playground
    )
    scope.setup_initial_tools!(decision: decision, ctx: ctx, scout: @scout, conversation: @conversation, openable: openable)
    @turn_scope = scope

    chat
  end

  def add_history_to_chat(chat, last_user_message)
    if @message_history.is_a?(Array)
      add_playground_history(chat)
    else
      add_inbox_history(chat, last_user_message)
    end
  end

  def add_playground_history(chat)
    @message_history.each do |msg|
      role = msg[:role].to_s == 'assistant' ? :assistant : :user
      chat.add_message(role: role, content: msg[:content].to_s) if msg[:content].present?
    end
  end

  def add_inbox_history(chat, last_user_message)
    conversation_messages.reject { |m| m.id == last_user_message&.id }.each do |msg|
      attachments = extract_attachment_urls(msg)
      content = attachments.any? ? RubyLLM::Content.new(msg.content.to_s, attachments) : msg.content.to_s
      chat.add_message(role: msg.incoming? ? :user : :assistant, content: content)
    end
  end

  def execute_chat(chat, decision, ctx, attachments)
    params = instrumentation_params(chat, @message, decision)

    instrument_agent_session(params) do
      response = instrument_llm_call(params) do
        attachments.any? ? chat.ask(@message, with: attachments) : chat.ask(@message)
      end
      @unsatisfied_items_record = Custom::ScoutV2::UnsatisfiedItems.trace!(
        playbook: @turn_scope.catalog[@turn_scope.active_procedure_name],
        conversation: @conversation,
        scout: @scout,
        ctx: ctx
      )
      response
    end
  end

  def persist_unsatisfied_items!
    return if @unsatisfied_items_record.blank?

    conversation_state.record_unsatisfied_items!(@unsatisfied_items_record)
  end

  def handle_unreadable_output
    error_msg = 'Resposta final do modelo vazia ou ilegível.'
    if playground?
      { reply: "Erro ao executar simulação: #{error_msg}", tool_calls: recorded_tool_calls, error: error_msg }
    else
      Custom::Scout::HandoffService.new(scout: @scout, conversation: @conversation).perform(message: nil, reason: error_msg)
      { reply: '', tool_calls: recorded_tool_calls }
    end
  end

  def instrumentation_params(chat, prompt_text, decision)
    config = ScoutAccountConfig.find_by(account_id: @scout.account_id)

    {
      span_name: 'llm.scout_v2.turn_runner',
      account: @conversation.account,
      account_id: @conversation.account_id,
      conversation_id: @conversation.id,
      feature_name: 'scout_v2_turn_runner',
      model: config&.model_name || 'gemini-2.0-flash',
      messages: chat_message_history(chat, prompt_text),
      metadata: metadata_for(decision)
    }
  end

  def metadata_for(decision)
    activation_reason = decision.playbook.present? ? conversation_state.activation_reason : nil

    {
      scout_id: @scout.id,
      playbook: decision.playbook&.name,
      activation_reason: activation_reason
    }.compact
  end

  def chat_message_history(chat, prompt_text = nil)
    history = chat.respond_to?(:messages) && chat.messages.present? ? chat.messages.map { |m| { role: m.role.to_s, content: m.content.to_s } } : []
    history << { role: 'user', content: prompt_text.to_s } if prompt_text.present?
    history
  end

  def conversation_messages
    @conversation.messages.where(private: false, message_type: %i[incoming outgoing]).reorder(created_at: :asc, id: :asc).to_a
  end

  def resolve_last_user_message_record
    return nil if playground?

    msgs = conversation_messages
    msgs.reverse.find(&:incoming?) || msgs.last
  end

  def resolve_last_user_message_content
    resolve_last_user_message_record&.content.presence || 'Mensagem recebida.'
  end

  def extract_attachment_urls(message)
    return [] if message.blank? || !message.respond_to?(:attachments)

    message.attachments.where(file_type: %i[image audio]).filter_map do |a|
      a.download_url.presence || a.external_url.presence || (a.file.attached? ? a.file_url : nil)
    end
  end
end
