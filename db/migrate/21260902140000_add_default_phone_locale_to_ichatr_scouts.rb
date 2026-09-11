# frozen_string_literal: true

class AddDefaultPhoneLocaleToIchatrScouts < ActiveRecord::Migration[7.0]
  def up
    change_table :ichatr_scouts, bulk: true do |t|
      t.string :default_country_code, default: '+55'
      t.string :default_area_code
    end
  end

  def down
    change_table :ichatr_scouts, bulk: true do |t|
      t.remove :default_country_code
      t.remove :default_area_code
    end
  end
end
