class Meta::DrainPendingAttributionsJob < ApplicationJob
  queue_as :low

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return unless account

    setting = account.campaign_attribution_setting
    return unless setting&.enabled? && setting.provider_config['access_token'].present?

    pending_opportunities = account.opportunities
                                   .where(campaign_resolution_status: 'pending')
                                   .where.not(campaign_source_id: [nil, ''])

    pending_opportunities.find_each.with_index do |opportunity, idx|
      delay = (idx / 5).seconds
      Custom::CampaignResolutionJob.set(wait: delay).perform_later(opportunity.id)
    end
  end
end
