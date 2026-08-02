class AddValueAndCustomAttributesToMatiasOpportunities < ActiveRecord::Migration[7.1]
  def change
    add_column :matias_opportunities, :custom_attributes, :jsonb, default: {}
    add_column :matias_opportunities, :value, :decimal
  end
end
