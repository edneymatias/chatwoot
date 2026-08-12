module Custom::AutomationRules::ActionService
  def self.process_campaign_attribution(opportunity, first_message)
    return unless first_message

    referral = first_message.content_attributes&.dig('referral')
    return unless referral

    source_url = referral['source_url']
    campaign_platform = nil
    campaign_source_id = referral['ad_id'] || referral['source_id']

    if source_url.present?
      if source_url.include?('facebook') || source_url.include?('fb')
        campaign_platform = 'facebook'
      elsif source_url.include?('instagram') || source_url.include?('ig')
        campaign_platform = 'instagram'
      end

      if campaign_source_id.blank?
        uri = begin
          URI.parse(source_url)
        rescue StandardError
          nil
        end
        if uri && uri.query
          parsed_query = CGI.parse(uri.query)
          campaign_source_id = parsed_query['ad_id']&.first
        end
      end
    end

    campaign_resolution_status = campaign_source_id.present? ? 'pending' : 'not_applicable'

    opportunity.update!(
      campaign_platform: campaign_platform,
      campaign_source_id: campaign_source_id,
      campaign_source_url: source_url,
      campaign_resolution_status: campaign_resolution_status
    )

    return unless campaign_source_id.present? && opportunity.account.campaign_attribution_setting&.enabled?

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

      first_message = @conversation.messages.incoming.first
      Custom::AutomationRules::ActionService.process_campaign_attribution(opportunity, first_message)
    rescue ActiveRecord::RecordNotUnique
      # Idempotent no-op
    end
  end

  def resolve_assignee_id(assignee_id_param)
    if assignee_id_param == 'same_as_conversation'
      @conversation.assignee_id
    else
      assignee_id_param
    end
  end
end
