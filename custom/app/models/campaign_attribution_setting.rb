class CampaignAttributionSetting < ApplicationRecord
  self.table_name = 'ichatr_campaign_attribution_settings'

  belongs_to :account

  validates :account_id, uniqueness: true
end
