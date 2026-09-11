# frozen_string_literal: true

class AddAuthTypeToIchatrScoutTools < ActiveRecord::Migration[7.0]
  def change
    add_column :ichatr_scout_tools, :auth_type, :string, default: 'none', null: false
  end
end
