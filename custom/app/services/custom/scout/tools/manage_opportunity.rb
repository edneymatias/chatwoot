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
    sanitized_attrs = sanitize_custom_attributes(custom_attributes)

    opp = Opportunity.create!(
      account: account,
      contact: contact,
      origin_conversation: conversation,
      pipeline_stage_id: default_stage_id,
      title: resolved_title,
      value: estimated_value,
      custom_attributes: sanitized_attrs,
      status: :open
    )

    process_referral_attribution(opp)

    reminder = scoped_confirmation_reminder(custom_attribute_labels(sanitized_attrs.keys, attribute_model: :opportunity_attribute))
    return "Opportunity created successfully (ID: #{opp.id}, Stage: #{default_stage_id}).#{reminder}" if stage_id.blank?

    # A caller-requested stage (e.g. the qualified stage) must go through the same
    # requirement gate and handoff flagging as update_opportunity — creating directly
    # into a gated stage would silently skip both.
    "Opportunity created successfully (ID: #{opp.id}). #{apply_stage_transition(opp, stage_id, reminder)}"
  end

  def update_opportunity(opp, stage_id: nil, **params)
    opp.attach_conversation!(conversation)
    sanitized_attrs = apply_opportunity_fields(opp, params)
    Custom::Scout::ValueEstimationService.new(scout: scout).sync!(opp)

    # Persist field updates before attempting any stage transition: a rejected
    # transition (missing required fields) must not discard data the model
    # legitimately provided in the same call.
    opp.save!
    fields_changed = opportunity_fields_changed?(opp)

    reminder = scoped_confirmation_reminder(custom_attribute_labels(sanitized_attrs.keys, attribute_model: :opportunity_attribute))
    return apply_stage_transition(opp, stage_id, reminder) if stage_id.present?
    return already_qualified_update_message(opp, reminder) if fields_changed && opp.pipeline_stage_id == scout.qualified_stage_id

    "Opportunity updated successfully (ID: #{opp.id}).#{reminder}"
  end

  def apply_opportunity_fields(opp, params)
    opp.title = params[:title] if params[:title].present?
    opp.value = params[:estimated_value] if params[:estimated_value].present?
    sanitized_attrs = sanitize_custom_attributes(params[:custom_attributes])
    opp.custom_attributes = (opp.custom_attributes || {}).merge(sanitized_attrs)
    sanitized_attrs
  end

  def opportunity_fields_changed?(opp)
    opp.saved_change_to_title? || opp.saved_change_to_value? || opp.saved_change_to_custom_attributes?
  end

  # Closes the gap behind conversation #66/display_id 64: an already-qualified opportunity that
  # gets fresh data (e.g. a new appointment time from a follow-up conversation merged into this
  # contact) never triggers a stage-transition handoff, because Rails doesn't consider reassigning
  # the same pipeline_stage_id a "change" — and the model has no reason to re-send stage_id when it
  # isn't moving the deal anywhere. Without this, real new commitments on an already-qualified deal
  # can silently overwrite prior data with nobody notified.
  def already_qualified_update_message(opp, reminder)
    @handoff_needed = true
    create_requalified_update_note(opp)
    "Opportunity updated successfully (ID: #{opp.id})." \
      "#{reminder}#{Custom::Scout::OpportunityStageTransitionService::NO_QUESTION_CLOSING_INSTRUCTION}"
  end

  # Flags for human review that this isn't a routine stage-transition handoff: the deal was already
  # qualified (possibly from an earlier, unrelated visit — e.g. a contact merge earlier in this same
  # conversation) and just got overwritten with this conversation's data. The agent should confirm
  # whether the prior data still applies before treating this as a fresh commitment.
  def create_requalified_update_note(opp)
    Messages::MessageBuilder.new(
      nil, conversation,
      { content: "ℹ️ Oportunidade ##{opp.id} - #{opp.title} já estava no estágio \"#{opp.pipeline_stage.name}\" e foi " \
                 'atualizada com novos dados nesta conversa, sem mudança de estágio (pode ser continuidade legítima, ou ' \
                 'uma visita/pedido diferente reaproveitando a mesma oportunidade — vale confirmar com o cliente).',
        private: true }
    ).perform
  end

  def apply_stage_transition(opp, stage_id, reminder)
    service = Custom::Scout::OpportunityStageTransitionService.new(scout: scout, conversation: conversation, opportunity: opp)
    result = service.call(stage_id: stage_id)
    @handoff_needed = service.handoff_needed
    "#{result}#{reminder}"
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

  def process_referral_attribution(opp)
    referral_message = find_referral_message
    return unless referral_message

    Custom::ReferralAttributionService.process(opp, referral_message)
    classify_and_estimate_referral_interest(opp) if referral_message.content_attributes&.dig('referral').present?
  end

  def classify_and_estimate_referral_interest(opp)
    return unless scout&.interest_attribute_definition

    matched_interest = Custom::Scout::ReferralInterestClassifierService.new(
      scout: scout,
      conversation: conversation
    ).classify(opportunity: opp)
    return if matched_interest.blank?

    interest_key = scout.interest_attribute_definition.attribute_key
    opp.custom_attributes = (opp.custom_attributes || {}).merge(interest_key => matched_interest)
    Custom::Scout::ValueEstimationService.new(scout: scout).sync!(opp)
    opp.save!
  end
end
