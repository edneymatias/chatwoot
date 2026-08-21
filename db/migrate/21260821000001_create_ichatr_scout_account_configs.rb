# frozen_string_literal: true

class CreateIchatrScoutAccountConfigs < ActiveRecord::Migration[7.0]
  # rubocop:disable Rails/DangerousColumnNames
  def change
    create_table :ichatr_scout_account_configs do |t|
      t.bigint :account_id, null: false
      t.integer :provider, null: false, default: 0
      t.string :model_name, null: false
      t.text :api_key, null: false
      t.timestamps
    end

    add_index :ichatr_scout_account_configs, :account_id, unique: true, name: 'index_ichatr_scout_account_configs_on_account_id'
    add_foreign_key :ichatr_scout_account_configs, :accounts, on_delete: :cascade

    remove_column :ichatr_scouts, :provider, :integer
    remove_column :ichatr_scouts, :model_name, :string
    remove_column :ichatr_scouts, :api_key_override, :text
  end
  # rubocop:enable Rails/DangerousColumnNames
end
