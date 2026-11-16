# frozen_string_literal: true

class Custom::ReferralAttributionService
  def self.process(opportunity, first_message)
    return unless first_message

    referral = first_message.content_attributes&.dig('referral')
    return unless referral

    data = extract_referral_data(referral)

    if organic_referral?(data, referral)
      persist_organic_referral(opportunity, data)
    else
      persist_paid_referral(opportunity, data)
    end
  end

  def self.extract_referral_data(referral)
    source_url = referral['source_url']
    platform = extract_platform(source_url) || extract_platform_from_source_app(referral['source_app'])
    source_id = referral['ad_id'] || referral['source_id'] || extract_source_id_from_url(source_url)

    {
      platform: platform,
      source_id: source_id,
      source_url: source_url,
      headline: referral['headline'],
      body: referral['body'],
      thumbnail_url: referral['thumbnail_url'] || referral['image_url'] || referral['video_url'],
      source_type: referral['source_type'],
      ad_signal: ad_signal?(referral)
    }
  end

  def self.extract_platform(source_url)
    return nil if source_url.blank?

    if source_url.include?('facebook') || source_url.include?('fb')
      'facebook'
    elsif source_url.include?('instagram') || source_url.include?('ig')
      'instagram'
    end
  end

  # WhatsApp sends source_app ("instagram"/"facebook") even when it omits the ad card (externalAdReply),
  # so it is the only platform hint left for click-to-WhatsApp leads that arrive without an ad id.
  def self.extract_platform_from_source_app(source_app)
    source_app if %w[facebook instagram].include?(source_app)
  end

  # The message came from a Meta ad, even when the referral carries no ad id to resolve.
  def self.ad_signal?(referral)
    referral['source_type'] == 'ad' ||
      referral['conversion_source'] == 'FB_Ads' ||
      referral['entry_point_conversion_source'] == 'ctwa_ad'
  end

  def self.extract_source_id_from_url(source_url)
    return nil if source_url.blank?

    uri = begin
      URI.parse(source_url)
    rescue StandardError
      nil
    end
    return nil unless uri&.query

    CGI.parse(uri.query)['ad_id']&.first
  end

  def self.organic_referral?(data, referral)
    (data[:source_type] == 'post' || referral['story_fbid'].present?) ||
      (data[:source_type] != 'ad' && data[:source_id].blank? && (data[:headline].present? || data[:body].present?))
  end

  def self.persist_organic_referral(opportunity, data)
    opportunity.update!(
      campaign_platform: data[:platform],
      campaign_source_id: data[:source_id],
      campaign_source_url: data[:source_url],
      campaign_headline: data[:headline],
      campaign_body: data[:body],
      campaign_thumbnail_url: data[:thumbnail_url],
      campaign_resolution_status: 'organic_post'
    )
    Meta::AttachCampaignThumbnailJob.perform_later(opportunity.id, data[:thumbnail_url]) if data[:thumbnail_url].present?
  end

  def self.persist_paid_referral(opportunity, data)
    status = compute_resolution_status(opportunity, data)

    opportunity.update!(
      campaign_platform: data[:platform],
      campaign_source_id: data[:source_id],
      campaign_source_url: data[:source_url],
      campaign_headline: data[:headline],
      campaign_body: data[:body],
      campaign_thumbnail_url: data[:thumbnail_url],
      campaign_resolution_status: status
    )

    Meta::AttachCampaignThumbnailJob.perform_later(opportunity.id, data[:thumbnail_url]) if data[:thumbnail_url].present?
    dispatch_resolution_job_if_needed(opportunity, data[:source_id], status)
  end

  def self.compute_resolution_status(opportunity, data)
    if opportunity.campaign_resolution_status == 'resolved'
      'resolved'
    elsif data[:source_id].present?
      'pending'
    elsif data[:ad_signal]
      'unattributed_ad'
    else
      'not_applicable'
    end
  end

  def self.dispatch_resolution_job_if_needed(opportunity, source_id, status)
    return unless source_id.present? && status == 'pending' && opportunity.account.campaign_attribution_setting&.enabled?

    Custom::CampaignResolutionJob.perform_later(opportunity.id)
  end
end
