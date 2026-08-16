# frozen_string_literal: true

class Custom::CampaignResolutionJob < ApplicationJob
  queue_as :low

  def perform(opportunity_id, force: false)
    opportunity = Opportunity.find_by(id: opportunity_id)
    return unless opportunity_eligible?(opportunity, force: force)

    setting = opportunity.account.campaign_attribution_setting
    return update_status(opportunity, 'failed') unless setting_active?(setting)
    return retry_job(wait: 1.minute) unless rate_limit_available?(opportunity.account)

    resolve_opportunity(opportunity, setting, force: force)
  end

  private

  def opportunity_eligible?(opportunity, force:)
    return false if opportunity&.campaign_source_id.blank?

    opportunity.campaign_resolution_status == 'pending' || force
  end

  def setting_active?(setting)
    setting&.enabled? && setting.provider_config['access_token'].present?
  end

  def rate_limit_available?(account)
    limiter = Meta::RateLimiter.new(account)
    return false unless limiter.within_limit?

    limiter.track_request
    true
  end

  def resolve_opportunity(opportunity, setting, force:)
    cached = Meta::CampaignResolutionCache.read(opportunity.campaign_source_id)
    if cached && (!force || cached[:thumbnail_url].present? || cached['thumbnail_url'].present?)
      apply_resolution(opportunity, cached)
      return
    end

    fetch_and_apply_remote(opportunity, setting)
  end

  def fetch_and_apply_remote(opportunity, setting)
    client = Meta::GraphApiClient.new(setting.provider_config['access_token'])
    response = client.fetch_ad_details(opportunity.campaign_source_id)

    if response
      parsed = parse_meta_response(response)
      Meta::CampaignResolutionCache.write(opportunity.campaign_source_id, parsed)
      apply_resolution(opportunity, parsed)
    else
      update_status(opportunity, 'failed')
    end
  rescue Meta::AuthenticationError => e
    handle_auth_error(opportunity, e)
  rescue Meta::RateLimitError => e
    handle_rate_limit_error(opportunity, e)
  rescue Meta::NodeNotFoundError => e
    handle_node_not_found(opportunity, e)
  rescue Meta::ApiError, StandardError => e
    handle_generic_error(opportunity, e)
  end

  def handle_auth_error(opportunity, error)
    Rails.logger.warn("[Meta::CampaignResolutionJob] Token revoked for Account #{opportunity.account_id}: #{error.message}")
    update_status(opportunity, 'failed')
    disconnect_setting(opportunity.account.campaign_attribution_setting)
  end

  def handle_rate_limit_error(opportunity, error)
    Rails.logger.warn("[Meta::CampaignResolutionJob] Rate limit hit for Account #{opportunity.account_id}: #{error.message}")
    retry_job wait: 2.minutes
  end

  def handle_node_not_found(opportunity, error)
    Rails.logger.info("[Meta::CampaignResolutionJob] Node not found for Opportunity #{opportunity.id}: #{error.message}")
    update_status(opportunity, 'failed')
  end

  def handle_generic_error(opportunity, error)
    Rails.logger.error("[Meta::CampaignResolutionJob] Error resolving Opportunity #{opportunity.id}: #{error.message}")
    update_status(opportunity, 'failed')
  end

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
