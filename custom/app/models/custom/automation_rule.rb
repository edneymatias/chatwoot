module Custom::AutomationRule
  OPPORTUNITY_ACTIONS = %w[
    create_opportunity
    update_opportunity_stage
    update_opportunity_assignee
    update_opportunity_status
    update_opportunity_value
    update_opportunity_custom_attribute
    update_contact_attribute
    update_contact_custom_attribute
  ].freeze

  OPPORTUNITY_CONDITIONS = %w[
    pipeline_id
    pipeline_stage_id
    from_pipeline_stage_id
    value
    loss_reason
  ].freeze

  def actions_attributes
    super + OPPORTUNITY_ACTIONS
  end

  def conditions_attributes
    super + OPPORTUNITY_CONDITIONS
  end
end
