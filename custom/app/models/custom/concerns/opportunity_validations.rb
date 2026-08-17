# frozen_string_literal: true

module Custom::Concerns::OpportunityValidations
  extend ActiveSupport::Concern

  included do
    validates :title, :contact_id, :pipeline_stage_id, :account_id, presence: true
    validate :pipeline_stage_belongs_to_account
    validate :validate_forward_stage_move_requirements, on: :update, if: :pipeline_stage_id_changed?
    validate :validate_closing_requirements, on: :update, if: :status_changed?
    validate :validate_origin_conversation_id_immutability, on: :update, if: :origin_conversation_id_changed?
    validate :validate_active_conversation_uniqueness, if: :active_conversation_id_changed?
  end

  private

  def pipeline_stage_belongs_to_account
    return unless account_id && pipeline_stage_id
    return unless pipeline_stage&.account_id != account_id

    errors.add(:pipeline_stage, 'must belong to the same account')
  end

  def validate_forward_stage_move_requirements
    return if Current.executed_by.is_a?(AutomationRule)
    return unless pipeline_stage_id_was

    old_stage = account.pipeline_stages.find_by(id: pipeline_stage_id_was)
    return unless old_stage && pipeline_stage
    return if pipeline_stage.position <= old_stage.position

    missing_keys = missing_required_keys(pipeline_stage)
    value_missing = pipeline_stage.requires_deal_value? && value.nil?
    return unless missing_keys.any? || value_missing

    self.missing_required_fields = { custom_attribute_keys: missing_keys, requires_value: value_missing }
    errors.add(:base, 'Missing required fields for this stage')
  end

  def validate_closing_requirements
    return if Current.executed_by.is_a?(AutomationRule)
    return unless status.to_s.in?(%w[won lost])

    missing_keys = []
    attrs = custom_attributes || {}

    PipelineClosingRequiredField.where(account_id: account_id, outcome: status).each do |req|
      definition = req.custom_attribute_definition
      missing_keys << definition.attribute_key unless attrs.key?(definition.attribute_key)
    end

    return unless missing_keys.any?

    self.missing_required_fields = { custom_attribute_keys: missing_keys }
    errors.add(:base, 'Missing required fields to close this opportunity')
  end

  def missing_required_keys(stage)
    missing_keys = []
    attrs = custom_attributes || {}

    stage.required_custom_attribute_definitions.each do |definition|
      missing_keys << definition.attribute_key unless attrs.key?(definition.attribute_key)
    end

    missing_keys
  end

  def validate_origin_conversation_id_immutability
    return if origin_conversation_id_was.nil?

    errors.add(:origin_conversation_id, 'cannot be changed once set')
  end

  def validate_active_conversation_uniqueness
    return if active_conversation_id.blank?

    conflicting = Opportunity.where(account_id: account_id, active_conversation_id: active_conversation_id)
                             .where.not(id: id)
    return if conflicting.none?

    errors.add(:active_conversation_id, 'is already actively associated with another opportunity')
  end
end
