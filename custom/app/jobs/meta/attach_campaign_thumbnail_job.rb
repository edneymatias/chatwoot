require 'open-uri'

class Meta::AttachCampaignThumbnailJob < ApplicationJob
  queue_as :low

  def perform(opportunity_id, thumbnail_url)
    opportunity = Opportunity.find_by(id: opportunity_id)
    return unless opportunity
    return if thumbnail_url.blank?
    return if opportunity.campaign_thumbnail.attached?

    downloaded_file = URI.parse(thumbnail_url).open(
      read_timeout: 5,
      open_timeout: 3
    )

    filename = "opportunity_#{opportunity.id}_thumbnail.jpg"
    opportunity.campaign_thumbnail.attach(
      io: downloaded_file,
      filename: filename,
      content_type: downloaded_file.content_type || 'image/jpeg'
    )
  rescue StandardError => e
    Rails.logger.warn("[Meta::AttachCampaignThumbnailJob] Failed to attach thumbnail for Opportunity #{opportunity_id}: #{e.message}")
  end
end
