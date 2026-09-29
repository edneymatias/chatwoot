# frozen_string_literal: true

class Custom::ScoutV2::Tools::ManageOpportunity < Custom::Scout::Tools::ManageOpportunity
  description 'Creates or updates a commercial Opportunity in the sales pipeline for the current conversation'

  param :action, type: :string, desc: "Action: 'create' or 'update'", required: false
  param :title, type: :string, desc: 'Opportunity title', required: false
  param :estimated_value, type: :number, desc: 'Estimated deal value', required: false
  param :custom_attributes, type: :hash, desc: 'Key-value map of qualification fields', required: false
  param :opportunity_id, type: :integer, desc: 'ID of an existing open Opportunity to continue', required: false

  def execute(action: 'create', opportunity_id: nil, stage_id: nil, **params)
    if stage_id.present?
      err = 'stage_id não é aceito: a mudança de estágio acontece apenas pelos exits da playbook.'
      return { error: err }
    end

    super(action: action, opportunity_id: opportunity_id, **params)
  end

  private

  def already_qualified_update_message(opp, reminder)
    create_requalified_update_note(opp)
    "Opportunity updated successfully (ID: #{opp.id}).#{reminder}"
  end
end
