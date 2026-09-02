# frozen_string_literal: true

class AddTrigramSearchIndexToIchatrOpportunities < ActiveRecord::Migration[7.1]
  def change
    add_index :ichatr_opportunities,
              %i[title campaign_name campaign_adset_name campaign_ad_name],
              using: :gin,
              opclass: :gin_trgm_ops,
              name: 'index_ichatr_opportunities_on_title_and_campaign_trgm'
  end
end
