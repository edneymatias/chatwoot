# frozen_string_literal: true

class ScoutTool < ApplicationRecord
  self.table_name = 'ichatr_scout_tools'

  AUTH_TYPES = %w[none bearer basic api_key].freeze
  MASKED_SECRET = '••••••••'
  IDENTIFIER_REGEX = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

  encrypts :auth_headers

  belongs_to :account

  alias_attribute :parameters_schema, :parameter_schema

  validates :account_id, :name, :description, :endpoint_url, :http_method, presence: true
  validates :auth_type, inclusion: { in: AUTH_TYPES }, allow_nil: true
  validate :validate_parameter_schema_properties
  validate :validate_auth_credentials

  def auth_headers=(value)
    if value.is_a?(Hash) || value.respond_to?(:to_unsafe_h)
      h = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
      super(h.to_json)
    elsif value.is_a?(String) && value.include?('=>')
      super(parse_yaml_to_json(value))
    else
      super(value)
    end
  end

  def auth_headers
    val = super
    return val unless val.is_a?(String) && val.include?('=>')

    begin
      parsed = YAML.safe_load(val.gsub('=>', ': '))
      parsed.is_a?(Hash) ? parsed.to_json : val
    rescue StandardError
      val
    end
  end

  def parsed_auth_headers
    val = auth_headers
    return {} if val.blank?
    return val.transform_keys(&:to_s) if val.is_a?(Hash)

    parse_string_auth_headers(val)
  rescue JSON::ParserError, TypeError
    {}
  end

  def masked_auth_headers
    raw = parsed_auth_headers
    return {} if raw.blank?

    case auth_type
    when 'bearer'
      { 'token' => MASKED_SECRET }
    when 'basic'
      { 'username' => raw['username'], 'password' => MASKED_SECRET }
    when 'api_key'
      { 'header_name' => raw['header_name'], 'header_value' => MASKED_SECRET }
    else
      raw.transform_values { MASKED_SECRET }
    end
  end

  def apply_credentials_update(incoming_credentials)
    return if incoming_credentials.blank?

    normalized = normalize_incoming_hash(incoming_credentials)
    return unless normalized.is_a?(Hash)

    existing = parsed_auth_headers
    self.auth_headers = merge_preserved_secrets(normalized, existing)
  end

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

  def parse_string_auth_headers(val)
    trimmed = val.strip
    if trimmed.start_with?('{') && trimmed.end_with?('}')
      JSON.parse(trimmed)
    elsif trimmed.start_with?('Bearer ')
      { 'token' => trimmed.sub(/\ABearer\s+/i, '') }
    else
      { 'Authorization' => trimmed }
    end
  end

  def normalize_incoming_hash(val)
    h = val.respond_to?(:to_unsafe_h) ? val.to_unsafe_h : val
    h.respond_to?(:deep_stringify_keys) ? h.deep_stringify_keys : h
  end

  def merge_preserved_secrets(incoming, existing)
    case auth_type
    when 'bearer' then merge_bearer_secret(incoming, existing)
    when 'basic' then merge_basic_secrets(incoming, existing)
    when 'api_key' then merge_api_key_secrets(incoming, existing)
    end
    incoming
  end

  def merge_bearer_secret(incoming, existing)
    incoming['token'] = existing['token'] if secret_blank_or_masked?(incoming['token'])
  end

  def merge_basic_secrets(incoming, existing)
    incoming['password'] = existing['password'] if secret_blank_or_masked?(incoming['password'])
    incoming['username'] = existing['username'] if incoming['username'].blank?
  end

  def merge_api_key_secrets(incoming, existing)
    incoming['header_value'] = existing['header_value'] if secret_blank_or_masked?(incoming['header_value'])
    incoming['header_name'] = existing['header_name'] if incoming['header_name'].blank?
  end

  def secret_blank_or_masked?(val)
    val == MASKED_SECRET || val.blank?
  end

  def parse_yaml_to_json(str)
    parsed = YAML.safe_load(str.gsub('=>', ': '))
    parsed.is_a?(Hash) ? parsed.to_json : str
  rescue StandardError
    str
  end

  def validate_parameter_schema_properties
    return if parameter_schema.blank?

    schema = parameter_schema.is_a?(String) ? JSON.parse(parameter_schema) : parameter_schema
    return unless schema.is_a?(Hash) && schema['properties'].is_a?(Hash)

    schema['properties'].each_key do |prop_name|
      next if prop_name.to_s.match?(IDENTIFIER_REGEX)

      msg = I18n.t('activerecord.errors.models.scout_tool.attributes.parameter_schema.invalid_property_name',
                   name: prop_name,
                   default: "contains invalid property name: '#{prop_name}'. Only alphanumeric characters and underscores are allowed.")
      errors.add(:parameter_schema, msg)
    end
  rescue JSON::ParserError
    errors.add(:parameter_schema, I18n.t('activerecord.errors.models.scout_tool.attributes.parameter_schema.not_valid_json',
                                         default: 'is not valid JSON'))
  end

  def validate_auth_credentials
    return if auth_type.blank? || auth_type == 'none'

    headers = parsed_auth_headers
    case auth_type
    when 'bearer' then validate_bearer_credentials(headers)
    when 'basic' then validate_basic_credentials(headers)
    when 'api_key' then validate_api_key_credentials(headers)
    end
  end

  def validate_bearer_credentials(headers)
    token = headers['token'].presence || headers['Authorization']
    return if token.present?

    errors.add(:auth_headers, I18n.t('activerecord.errors.models.scout_tool.attributes.auth_headers.bearer_token_required',
                                     default: 'must include a token for Bearer authentication'))
  end

  def validate_basic_credentials(headers)
    return if headers['username'].present? && headers['password'].present?

    errors.add(:auth_headers, I18n.t('activerecord.errors.models.scout_tool.attributes.auth_headers.basic_credentials_required',
                                     default: 'must include username and password for Basic authentication'))
  end

  def validate_api_key_credentials(headers)
    return if headers['header_name'].present? && headers['header_value'].present?

    errors.add(:auth_headers, I18n.t('activerecord.errors.models.scout_tool.attributes.auth_headers.api_key_credentials_required',
                                     default: 'must include header_name and header_value for API Key authentication'))
  end

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
