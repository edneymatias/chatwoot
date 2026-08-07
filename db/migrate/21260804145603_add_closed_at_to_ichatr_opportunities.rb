class AddClosedAtToIchatrOpportunities < ActiveRecord::Migration[7.1]
  def change
    add_column :ichatr_opportunities, :closed_at, :datetime
    add_index :ichatr_opportunities, %i[account_id closed_at]
  end
end
