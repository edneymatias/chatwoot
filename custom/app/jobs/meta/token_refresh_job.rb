module Meta
  class TokenRefreshJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform
      CampaignAttributionSetting.where(enabled: true).where.not(provider_config: nil).find_each do |setting|
        config = setting.provider_config
        next unless config['access_token'].present? && config['expires_at'].present?

        expires_at = Time.parse(config['expires_at'])
        if expires_at < 10.days.from_now
          begin
            new_token_data = Meta::MarketingAuthorizationService.new.exchange_for_long_lived(config['access_token'])
            setting.update!(provider_config: new_token_data) if new_token_data
          rescue StandardError => e
            Rails.logger.error "Failed to refresh Meta token for account #{setting.account_id}: #{e.message}"
          end
        end
      end
    end
  end
end
