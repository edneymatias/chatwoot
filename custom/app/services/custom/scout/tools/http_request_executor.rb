# frozen_string_literal: true

class Custom::Scout::Tools::HttpRequestExecutor
  MAX_RESPONSE_SIZE = 1.megabyte
  PREVIEW_TRUNCATE_LIMIT = 500

  Result = Struct.new(:success, :status, :raw_body, :formatted_response, :error, keyword_init: true) do
    def success? = success == true
    def truncated_raw_body(limit = PREVIEW_TRUNCATE_LIMIT) = raw_body&.truncate(limit)
    def truncated?(limit = PREVIEW_TRUNCATE_LIMIT) = raw_body.present? && raw_body.length > limit
  end

  def initialize(endpoint_url:, http_method: 'POST', **options)
    @endpoint_url = endpoint_url.to_s.strip
    @http_method = http_method.to_s.strip.presence || 'POST'
    @auth_type = options[:auth_type].to_s.strip.presence || 'none'
    @auth_headers = options[:auth_headers]
    @response_template = options[:response_template].presence
    @payload = normalize_payload(options[:payload])
  end

  def self.execute(...) = new(...).execute

  def self.from_tool(tool, payload: {})
    new(
      endpoint_url: tool.endpoint_url,
      http_method: tool.http_method,
      auth_type: tool.auth_type,
      auth_headers: tool.auth_headers,
      response_template: tool.response_template,
      payload: payload
    )
  end

  def execute
    final_url, request_body = prepare_url_and_body
    headers = build_request_headers
    method_sym = @http_method.downcase.to_sym

    response_body = perform_fetch(final_url, method_sym, request_body, headers)
    formatted = format_response(response_body)

    Result.new(success: true, status: 200, raw_body: response_body, formatted_response: formatted, error: nil)
  rescue StandardError => e
    handle_execution_error(e)
  end

  private

  def normalize_payload(payload)
    return {} if payload.blank?
    return parse_string_payload(payload) if payload.is_a?(String)
    return payload.to_unsafe_h.deep_stringify_keys if payload.respond_to?(:to_unsafe_h)

    payload.respond_to?(:deep_stringify_keys) ? payload.deep_stringify_keys : payload
  end

  def parse_string_payload(payload)
    parsed = JSON.parse(payload)
    parsed.is_a?(Hash) ? parsed.deep_stringify_keys : parsed
  rescue JSON::ParserError
    {}
  end

  def prepare_url_and_body
    rendered_url, remaining_payload = resolve_url_and_consumed_payload
    method_sym = @http_method.downcase.to_sym

    if method_sym == :get
      [build_get_url(rendered_url, remaining_payload), nil]
    else
      [rendered_url, remaining_payload.present? ? remaining_payload.to_json : nil]
    end
  end

  def resolve_url_and_consumed_payload
    return [@endpoint_url, @payload] unless @endpoint_url.include?('{{')

    consumed_keys = @endpoint_url.scan(/\{\{\s*([a-zA-Z0-9_]+)/).flatten.uniq
    liquid_template = Liquid::Template.parse(@endpoint_url, error_mode: :strict)
    rendered_url = liquid_template.render(@payload, registers: {}, strict_variables: true, strict_filters: true)

    raise "Template rendering failed: #{liquid_template.errors.map(&:message).join(', ')}" if liquid_template.errors.present?

    [rendered_url, @payload.except(*consumed_keys)]
  end

  def build_get_url(base_url, query_params_hash)
    return base_url if query_params_hash.blank?

    query_string = query_params_hash.map do |key, value|
      formatted_val = format_query_param_value(value)
      "#{ERB::Util.url_encode(key.to_s)}=#{ERB::Util.url_encode(formatted_val)}"
    end.join('&')

    delimiter = base_url.include?('?') ? '&' : '?'
    "#{base_url}#{delimiter}#{query_string}"
  end

  def format_query_param_value(value)
    if value.is_a?(Hash) || value.is_a?(Array)
      value.to_json
    else
      value.nil? ? '' : value.to_s
    end
  end

  def build_request_headers
    headers = Custom::Scout::Tools::AuthHeaderBuilder.build(auth_type: @auth_type, auth_headers: @auth_headers)
    method_upper = @http_method.to_s.upcase
    headers['Content-Type'] ||= 'application/json' if %w[POST PUT PATCH].include?(method_upper)
    headers
  end

  def perform_fetch(url, method_sym, request_body, headers)
    response_body = +''
    SafeFetch.fetch(
      url,
      method: method_sym,
      body: request_body,
      headers: headers,
      sensitive_headers: headers.keys.select { |k| k.downcase.in?(%w[authorization cookie proxy-authorization api-key x-api-key token]) }.presence ||
                         ['Authorization'],
      max_bytes: MAX_RESPONSE_SIZE,
      validate_content_type: false
    ) do |result|
      response_body = result.tempfile.read
    end
    response_body
  end

  def format_response(response_body)
    return '' if response_body.blank?
    return render_response_template(response_body) if @response_template.present?

    parse_json_or_raw(response_body)
  end

  def render_response_template(response_body)
    parsed_json = parse_json_response(response_body)
    context = { 'response' => parsed_json, 'r' => parsed_json }
    liquid_template = Liquid::Template.parse(@response_template, error_mode: :strict)
    rendered = liquid_template.render(context.deep_stringify_keys, registers: {}, strict_variables: true, strict_filters: true)

    raise "Template rendering failed: #{liquid_template.errors.map(&:message).join(', ')}" if liquid_template.errors.present?

    rendered
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

  def handle_execution_error(error)
    return handle_http_error(error) if error.is_a?(SafeFetch::HttpError)

    msg = build_error_message(error)
    Result.new(success: false, status: nil, raw_body: nil, formatted_response: nil, error: msg)
  end

  def handle_http_error(error)
    status_code = error.message[/^\d+/]&.to_i || 400
    Result.new(
      success: false,
      status: status_code,
      raw_body: error.message,
      formatted_response: nil,
      error: "External system returned error status: #{error.message}"
    )
  end

  def build_error_message(error)
    case error
    when SafeFetch::FileTooLargeError
      "Error: Response exceeded maximum allowed size (#{error.message})"
    when SafeFetch::FetchError
      "Request failed or timed out while contacting the external system: #{error.message}"
    when SafeFetch::InvalidUrlError, SafeFetch::UnsafeUrlError
      "Invalid or unsafe URL: #{error.message}"
    when Liquid::SyntaxError, Liquid::UndefinedVariable, Liquid::UndefinedFilter
      "Template rendering failed: #{error.message}"
    else
      fallback = 'Error: An error occurred while executing the external tool.'
      error.message.start_with?('Template rendering failed', 'Error:') ? error.message : fallback
    end
  end
end
