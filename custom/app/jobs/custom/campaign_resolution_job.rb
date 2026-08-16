class Custom::CampaignResolutionJob < ApplicationJob
  queue_as :low

  def perform(opportunity_id, force: false)
    opportunity = Opportunity.find_by(id: opportunity_id)
    return unless opportunity
    return if opportunity.campaign_source_id.blank?
    return unless opportunity.campaign_resolution_status == 'pending' || force

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
    if cached && (!force || cached[:thumbnail_url].present? || cached['thumbnail_url'].present?)
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
    rescue Meta::AuthenticationError => e
      Rails.logger.warn("[Meta::CampaignResolutionJob] Token revoked for Account #{opportunity.account_id}: #{e.message}")
      update_status(opportunity, 'failed')
      disconnect_setting(opportunity.account.campaign_attribution_setting)
    rescue Meta::RateLimitError => e
      Rails.logger.warn("[Meta::CampaignResolutionJob] Rate limit hit for Account #{opportunity.account_id}: #{e.message}")
      retry_job wait: 2.minutes
    rescue Meta::NodeNotFoundError => e
      Rails.logger.info("[Meta::CampaignResolutionJob] Node not found for Opportunity #{opportunity.id} (#{opportunity.campaign_source_id}): #{e.message}")
      update_status(opportunity, 'failed')
    rescue Meta::ApiError, StandardError => e
      Rails.logger.error("[Meta::CampaignResolutionJob] Error resolving Opportunity #{opportunity.id}: #{e.message}")
      update_status(opportunity, 'failed')
    end
  end

  private

  def parse_meta_response(response)
    creative = response['creative'] || {}
    thumbnail_url = creative['thumbnail_url'] || creative['image_url']

    {
      ad_id: response['id'],
      ad_name: response['name'],
      adset_id: response.dig('adset', 'id'),
      adset_name: response.dig('adset', 'name'),
      campaign_id: response.dig('campaign', 'id'),
      campaign_name: response.dig('campaign', 'name'),
      thumbnail_url: thumbnail_url
    }
  end

  def apply_resolution(opportunity, data)
    opportunity.update!(
      campaign_name: data[:campaign_name] || data['campaign_name'],
      campaign_adset_name: data[:adset_name] || data['adset_name'],
      campaign_ad_name: data[:ad_name] || data['ad_name'],
      campaign_thumbnail_url: data[:thumbnail_url] || data['thumbnail_url'] || opportunity.campaign_thumbnail_url,
      campaign_resolution_status: 'resolved'
    )
    thumb = opportunity.campaign_thumbnail_url
    Meta::AttachCampaignThumbnailJob.perform_later(opportunity.id, thumb) if thumb.present? && !opportunity.campaign_thumbnail.attached?
  end

  def update_status(opportunity, status)
    opportunity.update!(campaign_resolution_status: status)
  end

  def disconnect_setting(setting)
    return unless setting

    config = setting.provider_config.dup
    config.delete('access_token')
    setting.update!(provider_config: config, enabled: false)
  end
end
