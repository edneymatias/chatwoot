module Custom::AutomationRules::ActionService
  private

  def create_opportunity(params)
    return if Opportunity.exists?(origin_conversation_id: @conversation.id)

    title = params[:title_template].presence || "Oportunidade ##{@conversation.display_id}"

    begin
      Opportunity.create!(
        account: @conversation.account,
        contact: @conversation.contact,
        pipeline_stage_id: params[:pipeline_stage_id],
        origin_conversation: @conversation,
        status: :open,
        title: title
      )
    rescue ActiveRecord::RecordNotUnique
      # Idempotent no-op
    end
  end
end
