# frozen_string_literal: true

class AddResponseAuditorFlagToIchatrScouts < ActiveRecord::Migration[7.0]
  def up
    change_table :ichatr_scouts, bulk: true do |t|
      t.boolean :feature_response_auditor, null: false, default: false
    end
  end

  def down
    change_table :ichatr_scouts, bulk: true do |t|
      t.remove :feature_response_auditor
    end
  end
end
