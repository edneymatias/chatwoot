# frozen_string_literal: true

module Custom::AutomationRules::ActionService
  def self.process_campaign_attribution(opportunity, first_message)
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
    platform = extract_platform(source_url)
    source_id = referral['ad_id'] || referral['source_id'] || extract_source_id_from_url(source_url)

    {
      platform: platform,
      source_id: source_id,
      source_url: source_url,
      headline: referral['headline'],
      body: referral['body'],
      thumbnail_url: referral['thumbnail_url'] || referral['image_url'] || referral['video_url'],
      source_type: referral['source_type']
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
    status = compute_resolution_status(opportunity, data[:source_id])

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

  def self.compute_resolution_status(opportunity, source_id)
    if opportunity.campaign_resolution_status == 'resolved'
      'resolved'
    elsif source_id.present?
      'pending'
    else
      'not_applicable'
    end
  end

  def self.dispatch_resolution_job_if_needed(opportunity, source_id, status)
    return unless source_id.present? && status == 'pending' && opportunity.account.campaign_attribution_setting&.enabled?

    Custom::CampaignResolutionJob.perform_later(opportunity.id)
  end

  private

  def create_opportunity(params)
    return if Opportunity.exists?(origin_conversation_id: @conversation.id)

    stage_id = params[0]
    assignee_id_param = params[1]&.presence

    title = "Oportunidade ##{@conversation.display_id}"
    assignee_id = resolve_assignee_id(assignee_id_param)

    begin
      opportunity = Opportunity.create!(
        account: @conversation.account,
        contact: @conversation.contact,
        pipeline_stage_id: stage_id,
        origin_conversation: @conversation,
        status: :open,
        title: title,
        assignee_id: assignee_id
      )

      referral_message = find_referral_message
      Custom::AutomationRules::ActionService.process_campaign_attribution(opportunity, referral_message)
    rescue ActiveRecord::RecordNotUnique
      # Idempotent no-op
    end
  end

  def find_referral_message
    @conversation.messages.incoming
                 .where("(content_attributes #>> '{}')::jsonb -> 'referral' IS NOT NULL")
                 .order(created_at: :asc)
                 .first || @conversation.messages.incoming.order(created_at: :asc).first
  end

  def resolve_assignee_id(assignee_id_param)
    if assignee_id_param == 'same_as_conversation'
      @conversation.assignee_id
    else
      assignee_id_param
    end
  end
end
