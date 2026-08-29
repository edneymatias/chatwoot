# frozen_string_literal: true

class Custom::Scout::Tools::MoveOpportunityStage < Custom::Scout::Tools::BaseTool
  description 'Moves the conversation Opportunity to a new pipeline stage in the sales funnel'

  param :stage_id, type: :integer, desc: 'Target pipeline stage ID to move the Opportunity into', required: true

  attr_reader :handoff_needed

  def name
    'move_opportunity_stage'
  end

  def execute(stage_id:)
    @handoff_needed = false
    return "[Simulado] Oportunidade movida para etapa #{stage_id}" if playground?

    opportunity = Opportunity.find_by(origin_conversation_id: conversation.id)
    return 'No opportunity found for this conversation.' if opportunity.blank?

    service = Custom::Scout::OpportunityStageTransitionService.new(
      scout: scout,
      conversation: conversation,
      opportunity: opportunity
    )
    result = service.call(stage_id: stage_id)
    @handoff_needed = service.handoff_needed
    result
  end
end
