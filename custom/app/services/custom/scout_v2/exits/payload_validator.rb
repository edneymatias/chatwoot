# frozen_string_literal: true

require 'time'

class Custom::ScoutV2::Exits::PayloadValidator
  class << self
    def call(declaration, payload)
      new(declaration, payload).call
    end
  end

  def initialize(declaration, payload)
    @declaration = declaration
    @payload = normalize_payload(payload)
  end

  def call
    problems = []
    validate_missing_and_types(problems)
    validate_undeclared(problems)
    problems
  end

  private

  def normalize_payload(payload)
    payload.transform_keys(&:to_s)
  end

  def validate_missing_and_types(problems)
    @declaration.fields.each do |field_name, expected_type|
      unless @payload.key?(field_name)
        problems << "campo '#{field_name}' ausente"
        next
      end

      val = @payload[field_name]
      next if valid_type?(val, expected_type)

      problems << "campo '#{field_name}' deve ser #{expected_type}"
    end
  end

  def validate_undeclared(problems)
    (@payload.keys - @declaration.fields.keys).each do |extra_key|
      problems << "campo '#{extra_key}' não declarado"
    end
  end

  def valid_type?(val, expected_type)
    case expected_type
    when 'string' then valid_string?(val)
    when 'integer' then valid_integer?(val)
    when 'number' then valid_number?(val)
    when 'boolean' then boolean?(val)
    when 'datetime' then valid_datetime?(val)
    end
  end

  def valid_string?(val)
    val.is_a?(String) && val.strip.present?
  end

  def valid_integer?(val)
    val.is_a?(Integer)
  end

  def valid_number?(val)
    val.is_a?(Integer) || val.is_a?(Float)
  end

  def boolean?(val)
    val.is_a?(TrueClass) || val.is_a?(FalseClass)
  end

  def valid_datetime?(val)
    return false unless val.is_a?(String)

    Time.iso8601(val)
    true
  rescue ArgumentError
    false
  end
end
