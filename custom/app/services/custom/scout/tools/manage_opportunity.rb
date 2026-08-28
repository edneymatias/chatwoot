# frozen_string_literal: true

class Custom::Scout::Tools::ManageOpportunity < Custom::Scout::Tools::BaseTool
  description 'Creates or updates a commercial Opportunity in the sales pipeline for the current conversation'

  param :action, type: :string, desc: "Action: 'create' or 'update'", required: false
  param :title, type: :string, desc: 'Opportunity title', required: false
  param :stage_id, type: :integer, desc: 'Target pipeline stage ID', required: false
  param :estimated_value, type: :number, desc: 'Estimated deal value', required: false
  param :custom_attributes, type: :hash, desc: 'Key-value map of qualification fields', required: false
  param :opportunity_id, type: :integer, desc: 'ID of an existing open Opportunity to continue', required: false

  def name
    'manage_opportunity'
  end

  def execute(action: 'create', opportunity_id: nil, **params)
    if playground?
      payload = params.merge(opportunity_id: opportunity_id).compact
      return "[Simulado] Oportunidade gerenciada (#{action}): #{payload.to_json}"
    end

    decision = Custom::Opportunities::ContinuityResolverService.new(
      account: account,
      contact: contact,
      declared_opportunity_id: opportunity_id
    ).call

    case decision.outcome
    when :reuse
      update_opportunity(decision.opportunity, **params)
    when :create_new
      create_opportunity(**params)
    when :ambiguous
      handle_ambiguity(decision)
    end
  end

  private

  def handle_ambiguity(decision)
    note_content = "⚠️ [Continuidade de Oportunidade]: Não foi possível vincular automaticamente. Motivo: #{decision.reason}"
    Messages::MessageBuilder.new(nil, conversation, { content: note_content, private: true }).perform

    "Opportunity management deferred: #{decision.reason}. A private note was added for human review."
  end

  def create_opportunity(title: nil, stage_id: nil, estimated_value: nil, custom_attributes: nil, **)
    resolved_stage_id = stage_id.presence || scout.default_pipeline_stage_id || account.pipeline_stages.first&.id
    resolved_title = title.presence || "Oportunidade ##{conversation.display_id}"

    opp = Opportunity.create!(
      account: account,
      contact: contact,
      origin_conversation: conversation,
      pipeline_stage_id: resolved_stage_id,
      title: resolved_title,
      value: estimated_value,
      custom_attributes: custom_attributes || {},
      status: :open
    )

    referral_message = find_referral_message
    Custom::ReferralAttributionService.process(opp, referral_message) if referral_message

    "Opportunity created successfully (ID: #{opp.id}, Stage: #{resolved_stage_id})."
  end

  def update_opportunity(opp, stage_id: nil, **params)
    opp.attach_conversation!(conversation)

    opp.title = params[:title] if params[:title].present?
    opp.value = params[:estimated_value] if params[:estimated_value].present?
    opp.custom_attributes = (opp.custom_attributes || {}).merge(params[:custom_attributes]) if params[:custom_attributes].is_a?(Hash)

    if stage_id.present?
      Custom::Scout::OpportunityStageTransitionService.new(
        scout: scout,
        conversation: conversation,
        opportunity: opp
      ).call(stage_id: stage_id)
    else
      opp.save!
      "Opportunity updated successfully (ID: #{opp.id})."
    end
  end

  def find_referral_message
    conversation.messages.incoming
                .where("(content_attributes #>> '{}')::jsonb -> 'referral' IS NOT NULL")
                .order(created_at: :asc)
                .first || conversation.messages.incoming.order(created_at: :asc).first
  end
end
