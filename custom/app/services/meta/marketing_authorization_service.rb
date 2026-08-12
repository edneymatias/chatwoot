module Meta
  class MarketingAuthorizationService
    include HTTParty
    base_uri 'https://graph.facebook.com'

    def initialize(code = nil)
      @code = code
      @app_id = GlobalConfigService.load('META_MARKETING_APP_ID', '')
      @app_secret = GlobalConfigService.load('META_MARKETING_APP_SECRET', '')
      @api_version = GlobalConfigService.load('META_MARKETING_API_VERSION', 'v22.0')
    end

    def exchange_code_for_long_lived_token
      short_lived_token = exchange_code_for_token
      return nil unless short_lived_token

      exchange_for_long_lived(short_lived_token)
    end

    def exchange_for_long_lived(short_lived_token)
      response = self.class.get("/#{@api_version}/oauth/access_token", query: {
                                  grant_type: 'fb_exchange_token',
                                  client_id: @app_id,
                                  client_secret: @app_secret,
                                  fb_exchange_token: short_lived_token
                                })

      return nil unless response.success?

      {
        'access_token' => response.parsed_response['access_token'],
        'expires_at' => (Time.current + response.parsed_response['expires_in'].to_i.seconds).iso8601
      }
    end

    private

    def exchange_code_for_token
      response = self.class.get("/#{@api_version}/oauth/access_token", query: {
                                  client_id: @app_id,
                                  client_secret: @app_secret,
                                  redirect_uri: '',
                                  code: @code
                                })

      return nil unless response.success?

      response.parsed_response['access_token']
    end
  end
end
