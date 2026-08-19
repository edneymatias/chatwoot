# frozen_string_literal: true

class Custom::Scout::Tools::MoveOpportunityStage < Custom::Scout::Tools::BaseTool
  description 'Moves the conversation Opportunity to a new pipeline stage and records a reason if lost or disqualified'

  param :stage_id, type: :integer, desc: 'Target pipeline stage ID to move the Opportunity into', required: true
  param :lost_reason, type: :string, desc: 'Reason for loss or disqualification', required: false

  def name
    'move_opportunity_stage'
  end

  def execute(stage_id:, lost_reason: nil)
    opportunity = Opportunity.find_by(origin_conversation_id: conversation.id)
    return 'No opportunity found for this conversation.' if opportunity.blank?

    stage = PipelineStage.find_by(id: stage_id, account_id: account.id)
    return 'Pipeline stage not found.' if stage.blank?

    opportunity.pipeline_stage_id = stage.id
    if lost_reason.present?
      opportunity.lost_reason = lost_reason
      opportunity.status = :lost if opportunity.respond_to?(:status)
    end

    opportunity.save!
    "Opportunity moved to stage #{stage.name || stage.id} successfully."
  end
end
