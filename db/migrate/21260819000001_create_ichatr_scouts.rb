# frozen_string_literal: true

class CreateIchatrScouts < ActiveRecord::Migration[7.0]
  # rubocop:disable Rails/DangerousColumnNames
  def up
    create_table :ichatr_scouts do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.text :persona
      t.integer :provider, null: false
      t.string :model_name, null: false
      t.text :api_key_override
      t.bigint :default_pipeline_stage_id
      t.integer :responses_quota, null: false, default: -1
      t.integer :responses_consumed, null: false, default: 0
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end

    add_index :ichatr_scouts, :account_id, name: 'index_ichatr_scouts_on_account_id'
    add_index :ichatr_scouts, :default_pipeline_stage_id, name: 'index_ichatr_scouts_on_default_pipeline_stage_id'

    add_foreign_key :ichatr_scouts, :accounts, on_delete: :cascade
    add_foreign_key :ichatr_scouts, :ichatr_pipeline_stages, column: :default_pipeline_stage_id, on_delete: :nullify
  end
  # rubocop:enable Rails/DangerousColumnNames

  def down
    drop_table :ichatr_scouts, if_exists: true
  end
end
