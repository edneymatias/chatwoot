# frozen_string_literal: true

class ScoutRequiredField < ApplicationRecord
  self.table_name = 'ichatr_scout_required_fields'

  belongs_to :account
  belongs_to :scout, class_name: 'Scout'
  belongs_to :custom_attribute_definition

  before_validation :set_account_from_scout

  validates :account, :scout, :custom_attribute_definition, presence: true
  validates :custom_attribute_definition_id, uniqueness: { scope: :scout_id, message: I18n.t('errors.scout_required_field.already_required') }
  validate :definition_must_be_contact_or_opportunity_attribute

  private

  def set_account_from_scout
    self.account_id ||= scout&.account_id
  end

  def definition_must_be_contact_or_opportunity_attribute
    return unless custom_attribute_definition
    return if custom_attribute_definition.contact_attribute? || custom_attribute_definition.opportunity_attribute?

    errors.add(:custom_attribute_definition, I18n.t('errors.scout_required_field.must_be_contact_or_opportunity_attribute'))
  end
end
