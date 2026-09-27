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

    { reply: response&.content.to_s, tool_calls: recorded_tool_calls }
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
      Custom::ScoutV2::Playbook::IndexBuilder.call(openable)
    ]

    if playbook.present?
      body = playbook.body.strip
      pending = Custom::ScoutV2::Playbook::PendingFieldsFormatter.call(account_id: @conversation.account_id, pending_keys: ctx.pending_fields)
      blocks << (pending.present? ? "#{body}\n\n#{pending}" : body)
    end

    blocks.join("\n\n")
  end

  def setup_chat(decision, ctx, catalog)
    openable = Custom::ScoutV2::Playbook::OpenableSet.call(catalog: catalog, pinned: decision.playbook)
    chat = @scout.llm_chat.with_instructions(build_instructions(decision.playbook, ctx, openable))
    build_tools(decision, openable, chat).each { |tool| chat.with_tool(wrap_tool(tool, simulated: false)) }
    chat
  end

  # open_playbook is offered iff the openable set is non-empty (FR-004) — the full catalog when no procedure is pinned,
  # or situational playbooks when a procedure is pinned; it keeps the live chat so its tools join the same chat.ask loop.
  def build_tools(decision, openable, chat)
    always_on_tools = [Custom::Scout::Tools::SearchKnowledgeBase.new(@scout, @conversation, playground: false)]
    tools = always_on_tools.dup
    tools.concat(Custom::ScoutV2::Tools::Registry.build(decision.playbook.tools, scout: @scout, conversation: @conversation)) if decision.playbook
    if openable.any?
      turn_setup = Custom::ScoutV2::Tools::OpenPlaybook::TurnSetup.new(
        baseline_instructions: build_instructions(nil, nil, openable),
        baseline_tools: always_on_tools,
        tool_wrapper: ->(tool) { wrap_tool(tool, simulated: false) }
      )
      tools << Custom::ScoutV2::Tools::OpenPlaybook.new(
        @scout, @conversation, chat: chat, openable: openable, turn_setup: turn_setup
      )
    end
    tools
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
    params = instrumentation_params(chat, @message, decision, ctx)

    instrument_agent_session(params) do
      instrument_llm_call(params) do
        attachments.any? ? chat.ask(@message, with: attachments) : chat.ask(@message)
      end
    end
  end

  def instrumentation_params(chat, prompt_text, decision, ctx)
    config = ScoutAccountConfig.find_by(account_id: @scout.account_id)

    {
      span_name: 'llm.scout_v2.turn_runner',
      account: @conversation.account,
      account_id: @conversation.account_id,
      conversation_id: @conversation.id,
      feature_name: 'scout_v2_turn_runner',
      model: config&.model_name || 'gemini-2.0-flash',
      messages: chat_message_history(chat, prompt_text),
      metadata: metadata_for(decision, ctx)
    }
  end

  def metadata_for(decision, ctx)
    unsatisfied = {
      pending_fields: ctx.pending_fields,
      unmet_requires: (decision.playbook&.requires || []) - ctx.satisfied_capabilities
    }

    activation_reason = decision.playbook.present? ? conversation_state.activation_reason : nil

    {
      scout_id: @scout.id,
      playbook: decision.playbook&.name,
      activation_reason: activation_reason,
      unsatisfied_flags: unsatisfied
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
