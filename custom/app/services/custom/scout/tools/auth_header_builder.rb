# frozen_string_literal: true

require 'base64'

class Custom::Scout::Tools::AuthHeaderBuilder
  def initialize(auth_type: 'none', auth_headers: nil)
    @auth_type = auth_type.to_s.strip.presence || 'none'
    @auth_headers = auth_headers
  end

  def self.build(...) = new(...).build

  def build
    parsed = parse_auth_headers(@auth_headers)
    return {} if @auth_type == 'none'

    case @auth_type
    when 'bearer' then build_bearer_header(parsed)
    when 'basic' then build_basic_header(parsed)
    when 'api_key' then build_api_key_header(parsed)
    else parsed
    end
  end

  private

  def build_bearer_header(parsed)
    token = parsed['token'].presence || parsed['Authorization']&.sub(/\ABearer\s+/i, '')
    token.present? ? { 'Authorization' => "Bearer #{token}" } : {}
  end

  def build_basic_header(parsed)
    user = parsed['username']
    pass = parsed['password']
    return {} if user.blank? && pass.blank?

    { 'Authorization' => "Basic #{Base64.strict_encode64("#{user}:#{pass}")}" }
  end

  def build_api_key_header(parsed)
    header_name = parsed['header_name']
    header_value = parsed['header_value']
    return {} if header_name.blank? || header_value.blank?

    { header_name => header_value }
  end

  def parse_auth_headers(auth)
    return {} if auth.blank?
    return auth.to_unsafe_h.transform_keys(&:to_s) if auth.respond_to?(:to_unsafe_h)
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
end
