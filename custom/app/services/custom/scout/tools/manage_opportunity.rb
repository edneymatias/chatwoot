# frozen_string_literal: true

class Custom::Scout::Tools::ManageOpportunity < Custom::Scout::Tools::BaseTool
  description 'Creates or updates a commercial Opportunity in the sales pipeline for the current conversation'

  param :action, type: :string, desc: "Action: 'create' or 'update'", required: false
  param :title, type: :string, desc: 'Opportunity title', required: false
  param :stage_id, type: :integer, desc: 'Target pipeline stage ID', required: false
  param :estimated_value, type: :number, desc: 'Estimated deal value', required: false
  param :custom_attributes, type: :hash, desc: 'Key-value map of qualification fields', required: false
  param :opportunity_id, type: :integer, desc: 'ID of an existing open Opportunity to continue', required: false

  attr_reader :handoff_needed

  def name
    'manage_opportunity'
  end

  def execute(action: 'create', opportunity_id: nil, **params)
    @handoff_needed = false

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
    default_stage_id = scout.default_pipeline_stage_id || account.pipeline_stages.first&.id
    resolved_title = title.presence || "Oportunidade ##{conversation.display_id}"

    opp = Opportunity.create!(
      account: account,
      contact: contact,
      origin_conversation: conversation,
      pipeline_stage_id: default_stage_id,
      title: resolved_title,
      value: estimated_value,
      custom_attributes: sanitize_custom_attributes(custom_attributes),
      status: :open
    )

    referral_message = find_referral_message
    Custom::ReferralAttributionService.process(opp, referral_message) if referral_message

    return "Opportunity created successfully (ID: #{opp.id}, Stage: #{default_stage_id})." if stage_id.blank?

    # A caller-requested stage (e.g. the qualified stage) must go through the same
    # requirement gate and handoff flagging as update_opportunity — creating directly
    # into a gated stage would silently skip both.
    service = Custom::Scout::OpportunityStageTransitionService.new(scout: scout, conversation: conversation, opportunity: opp)
    result = service.call(stage_id: stage_id)
    @handoff_needed = service.handoff_needed
    "Opportunity created successfully (ID: #{opp.id}). #{result}"
  end

  def update_opportunity(opp, stage_id: nil, **params)
    opp.attach_conversation!(conversation)

    opp.title = params[:title] if params[:title].present?
    opp.value = params[:estimated_value] if params[:estimated_value].present?
    opp.custom_attributes = (opp.custom_attributes || {}).merge(sanitize_custom_attributes(params[:custom_attributes]))

    # Persist field updates before attempting any stage transition: a rejected
    # transition (missing required fields) must not discard data the model
    # legitimately provided in the same call.
    opp.save!

    return "Opportunity updated successfully (ID: #{opp.id})." if stage_id.blank?

    service = Custom::Scout::OpportunityStageTransitionService.new(
      scout: scout,
      conversation: conversation,
      opportunity: opp
    )
    result = service.call(stage_id: stage_id)
    @handoff_needed = service.handoff_needed
    result
  end

  def sanitize_custom_attributes(candidate)
    hash = coerce_hash_param(candidate)
    return {} unless hash.is_a?(Hash)

    valid_keys = account.custom_attribute_definitions.where(attribute_model: :opportunity_attribute).pluck(:attribute_key)
    hash.stringify_keys.slice(*valid_keys)
  end

  def find_referral_message
    conversation.messages.incoming
                .where("(content_attributes #>> '{}')::jsonb -> 'referral' IS NOT NULL")
                .order(created_at: :asc)
                .first || conversation.messages.incoming.order(created_at: :asc).first
  end
end
