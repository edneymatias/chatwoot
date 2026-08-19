# frozen_string_literal: true

class AddEnabledToIchatrScoutTools < ActiveRecord::Migration[7.0]
  def change
    add_column :ichatr_scout_tools, :enabled, :boolean, default: true, null: false
  end
end
