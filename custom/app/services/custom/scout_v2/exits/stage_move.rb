# frozen_string_literal: true

class Custom::ScoutV2::Exits::StageMove
  class << self
    def call(exit_tool)
      new(exit_tool).call
    end
  end

  def initialize(exit_tool)
    @scout = exit_tool.scout
    @conversation = exit_tool.conversation
    @declaration = exit_tool.declaration
  end

  def call
    role = @declaration.stage

    opportunity = @conversation.reload_active_opportunity
    return { error: 'A oportunidade não pode mudar de estágio: a conversa não tem oportunidade.' } if opportunity.blank?

    target_stage_id = resolve_stage_id(role)
    if target_stage_id.blank?
      return { error: "A oportunidade não pode mudar de estágio: o estágio '#{role}' não está configurado para este assistente." }
    end

    service = Custom::Scout::OpportunityStageTransitionService.new(
      scout: @scout,
      conversation: @conversation,
      opportunity: opportunity
    )
    result_text = service.call(stage_id: target_stage_id)

    return { error: result_text } unless service.moved?

    nil
  end

  private

  def resolve_stage_id(role)
    case role
    when 'qualified' then @scout.qualified_stage_id
    when 'unqualified' then @scout.unqualified_stage_id
    end
  end
end
