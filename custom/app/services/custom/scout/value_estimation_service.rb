# frozen_string_literal: true

class Custom::Scout::ValueEstimationService
  def initialize(scout:)
    @scout = scout
  end

  def sync!(opportunity)
    return unless @scout&.interest_attribute_definition
    return if opportunity.blank?

    interest_key = @scout.interest_attribute_definition.attribute_key
    selected_option = opportunity.custom_attributes&.dig(interest_key)
    return if selected_option.blank?

    value_map = @scout.value_by_interest || {}
    return unless value_map.key?(selected_option.to_s)

    mapped_value = value_map[selected_option.to_s]
    opportunity.value = mapped_value if mapped_value.present?
  end
end
