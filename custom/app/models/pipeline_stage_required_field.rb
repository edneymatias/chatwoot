# == Schema Information
#
# Table name: ichatr_pipeline_stage_required_fields
#
#  id                             :bigint           not null, primary key
#  account_id                     :bigint           not null
#  pipeline_stage_id              :bigint           not null
#  custom_attribute_definition_id :bigint           not null
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#
# Indexes
#
#  idx_ichatr_pipeline_stage_req_fields_on_acc_and_attr_def (account_id, custom_attribute_definition_id) UNIQUE
#
class PipelineStageRequiredField < ApplicationRecord
  self.table_name = 'ichatr_pipeline_stage_required_fields'

  belongs_to :account
  belongs_to :pipeline_stage
  belongs_to :custom_attribute_definition

  before_validation :set_account_from_stage

  validates :account, presence: true
  validates :pipeline_stage, presence: true
  validates :custom_attribute_definition, presence: true
  validates :custom_attribute_definition_id,
            uniqueness: { scope: :account_id, message: I18n.t('errors.pipeline_stage_required_field.already_required') }
  validate :definition_must_be_opportunity_attribute

  private

  def set_account_from_stage
    self.account_id ||= pipeline_stage&.account_id
  end

  def definition_must_be_opportunity_attribute
    return unless custom_attribute_definition
    return if custom_attribute_definition.opportunity_attribute?

    errors.add(:custom_attribute_definition, I18n.t('errors.pipeline_stage_required_field.must_be_opportunity_attribute'))
  end
end
