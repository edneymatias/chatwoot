# frozen_string_literal: true

class Custom::ScoutV2::Exits::Transition
  TRANSITION_LIMIT_ERROR = "A transição para '%<target>s' não aconteceu: limite de transições deste turno atingido. Responda ao cliente agora."

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
    @scout = exit_tool.scout
  end

  def call
    state = ScoutConversationState.for_conversation(@conversation)
    if @scope.transitions >= 2
      state.record_transition!(@declaration.target, turn_transition_count: @scope.transitions)
      return { error: format(TRANSITION_LIMIT_ERROR, target: @declaration.target) }
    end

    target_playbook = @scope.catalog[@declaration.target]
    error = persist_transition(state, @scope.active_procedure_name)
    return error if error

    activate_target(target_playbook)
  end

  private

  def persist_transition(state, completed_name)
    error = nil
    ActiveRecord::Base.transaction do
      error = apply_stage_move_if_declared
      raise ActiveRecord::Rollback if error

      state.record_transition!(
        @declaration.target,
        turn_transition_count: @scope.transitions,
        completed: completed_name
      )
    end
    error
  end

  def activate_target(target_playbook)
    @scope.record_transition!
    @scope.active_procedure_name = @declaration.target
    target_actions = @scope.actions_for(target_playbook, scout: @scout, conversation: @conversation)
    @scope.replace_with_baseline!(target_actions)
    @scope.content_for(target_playbook)
  end

  def apply_stage_move_if_declared
    return nil unless @declaration.stage

    Custom::ScoutV2::Exits::StageMove.call(@exit_tool)
  end
end
