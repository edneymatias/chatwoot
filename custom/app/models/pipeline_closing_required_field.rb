# == Schema Information
#
# Table name: ichatr_pipeline_closing_required_fields
#
#  id                             :bigint           not null, primary key
#  account_id                     :bigint           not null
#  custom_attribute_definition_id :bigint           not null
#  outcome                        :integer          not null
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#
# Indexes
#
#  idx_ichatr_pipeline_closing_req_fields_on_acc_attr_outcome (account_id, custom_attribute_definition_id, outcome) UNIQUE
#
class PipelineClosingRequiredField < ApplicationRecord
  self.table_name = 'ichatr_pipeline_closing_required_fields'

  belongs_to :account
  belongs_to :custom_attribute_definition

  # NOTE: the integer mapping is independent of Opportunity#status's enum
  # but they conceptually align for won/lost.
  enum outcome: {
    won: 1,
    lost: 2
  }

  validates :account, presence: true
  validates :custom_attribute_definition, presence: true
  validates :custom_attribute_definition_id, uniqueness: { scope: %i[account_id outcome], message: 'is already required for this outcome' } # rubocop:disable Rails/I18nLocaleTexts
  validate :definition_must_be_opportunity_attribute

  private

  def definition_must_be_opportunity_attribute
    return unless custom_attribute_definition
    return if custom_attribute_definition.opportunity_attribute?

    errors.add(:custom_attribute_definition, 'must be an opportunity attribute')
  end
end
