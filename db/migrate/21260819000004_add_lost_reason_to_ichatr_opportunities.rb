# frozen_string_literal: true

class AddLostReasonToIchatrOpportunities < ActiveRecord::Migration[7.0]
  def up
    add_column :ichatr_opportunities, :lost_reason, :string
  end

  def down
    remove_column :ichatr_opportunities, :lost_reason, :string
  end
end
