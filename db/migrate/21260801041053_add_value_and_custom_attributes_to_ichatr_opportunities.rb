class AddValueAndCustomAttributesToIchatrOpportunities < ActiveRecord::Migration[7.1]
  def change
    add_column :ichatr_opportunities, :custom_attributes, :jsonb, default: {}
    add_column :ichatr_opportunities, :value, :decimal
  end
end
