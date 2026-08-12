module Custom
  class CampaignResolutionJob < ApplicationJob
    queue_as :low

    def perform(opportunity_id)
      opportunity = Opportunity.find_by(id: opportunity_id)
      return unless opportunity
      return if opportunity.campaign_source_id.blank?
      return unless opportunity.campaign_resolution_status == 'pending'

      setting = opportunity.account.campaign_attribution_setting
      unless setting&.enabled? && setting.provider_config['access_token'].present?
        update_status(opportunity, 'failed')
        return
      end

      limiter = Meta::RateLimiter.new(opportunity.account)
      unless limiter.within_limit?
        retry_job wait: 1.minute
        return
      end

      limiter.track_request

      cached = Meta::CampaignResolutionCache.read(opportunity.campaign_source_id)
      if cached
        apply_resolution(opportunity, cached)
        return
      end

      client = Meta::GraphApiClient.new(setting.provider_config['access_token'])
      begin
        response = client.fetch_ad_details(opportunity.campaign_source_id)
        if response
          parsed = parse_meta_response(response)
          Meta::CampaignResolutionCache.write(opportunity.campaign_source_id, parsed)
          apply_resolution(opportunity, parsed)
        else
          update_status(opportunity, 'failed')
        end
      rescue StandardError => e
        raise e unless e.message == 'OAuthException'

        update_status(opportunity, 'failed')

        # T020 / FR-021: Disconnect on permanent OAuth failure
        setting = opportunity.account.campaign_attribution_setting
        if setting
          config = setting.provider_config.dup
          config.delete('access_token')
          setting.update!(provider_config: config, enabled: false)
        end
      end
    end

    private

    def parse_meta_response(response)
      {
        ad_id: response['id'],
        ad_name: response['name'],
        adset_id: response.dig('adset', 'id'),
        adset_name: response.dig('adset', 'name'),
        campaign_id: response.dig('campaign', 'id'),
        campaign_name: response.dig('campaign', 'name')
      }
    end

    def apply_resolution(opportunity, data)
      opportunity.update!(
        campaign_name: data[:campaign_name] || data['campaign_name'],
        campaign_adset_name: data[:adset_name] || data['adset_name'],
        campaign_ad_name: data[:ad_name] || data['ad_name'],
        campaign_resolution_status: 'resolved'
      )
    end

    def update_status(opportunity, status)
      opportunity.update!(campaign_resolution_status: status)
    end
  end
end
