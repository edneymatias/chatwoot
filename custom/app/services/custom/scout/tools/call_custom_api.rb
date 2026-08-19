# frozen_string_literal: true

class Custom::Scout::Tools::CallCustomApi < Custom::Scout::Tools::BaseTool
  MAX_RESPONSE_SIZE = 1.megabyte

  description 'Calls an external REST API or webhook configured for this account by tool_id with the given payload.'

  param :tool_id, type: :integer, desc: 'ID of the configured external tool to execute', required: true
  param :payload, type: :object, desc: 'Key-value JSON payload matching the target tool parameters_schema', required: false

  def name
    'call_custom_api'
  end

  def description
    base = 'Calls an external REST API or webhook configured for this account by tool_id with the given payload.'
    tools = available_tools
    return base if tools.blank?

    catalog = tools.map do |t|
      schema_desc = t.parameters_schema.present? ? " (schema: #{t.parameters_schema.to_json})" : ''
      "- [ID: #{t.id}] #{t.name}: #{t.description}#{schema_desc}"
    end.join("\n")

    "#{base}\nAvailable tools for this account:\n#{catalog}"
  end

  def execute(tool_id:, payload: {})
    scout_tool = resolve_scout_tool(tool_id)
    return 'Tool unavailable or not found.' if scout_tool.blank?

    normalized_payload = normalize_payload(payload)

    validation_error = validate_payload_schema(scout_tool, normalized_payload)
    return validation_error if validation_error.present?

    execute_request(scout_tool, normalized_payload)
  rescue SafeFetch::FileTooLargeError => e
    log_tool_error(scout_tool, tool_id, e)
    'Error: Response exceeded maximum allowed size (1 MB).'
  rescue SafeFetch::FetchError => e
    log_tool_error(scout_tool, tool_id, e)
    'Error: Request failed or timed out while contacting the external system.'
  rescue SafeFetch::HttpError => e
    log_tool_error(scout_tool, tool_id, e)
    "Error: External system returned error status: #{e.message}"
  rescue StandardError => e
    log_tool_error(scout_tool, tool_id, e)
    'Error: An error occurred while executing the external tool.'
  end

  private

  def resolve_scout_tool(tool_id)
    return nil if account.blank? || tool_id.blank?

    account.scout_tools.find_by(id: tool_id, enabled: true)
  end

  def available_tools
    return [] if account.blank?

    account.scout_tools.where(enabled: true).order(:id)
  end

  def normalize_payload(payload)
    return {} if payload.blank?

    if payload.is_a?(String)
      parse_string_payload(payload)
    elsif payload.respond_to?(:deep_stringify_keys)
      payload.deep_stringify_keys
    else
      payload
    end
  end

  def parse_string_payload(payload)
    parsed = JSON.parse(payload)
    parsed.is_a?(Hash) ? parsed.deep_stringify_keys : parsed
  rescue JSON::ParserError
    payload
  end

  def validate_payload_schema(scout_tool, payload)
    schema = scout_tool.parameters_schema
    return nil if schema.blank? || schema == {}

    schemer = JSONSchemer.schema(schema)
    errors = schemer.validate(payload).to_a
    return nil if errors.empty?

    formatted_errors = errors.filter_map { |err| format_schema_error(err) }.join('; ')
    "Invalid payload parameters: #{formatted_errors}"
  end

  def format_schema_error(error)
    case error['type']
    when 'required'
      missing = error.dig('details', 'missing_keys')&.join(', ')
      missing.present? ? "missing required field(s): #{missing}" : 'missing required fields'
    when 'type'
      pointer = error['data_pointer'].presence || 'payload'
      expected = error['schema']&.fetch('type', nil)
      "field '#{pointer}' must be of type #{expected}"
    else
      pointer = error['data_pointer'].presence || 'payload'
      "field '#{pointer}' failed validation (#{error['type']})"
    end
  end

  def execute_request(scout_tool, payload)
    method = scout_tool.http_method.to_s.downcase.to_sym
    headers = build_request_headers(scout_tool)
    sensitive_headers = determine_sensitive_headers(headers)
    body = (method == :post || payload.present?) && method != :get ? payload.to_json : nil

    response_body = +''
    SafeFetch.fetch(
      scout_tool.endpoint_url,
      method: method,
      body: body,
      headers: headers,
      sensitive_headers: sensitive_headers,
      max_bytes: MAX_RESPONSE_SIZE,
      validate_content_type: false
    ) do |result|
      response_body = result.tempfile.read
    end

    format_response(response_body)
  end

  def build_request_headers(scout_tool)
    headers = parse_auth_headers(scout_tool.auth_headers)
    headers['Content-Type'] ||= 'application/json' if scout_tool.http_method.to_s.upcase == 'POST'
    headers
  end

  def parse_auth_headers(auth)
    return {} if auth.blank?
    return auth.transform_keys(&:to_s) if auth.is_a?(Hash)

    parse_auth_header_string(auth.to_s.strip)
  end

  def parse_auth_header_string(auth_str)
    return { 'Authorization' => auth_str } unless auth_str.start_with?('{') && auth_str.end_with?('}')

    parse_json_or_yaml_headers(auth_str) || { 'Authorization' => auth_str }
  end

  def parse_json_or_yaml_headers(auth_str)
    parsed = JSON.parse(auth_str)
    return parsed.transform_keys(&:to_s) if parsed.is_a?(Hash)

    nil
  rescue JSON::ParserError
    parsed = YAML.safe_load(auth_str.gsub('=>', ': '))
    parsed.is_a?(Hash) ? parsed.transform_keys(&:to_s) : nil
  rescue StandardError
    nil
  end

  def determine_sensitive_headers(headers)
    headers.keys.select do |k|
      k.downcase.in?(%w[authorization cookie proxy-authorization api-key x-api-key token])
    end.presence || ['Authorization']
  end

  def format_response(response_body)
    return '' if response_body.blank?

    begin
      JSON.parse(response_body)
    rescue JSON::ParserError
      response_body
    end
  end

  def log_tool_error(scout_tool, tool_id, error)
    name = scout_tool&.name || 'unknown'
    Rails.logger.error "[Scout CallCustomApi] Error executing tool_id=#{tool_id} (#{name}): #{error.class} - #{error.message}"
  end
end
