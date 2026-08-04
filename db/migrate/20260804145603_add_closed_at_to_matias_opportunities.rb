class AddClosedAtToMatiasOpportunities < ActiveRecord::Migration[7.1]
  def change
    add_column :matias_opportunities, :closed_at, :datetime
    add_index :matias_opportunities, %i[account_id closed_at]
  end
end
