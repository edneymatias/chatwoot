# frozen_string_literal: true

class Custom::Scout::PlaygroundRunner
  attr_reader :scout, :message, :message_history, :recorded_tool_calls

  def initialize(scout:, message:, message_history: [])
    @scout = scout
    @message = message
    @message_history = message_history || []
    @recorded_tool_calls = []
  end

  def perform
    tools = build_tools
    chat = @scout.llm_chat
    chat.with_instructions(build_system_instructions)
    tools.each { |tool| chat = chat.with_tool(tool) }

    add_history_to_chat(chat)
    response = chat.ask(@message)
    reply_text = extract_reply_content(response&.content)

    {
      reply: reply_text,
      tool_calls: @recorded_tool_calls
    }
  rescue StandardError => e
    Rails.logger.error "[Scout PlaygroundRunner] Error: #{e.message}\n#{e.backtrace&.join("\n")}"
    {
      reply: "Erro ao executar simulação: #{e.message}",
      tool_calls: @recorded_tool_calls,
      error: e.message
    }
  end

  private

  def add_history_to_chat(chat)
    @message_history.each do |msg|
      role = msg[:role].to_s == 'assistant' ? :assistant : :user
      content = msg[:content].to_s
      chat.add_message(role: role, content: content) if content.present?
    end
  end

  def extract_reply_content(content)
    return '' if content.blank?

    sanitized = content.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
    json = JSON.parse(sanitized)
    json['response'].presence || content
  rescue JSON::ParserError
    content
  end

  def build_tools
    raw_tools = [
      Custom::Scout::Tools::ManageOpportunity.new(@scout, nil, playground: true),
      Custom::Scout::Tools::MoveOpportunityStage.new(@scout, nil, playground: true),
      Custom::Scout::Tools::UpdateContact.new(@scout, nil, playground: true),
      Custom::Scout::Tools::CreatePrivateNote.new(@scout, nil, playground: true),
      Custom::Scout::Tools::HandoverToHuman.new(@scout, nil, playground: true),
      Custom::Scout::Tools::CallCustomApi.new(@scout, nil, playground: true),
      Custom::Scout::Tools::SearchKnowledgeBase.new(@scout, nil, playground: true)
    ]

    raw_tools.map { |tool| wrap_tool(tool) }
  end

  def wrap_tool(tool)
    original_execute = tool.method(:execute)
    runner = self

    tool.define_singleton_method(:execute) do |**args|
      runner.send(:execute_and_record, tool.name, original_execute, args)
    end

    tool
  end

  def execute_and_record(tool_name, original_execute, args)
    call_record = { tool_name: tool_name, arguments: args, simulated: tool_name != 'call_custom_api' }
    begin
      result = original_execute.call(**args)
      call_record[:result] = result
      result
    rescue StandardError => e
      call_record[:error] = e.message
      raise e
    ensure
      @recorded_tool_calls << call_record
    end
  end

  def build_system_instructions
    Custom::Scout::SystemPromptsService.build(
      scout: @scout,
      catalog_instructions: build_catalog_instructions,
      knowledge_available: @scout.scout_knowledge_sources.ready.exists?
    )
  end

  def build_catalog_instructions
    return if @scout.product_catalog.blank? || @scout.product_catalog == {}

    "Catálogo de Produtos e Ofertas:\n#{@scout.product_catalog.to_json}"
  end
end
