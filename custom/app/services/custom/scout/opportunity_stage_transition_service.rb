# frozen_string_literal: true

class Custom::Scout::OpportunityStageTransitionService
  def initialize(scout:, conversation:, opportunity:)
    @scout = scout
    @conversation = conversation
    @opportunity = opportunity
  end

  def call(stage_id:)
    return 'No opportunity found for this conversation.' if @opportunity.blank?

    stage = @scout.account&.pipeline_stages&.find_by(id: stage_id)
    return 'Pipeline stage not found.' if stage.blank?

    if stage.id == @scout.qualified_stage_id
      missing_global_msg = check_global_qualification_requirements
      return missing_global_msg if missing_global_msg.present?
    end

    @opportunity.pipeline_stage_id = stage.id

    if @opportunity.save
      handle_post_save_handoff
      "Opportunity moved to stage #{stage.name || stage.id} successfully."
    else
      format_save_failure_message(stage)
    end
  end

  private

  def check_global_qualification_requirements
    attrs = @opportunity.custom_attributes || {}
    missing_defs = @scout.required_custom_attribute_definitions.select do |definition|
      attrs[definition.attribute_key].blank?
    end

    return nil if missing_defs.empty?

    names = missing_defs.map(&:attribute_display_name).join(', ')
    "Cannot move to the qualified stage. Missing required fields: #{names}."
  end

  def handle_post_save_handoff
    return unless @opportunity.saved_change_to_pipeline_stage_id?
    return unless @opportunity.pipeline_stage_id == @scout.qualified_stage_id

    Custom::Scout::HandoffService.new(scout: @scout, conversation: @conversation).perform
  end

  def format_save_failure_message(stage)
    missing_fields = @opportunity.missing_required_fields
    if missing_fields.present?
      missing_items = resolve_missing_stage_items(missing_fields)
      return "Cannot move to stage #{stage.name || stage.id}. Missing required fields: #{missing_items.join(', ')}." if missing_items.any?
    end

    "Cannot move to stage #{stage.name || stage.id}. #{@opportunity.errors.full_messages.join(', ')}"
  end

  def resolve_missing_stage_items(missing_fields)
    missing_items = []
    if missing_fields[:custom_attribute_keys].present?
      defs = @opportunity.account.custom_attribute_definitions.where(
        attribute_model: :opportunity_attribute,
        attribute_key: missing_fields[:custom_attribute_keys]
      )
      key_to_name = defs.index_by(&:attribute_key)
      missing_items.concat(missing_fields[:custom_attribute_keys].map { |k| key_to_name[k]&.attribute_display_name || k })
    end
    missing_items << 'Deal Value' if missing_fields[:requires_value]
    missing_items
  end
end
