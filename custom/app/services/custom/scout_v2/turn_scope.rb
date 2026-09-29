# frozen_string_literal: true

class Custom::ScoutV2::TurnScope
  TURN_ENDED_ERROR = 'O turno já foi encerrado por um exit. Nenhuma outra ação é executada; escreva apenas a resposta final ao cliente.'

  attr_reader :catalog, :transitions, :ctx
  attr_accessor :active_procedure_name

  def initialize(chat:, catalog:, baseline_instructions:, tool_wrapper:, playground: false)
    @chat = chat
    @catalog = catalog
    @baseline_instructions = baseline_instructions
    @tool_wrapper = tool_wrapper
    @playground = playground == true
    @baseline_tools = []
    @wrapped_tools = {}
    @ended = false
    @escalated = false
    @transitions = 0
    @active_procedure_name = nil
  end

  def playground?
    @playground
  end

  def ended?
    @ended
  end

  def escalated?
    @escalated
  end

  def procedure_in_turn?
    @active_procedure_name.present?
  end

  def end_turn!(escalated: false)
    @ended = true
    @escalated = true if escalated
  end

  def record_transition!
    @transitions += 1
  end

  def add_baseline(tool)
    @baseline_tools << tool
  end

  def register(tools)
    Array(tools).each do |tool|
      @chat.with_tool(wrap(tool))
    end
  end

  def replace_with_baseline!(tools)
    @chat.with_instructions(@baseline_instructions)
    all_tools = (@baseline_tools + Array(tools)).map { |tool| wrap(tool) }
    @chat.with_tools(*all_tools, replace: true)
  end

  def actions_for(playbook, scout:, conversation:)
    tools = Custom::ScoutV2::Tools::Registry.build(playbook.tools, scout: scout, conversation: conversation)
    requires_satisfied = (playbook.requires || []).all? do |req|
      (@ctx&.satisfied_capabilities || []).include?(req)
    end

    return tools unless requires_satisfied

    exits = playbook.exits.values.map do |exit_decl|
      Custom::ScoutV2::Exits::ExitTool.new(scout, conversation, declaration: exit_decl, scope: self)
    end
    tools + exits
  end

  def setup_initial_tools!(decision:, ctx:, scout:, conversation:, openable:)
    @ctx = ctx
    add_baseline(Custom::Scout::Tools::SearchKnowledgeBase.new(scout, conversation, playground: false))
    add_baseline(
      Custom::ScoutV2::Exits::ExitTool.new(
        scout,
        conversation,
        declaration: Custom::ScoutV2::Playbook::ExitDeclaration::HANDOFF,
        scope: self
      )
    )
    add_baseline(Custom::ScoutV2::Tools::OpenPlaybook.new(scout, conversation, openable: openable, scope: self)) if openable.any?
    register(@baseline_tools)

    return unless decision.playbook

    @active_procedure_name = decision.playbook.name
    register(actions_for(decision.playbook, scout: scout, conversation: conversation))
  end

  def content_for(playbook)
    raise 'Turn snapshot required before calling content_for' if @ctx.nil?

    Custom::ScoutV2::Playbook::ContentBuilder.call(playbook: playbook, ctx: @ctx)
  end

  def wrap(tool)
    @wrapped_tools[tool] ||= begin
      guard_tool(tool)
      @tool_wrapper.call(tool)
    end
  end

  private

  def guard_tool(tool)
    scope = self
    original_execute = tool.method(:execute)
    tool.define_singleton_method(:execute) do |**args|
      if scope.ended?
        { error: TURN_ENDED_ERROR }
      else
        original_execute.call(**args)
      end
    end
  end
end
