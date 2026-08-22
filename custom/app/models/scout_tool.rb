# frozen_string_literal: true

class ScoutTool < ApplicationRecord
  self.table_name = 'ichatr_scout_tools'

  encrypts :auth_headers

  belongs_to :account

  alias_attribute :parameters_schema, :parameter_schema

  validates :account_id, :name, :description, :endpoint_url, :http_method, presence: true

  def format_response(raw_body)
    return '' if raw_body.blank?
    return parse_json_or_raw(raw_body) if response_template.blank?

    parsed = parse_json_response(raw_body)
    context = { 'response' => parsed, 'r' => parsed }
    liquid_template = Liquid::Template.parse(response_template, error_mode: :strict)
    rendered = liquid_template.render(context.deep_stringify_keys, registers: {}, strict_variables: true, strict_filters: true)

    raise "Template rendering failed: #{liquid_template.errors.map(&:message).join(', ')}" if liquid_template.errors.present?

    rendered
  rescue Liquid::SyntaxError, Liquid::UndefinedVariable, Liquid::UndefinedFilter => e
    raise "Template rendering failed: #{e.message}"
  end

  private

  def parse_json_response(body)
    parsed = JSON.parse(body)
    parsed.is_a?(Hash) ? parsed : { 'data' => parsed }
  rescue JSON::ParserError
    { 'data' => body }
  end

  def parse_json_or_raw(body)
    JSON.parse(body)
  rescue JSON::ParserError
    body
  end
end
