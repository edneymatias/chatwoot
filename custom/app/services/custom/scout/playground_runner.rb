# frozen_string_literal: true

class Custom::Scout::PlaygroundRunner
  attr_reader :scout, :message, :recorded_tool_calls

  def initialize(scout:, message:)
    @scout = scout
    @message = message
    @recorded_tool_calls = []
  end

  def perform
    tools = build_tools
    chat = @scout.llm_chat
    chat.with_instructions(build_system_instructions)
    tools.each { |tool| chat = chat.with_tool(tool) }

    response = chat.ask(@message)

    {
      reply: response&.content.to_s,
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

  def build_tools
    raw_tools = [
      Custom::Scout::Tools::ManageOpportunity.new(@scout, nil, playground: true),
      Custom::Scout::Tools::MoveOpportunityStage.new(@scout, nil, playground: true),
      Custom::Scout::Tools::UpdateContact.new(@scout, nil, playground: true),
      Custom::Scout::Tools::CreatePrivateNote.new(@scout, nil, playground: true),
      Custom::Scout::Tools::HandoverToHuman.new(@scout, nil, playground: true),
      Custom::Scout::Tools::CallCustomApi.new(@scout, nil, playground: true)
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
    parts = []
    parts << @scout.system_prompt if @scout.system_prompt.present?
    parts << build_catalog_instructions
    parts << build_knowledge_instructions
    parts.compact.join("\n\n")
  end

  def build_catalog_instructions
    return if @scout.product_catalog.blank? || @scout.product_catalog == {}

    "Catálogo de Produtos e Ofertas:\n#{@scout.product_catalog.to_json}"
  end

  def build_knowledge_instructions
    entries = @scout.scout_knowledge_sources.where(status: :ready).filter_map do |src|
      format_knowledge_source(src)
    end

    if entries.any?
      "Base de Conhecimento:\n#{entries.join("\n---\n")}"
    elsif @scout.respond_to?(:knowledge_sources) && @scout.knowledge_sources.present? && @scout.knowledge_sources != {}
      "Base de Conhecimento:\n#{@scout.knowledge_sources.to_json}"
    end
  end

  def format_knowledge_source(src)
    case src.kind.to_sym
    when :faq
      "FAQ:\nP: #{src.question}\nR: #{src.answer}"
    when :url
      "URL (#{src.url}):\n#{src.content}"
    when :document
      filename = src.document_file.attached? ? src.document_file.filename : 'Document'
      "Documento (#{filename}):\n#{src.content}"
    end
  end
end
