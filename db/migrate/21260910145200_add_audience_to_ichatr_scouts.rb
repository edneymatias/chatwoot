# frozen_string_literal: true

class AddAudienceToIchatrScouts < ActiveRecord::Migration[7.0]
  def change
    add_column :ichatr_scouts, :audience, :jsonb, null: false, default: []
  end
end
