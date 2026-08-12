module Meta
  class GraphApiClient
    include HTTParty
    base_uri 'https://graph.facebook.com'

    def initialize(access_token)
      @access_token = access_token
      @api_version = GlobalConfigService.load('META_MARKETING_API_VERSION', 'v22.0')
    end

    def fetch_ad_details(ad_id)
      response = self.class.get(
        "/#{@api_version}/#{ad_id}",
        query: {
          fields: 'name,adset{id,name},campaign{id,name},creative{effective_object_story_id,object_story_spec}',
          access_token: @access_token
        }
      )

      # If unauthorized (e.g. token expired), we should raise so that rate limiter or other logic handles it.
      # But since OAuthException triggers a failed state, let's raise if it's an OAuth error.
      unless response.success?
        error_type = response.parsed_response.dig('error', 'type')
        raise StandardError, 'OAuthException' if error_type == 'OAuthException'

        return nil
      end

      response.parsed_response.with_indifferent_access
    end
  end
end
