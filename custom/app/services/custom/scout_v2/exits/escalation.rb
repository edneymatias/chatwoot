# frozen_string_literal: true

class Custom::ScoutV2::Exits::Escalation
  CLOSING_INSTRUCTION = 'Escreva agora sua resposta final ao cliente: uma mensagem natural de encerramento, ' \
                        'sem perguntas, informando que um atendente humano dará continuidade ao atendimento.'
  ESCALATION_REFUSED_ERROR = 'A transferência não aconteceu e o estágio não foi alterado: a conversa não está mais aos cuidados do assistente.'

  class << self
    def call(exit_tool, payload)
      new(exit_tool, payload).call
    end
  end

  def initialize(exit_tool, payload)
    @exit_tool = exit_tool
    @payload = payload
    @declaration = exit_tool.declaration
    @scope = exit_tool.scope
    @conversation = exit_tool.conversation
    @scout = exit_tool.scout
  end

  def call
    if @scope.playground?
      perform_playground_escalation
    else
      perform_inbox_escalation
    end
  end

  private

  def perform_inbox_escalation
    error = nil
    @conversation.with_lock do
      unless @conversation.pending?
        error = { error: ESCALATION_REFUSED_ERROR }
        raise ActiveRecord::Rollback
      end

      error = apply_stage_move_if_declared
      raise ActiveRecord::Rollback if error

      Custom::Scout::HandoffService.new(scout: @scout, conversation: @conversation).transfer!(reason: note_reason)
      state = ScoutConversationState.for_conversation(@conversation)
      state.record_terminal_exit!(
        @declaration.name,
        completed: @scope.active_procedure_name
      )
    end

    return error if error

    @scope.end_turn!(escalated: true)
    success_result
  end

  def perform_playground_escalation
    error = nil
    ActiveRecord::Base.transaction do
      error = apply_stage_move_if_declared
      raise ActiveRecord::Rollback if error

      state = ScoutConversationState.for_conversation(@conversation)
      state.record_terminal_exit!(
        @declaration.name,
        completed: @scope.active_procedure_name
      )
    end

    return error if error

    @scope.end_turn!(escalated: true)
    success_result
  end

  def apply_stage_move_if_declared
    return nil unless @declaration.stage

    stage_error = Custom::ScoutV2::Exits::StageMove.call(@exit_tool)
    return nil unless stage_error

    { error: "A transferência não aconteceu e o estágio não foi alterado: #{stage_error[:error]}" }
  end

  def success_result
    "Transferência para atendimento humano realizada. #{CLOSING_INSTRUCTION}"
  end

  def note_reason
    if @declaration.name == 'handoff'
      @payload[:reason]
    else
      build_declared_reason
    end
  end

  def build_declared_reason
    return @declaration.name if @declaration.fields.empty?

    fields_text = @declaration.fields.keys.map do |field|
      val = @payload[field.to_sym]
      "#{field}: #{val}"
    end.join('; ')
    "#{@declaration.name} (#{fields_text})"
  end
end
