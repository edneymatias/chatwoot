# frozen_string_literal: true

module Custom::AutomationRules::ActionService
  def self.process_campaign_attribution(opportunity, first_message)
    Custom::ReferralAttributionService.process(opportunity, first_message)
  end

  private

  def create_opportunity(params)
    return if Opportunity.exists?(origin_conversation_id: @conversation.id)

    stage_id = params[0]
    assignee_id_param = params[1]&.presence

    title = "Oportunidade ##{@conversation.display_id}"
    assignee_id = resolve_assignee_id(assignee_id_param)

    begin
      opportunity = Opportunity.create!(
        account: @conversation.account,
        contact: @conversation.contact,
        pipeline_stage_id: stage_id,
        origin_conversation: @conversation,
        status: :open,
        title: title,
        assignee_id: assignee_id
      )

      referral_message = find_referral_message
      Custom::AutomationRules::ActionService.process_campaign_attribution(opportunity, referral_message)
    rescue ActiveRecord::RecordNotUnique
      # Idempotent no-op
    end
  end

  def find_referral_message
    @conversation.messages.incoming
                 .where("(content_attributes #>> '{}')::jsonb -> 'referral' IS NOT NULL")
                 .order(created_at: :asc)
                 .first || @conversation.messages.incoming.order(created_at: :asc).first
  end

  def resolve_assignee_id(assignee_id_param)
    if assignee_id_param == 'same_as_conversation'
      @conversation.assignee_id
    else
      assignee_id_param
    end
  end
end
