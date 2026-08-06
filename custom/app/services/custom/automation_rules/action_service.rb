module Custom::AutomationRules::ActionService
  private

  def create_opportunity(params)
    return if Opportunity.exists?(origin_conversation_id: @conversation.id)

    title = params[:title_template].presence || "Oportunidade ##{@conversation.display_id}"
    assignee_id = if params[:assignee_id] == 'same_as_conversation'
                    @conversation.assignee_id
                  else
                    params[:assignee_id]
                  end

    begin
      Opportunity.create!(
        account: @conversation.account,
        contact: @conversation.contact,
        pipeline_stage_id: params[:pipeline_stage_id],
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
