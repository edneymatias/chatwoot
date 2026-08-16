class CreateIchatrCampaignAttributionSettings < ActiveRecord::Migration[7.0]
  def change
    create_table :ichatr_campaign_attribution_settings do |t|
      t.bigint :account_id, null: false
      t.boolean :enabled, default: false, null: false
      t.jsonb :provider_config, default: {}

      t.timestamps
    end

    add_index :ichatr_campaign_attribution_settings, :account_id, unique: true
  end
end
