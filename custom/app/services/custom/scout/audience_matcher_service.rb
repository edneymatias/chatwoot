# frozen_string_literal: true

class Custom::Scout::AudienceMatcherService
  STANDARD_ATTRIBUTES = %w[name email phone_number identifier blocked].freeze
  ADDITIONAL_ATTRIBUTES = %w[country_code city company_name].freeze

  def initialize(audience:, contact:)
    @audience = Array(audience)
    @contact = contact
  end

  def matches?
    return true if @audience.empty? || @contact.blank?

    @audience.each_with_index.reduce(nil) do |combined, (condition, index)|
      cond_hash = condition.is_a?(Hash) ? condition.with_indifferent_access : {}
      current_match = evaluate_condition(cond_hash)

      if index.zero?
        current_match
      elsif cond_hash[:query_operator].to_s.casecmp('or').zero?
        combined || current_match
      else
        combined && current_match
      end
    end || false
  end

  private

  def evaluate_condition(condition)
    attribute_key = condition[:attribute_key].to_s
    operator = condition[:filter_operator].to_s
    values = Array(condition[:values])

    actual_value = resolve_attribute_value(attribute_key)
    match_operator(operator, actual_value, values)
  end

  def resolve_attribute_value(attribute_key)
    return nil if @contact.blank? || attribute_key.blank?

    if attribute_key == 'labels'
      resolve_labels
    elsif STANDARD_ATTRIBUTES.include?(attribute_key)
      @contact.public_send(attribute_key)
    elsif ADDITIONAL_ATTRIBUTES.include?(attribute_key)
      @contact.additional_attributes&.dig(attribute_key)
    else
      @contact.custom_attributes&.dig(attribute_key)
    end
  end

  def resolve_labels
    if @contact.respond_to?(:label_list)
      @contact.label_list
    else
      @contact.labels.map(&:title)
    end
  end

  def match_operator(operator, actual, values)
    case operator
    when 'equal_to' then match_equal(actual, values)
    when 'not_equal_to' then !match_equal(actual, values)
    when 'is_present' then actual.present?
    when 'is_not_present' then actual.blank?
    when 'contains' then match_contains(actual, values.first)
    when 'does_not_contain' then !match_contains(actual, values.first)
    when 'starts_with' then match_starts_with(actual, values.first)
    when 'greater_than' then compare_numeric(actual, values.first) { |a, b| a > b }
    when 'less_than' then compare_numeric(actual, values.first) { |a, b| a < b }
    else false
    end
  end

  def match_equal(actual, values)
    if actual.is_a?(Array)
      values.any? { |v| actual.map(&:to_s).include?(v.to_s) }
    else
      values.any? { |v| actual.to_s.casecmp(v.to_s).zero? }
    end
  end

  def match_contains(actual, expected)
    return false if actual.blank? || expected.blank?

    if actual.is_a?(Array)
      actual.any? { |item| item.to_s.downcase.include?(expected.to_s.downcase) }
    else
      actual.to_s.downcase.include?(expected.to_s.downcase)
    end
  end

  def match_starts_with(actual, expected)
    return false if actual.blank? || expected.blank?

    actual.to_s.downcase.start_with?(expected.to_s.downcase)
  end

  def compare_numeric(actual, expected)
    return false if actual.blank? || expected.blank?

    act_num = Float(actual)
    exp_num = Float(expected)
    yield(act_num, exp_num)
  rescue ArgumentError, TypeError
    false
  end
end
