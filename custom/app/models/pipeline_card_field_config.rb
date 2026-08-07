class PipelineCardFieldConfig < ApplicationRecord
  self.table_name = 'ichatr_pipeline_card_field_configs'

  belongs_to :account
  belongs_to :custom_attribute_definition, optional: true

  enum field_type: { custom_attribute: 0, deal_value: 1 }

  validates :color, presence: true
  validates :custom_attribute_definition_id, uniqueness: { scope: :account_id }, if: :custom_attribute?
  validate :custom_attribute_definition_is_opportunity_attribute
  validate :at_most_one_deal_value_per_account
  validate :at_most_three_configs_per_account

  before_validation :set_position, on: :create

  private

  def custom_attribute_definition_is_opportunity_attribute
    return unless custom_attribute? && custom_attribute_definition.present?

    return if custom_attribute_definition.attribute_model == 'opportunity_attribute'

    errors.add(:custom_attribute_definition, 'must be an opportunity attribute')
  end

  def at_most_one_deal_value_per_account
    return unless deal_value?

    existing_configs = account.pipeline_card_field_configs.deal_value
    existing_configs = existing_configs.where.not(id: id) if persisted?

    return unless existing_configs.exists?

    errors.add(:field_type, 'only one deal_value config is allowed per account')
  end

  def at_most_three_configs_per_account
    return unless account

    existing_configs = account.pipeline_card_field_configs
    existing_configs = existing_configs.where.not(id: id) if persisted?

    return unless existing_configs.count >= 3

    errors.add(:base, 'at most 3 card field configs are allowed per account')
  end

  def set_position
    self.position ||= (account.pipeline_card_field_configs.maximum(:position) || 0) + 1
  end
end
