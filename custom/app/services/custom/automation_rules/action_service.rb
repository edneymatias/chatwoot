module Custom::AutomationRules::ActionService
  private

  def create_opportunity(params)
    return if Opportunity.exists?(origin_conversation_id: @conversation.id)

    opts = (params[0] || {}).with_indifferent_access
    title = opts[:title_template].presence || "Oportunidade ##{@conversation.display_id}"
    assignee_id = if opts[:assignee_id] == 'same_as_conversation'
                    @conversation.assignee_id
                  else
                    opts[:assignee_id]
                  end

    begin
      Opportunity.create!(
        account: @conversation.account,
        contact: @conversation.contact,
        pipeline_stage_id: opts[:pipeline_stage_id],
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
