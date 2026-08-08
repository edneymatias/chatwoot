module Custom::AutomationRules::ActionService
  private

  def create_opportunity(params)
    return if Opportunity.exists?(origin_conversation_id: @conversation.id)

    stage_id = params[0]
    assignee_id_param = params[1]&.presence

    # Temporarily drop title_template parsing since we are using scalar arrays. We use default title.
    title = "Oportunidade ##{@conversation.display_id}"
    assignee_id = if assignee_id_param == 'same_as_conversation'
                    @conversation.assignee_id
                  else
                    assignee_id_param
                  end

    begin
      Opportunity.create!(
        account: @conversation.account,
        contact: @conversation.contact,
        pipeline_stage_id: stage_id,
        origin_conversation: @conversation,
        status: :open,
        title: title,
        assignee_id: assignee_id
      )
    rescue ActiveRecord::RecordNotUnique
      # Idempotent no-op
    end
  end
end
