# frozen_string_literal: true

class AddCommunicationStyleToIchatrScouts < ActiveRecord::Migration[7.0]
  def change
    add_column :ichatr_scouts, :tone, :integer, default: 0, null: false
    add_column :ichatr_scouts, :response_length, :integer, default: 0, null: false
    add_column :ichatr_scouts, :greeting, :text
  end
end
