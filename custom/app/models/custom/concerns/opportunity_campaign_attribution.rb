# frozen_string_literal: true

module Custom::Concerns::OpportunityCampaignAttribution
  extend ActiveSupport::Concern

  included do
    has_one_attached :campaign_thumbnail
  end

  def thumbnail_url
    if campaign_thumbnail.attached?
      Rails.application.routes.url_helpers.rails_blob_url(campaign_thumbnail, only_path: true)
    else
      campaign_thumbnail_url
    end
  end

  def campaign_json
    {
      'campaign_source_id' => campaign_source_id,
      'campaign_source_url' => campaign_source_url,
      'campaign_platform' => campaign_platform,
      'campaign_name' => campaign_name,
      'campaign_adset_name' => campaign_adset_name,
      'campaign_ad_name' => campaign_ad_name,
      'campaign_headline' => campaign_headline,
      'campaign_body' => campaign_body,
      'campaign_thumbnail_url' => thumbnail_url,
      'campaign_resolution_status' => campaign_resolution_status
    }
  end
end
