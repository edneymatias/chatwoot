# frozen_string_literal: true

module Custom::AutomationRules::ActionService
  def self.process_campaign_attribution(opportunity, first_message)
    Custom::ReferralAttributionService.process(opportunity, first_message)
  end

  private

  def create_opportunity(params)
    decision = Custom::Opportunities::ContinuityResolverService.new(
      account: @conversation.account,
      contact: @conversation.contact
    ).call

    return handle_opportunity_ambiguity(decision) if decision.outcome == :ambiguous
    return unless decision.outcome == :create_new

    persist_opportunity(params[0], params[1]&.presence)
  end

  def persist_opportunity(stage_id, assignee_id_param)
    opportunity = Opportunity.create!(
      account: @conversation.account,
      contact: @conversation.contact,
      pipeline_stage_id: stage_id,
      origin_conversation: @conversation,
      status: :open,
      title: "Oportunidade ##{@conversation.display_id}",
      assignee_id: resolve_assignee_id(assignee_id_param)
    )

    referral_message = find_referral_message
    Custom::AutomationRules::ActionService.process_campaign_attribution(opportunity, referral_message)
  rescue ActiveRecord::RecordNotUnique
    # Idempotent no-op
  end

  def handle_opportunity_ambiguity(decision)
    note_content = "⚠️ [Continuidade de Oportunidade]: Não foi possível determinar a oportunidade automaticamente. Motivo: #{decision.reason}"
    add_private_note([note_content])
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
