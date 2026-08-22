# frozen_string_literal: true

class Custom::Scout::Tools::CallCustomApi < Custom::Scout::Tools::BaseTool
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

    result = Custom::Scout::Tools::HttpRequestExecutor.from_tool(scout_tool, payload: normalized_payload).execute
    if result.success?
      result.formatted_response
    else
      log_tool_error(scout_tool, tool_id, result.error)
      result.error
    end
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

  def log_tool_error(scout_tool, tool_id, error)
    name = scout_tool&.name || 'unknown'
    err_str = error.is_a?(Exception) ? "#{error.class} - #{error.message}" : error.to_s
    Rails.logger.error "[Scout CallCustomApi] Error executing tool_id=#{tool_id} (#{name}): #{err_str}"
  end
end
