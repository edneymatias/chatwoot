# frozen_string_literal: true

class CreateIchatrScoutTools < ActiveRecord::Migration[7.0]
  def up
    create_table :ichatr_scout_tools do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.text :description, null: false
      t.string :endpoint_url, null: false
      t.string :http_method, null: false
      t.text :auth_headers
      t.jsonb :parameter_schema, null: false, default: {}
      t.timestamps
    end

    add_index :ichatr_scout_tools, :account_id, name: 'index_ichatr_scout_tools_on_account_id'
    add_foreign_key :ichatr_scout_tools, :accounts, on_delete: :cascade
  end

  def down
    drop_table :ichatr_scout_tools, if_exists: true
  end
end
