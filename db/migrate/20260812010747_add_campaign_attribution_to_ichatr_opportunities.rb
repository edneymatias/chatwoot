class AddCampaignAttributionToIchatrOpportunities < ActiveRecord::Migration[7.0]
  def change
    add_column :ichatr_opportunities, :campaign_source_id, :string
    add_column :ichatr_opportunities, :campaign_source_url, :string
    add_column :ichatr_opportunities, :campaign_platform, :string
    add_column :ichatr_opportunities, :campaign_name, :string
    add_column :ichatr_opportunities, :campaign_adset_name, :string
    add_column :ichatr_opportunities, :campaign_ad_name, :string
    add_column :ichatr_opportunities, :campaign_resolution_status, :string

    add_index :ichatr_opportunities, :campaign_resolution_status,
              where: "campaign_resolution_status IS NULL OR campaign_resolution_status != 'not_applicable'"
  end
end
