# frozen_string_literal: true

class Meta::GraphApiClient
  include HTTParty
  base_uri 'https://graph.facebook.com'

  AUTH_SUBCODES = [458, 460, 463, 467, 490].freeze
  RATE_LIMIT_CODES = [17, 32, 613].freeze

  def initialize(access_token)
    @access_token = access_token
    @api_version = GlobalConfigService.load('META_MARKETING_API_VERSION', 'v22.0')
  end

  def fetch_ad_details(ad_id)
    response = self.class.get(
      "/#{@api_version}/#{ad_id}",
      query: {
        fields: 'name,adset{id,name},campaign{id,name},creative{effective_object_story_id,object_story_spec,thumbnail_url,image_url}',
        access_token: @access_token
      }
    )

    handle_error(response) unless response.success?

    response.parsed_response.with_indifferent_access
  end

  private

  def handle_error(response)
    error_body = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
    code = error_body&.dig('code')
    subcode = error_body&.dig('error_subcode')
    error_type = error_body&.dig('type')
    message = error_body&.dig('message') || "Meta API HTTP #{response.code}"
    params = { code: code, error_subcode: subcode, error_type: error_type, raw_error: error_body }

    raise_classified_error(response, message, params)
  end

  def raise_classified_error(response, message, params)
    code = params[:code]
    subcode = params[:error_subcode]

    if code == 190 || AUTH_SUBCODES.include?(subcode)
      raise Meta::AuthenticationError.new(message, **params)
    elsif RATE_LIMIT_CODES.include?(code) || response.code == 429
      raise Meta::RateLimitError.new(message, **params)
    elsif code == 100 || response.code == 404
      raise Meta::NodeNotFoundError.new(message, **params)
    else
      raise Meta::ApiError.new(message, **params)
    end
  end
end
