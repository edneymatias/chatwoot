class Meta::PendingAttributionsSweeperJob < ApplicationJob
  queue_as :low

  def perform
    CampaignAttributionSetting.where(enabled: true).find_each do |setting|
      next if setting.provider_config['access_token'].blank?

      has_pending = setting.account.opportunities
                           .where(campaign_resolution_status: 'pending')
                           .exists?(['created_at < ?', 15.minutes.ago])

      Meta::DrainPendingAttributionsJob.perform_later(setting.account_id) if has_pending
    end
  end
end
