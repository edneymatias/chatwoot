# frozen_string_literal: true

class AddRoleAndScopeToIchatrScouts < ActiveRecord::Migration[7.0]
  def change
    add_column :ichatr_scouts, :role, :text
    add_column :ichatr_scouts, :scope, :text
  end
end
