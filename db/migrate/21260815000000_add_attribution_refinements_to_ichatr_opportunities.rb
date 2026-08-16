class AddAttributionRefinementsToIchatrOpportunities < ActiveRecord::Migration[7.0]
  def change
    add_column :ichatr_opportunities, :campaign_headline, :string unless column_exists?(:ichatr_opportunities, :campaign_headline)
    add_column :ichatr_opportunities, :campaign_body, :text unless column_exists?(:ichatr_opportunities, :campaign_body)
    add_column :ichatr_opportunities, :campaign_thumbnail_url, :text unless column_exists?(:ichatr_opportunities, :campaign_thumbnail_url)
  end
end
