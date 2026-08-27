# frozen_string_literal: true

class Custom::Scout::Tools::MoveOpportunityStage < Custom::Scout::Tools::BaseTool
  description 'Moves the conversation Opportunity to a new pipeline stage in the sales funnel'

  param :stage_id, type: :integer, desc: 'Target pipeline stage ID to move the Opportunity into', required: true

  def name
    'move_opportunity_stage'
  end

  def execute(stage_id:)
    return "[Simulado] Oportunidade movida para etapa #{stage_id}" if playground?

    opportunity = Opportunity.find_by(origin_conversation_id: conversation.id)
    return 'No opportunity found for this conversation.' if opportunity.blank?

    Custom::Scout::OpportunityStageTransitionService.new(
      scout: scout,
      conversation: conversation,
      opportunity: opportunity
    ).call(stage_id: stage_id)
  end
end
