# frozen_string_literal: true

class Custom::ScoutV2::Exits::Terminal
  class << self
    def call(exit_tool)
      new(exit_tool).call
    end
  end

  def initialize(exit_tool)
    @exit_tool = exit_tool
    @declaration = exit_tool.declaration
    @scope = exit_tool.scope
    @conversation = exit_tool.conversation
  end

  def call
    error = nil
    ActiveRecord::Base.transaction do
      error = apply_stage_move_if_declared
      raise ActiveRecord::Rollback if error

      ScoutConversationState.for_conversation(@conversation).record_terminal_exit!(
        @declaration.name,
        completed: @scope.active_procedure_name
      )
    end

    return error if error

    @scope.end_turn!
    "Desfecho '#{@declaration.name}' registrado. Escreva agora sua resposta final ao cliente."
  end

  private

  def apply_stage_move_if_declared
    return nil unless @declaration.stage

    Custom::ScoutV2::Exits::StageMove.call(@exit_tool)
  end
end
