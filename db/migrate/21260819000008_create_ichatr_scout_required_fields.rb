# frozen_string_literal: true

class CreateIchatrScoutRequiredFields < ActiveRecord::Migration[7.0]
  def up
    create_table :ichatr_scout_required_fields do |t|
      t.bigint :account_id, null: false
      t.bigint :scout_id, null: false
      t.bigint :custom_attribute_definition_id, null: false
      t.timestamps
    end

    add_index :ichatr_scout_required_fields, :account_id, name: 'index_ichatr_scout_required_fields_on_account_id'
    add_index :ichatr_scout_required_fields, :scout_id, name: 'index_ichatr_scout_required_fields_on_scout_id'
    add_index :ichatr_scout_required_fields, :custom_attribute_definition_id, name: 'index_ichatr_scout_required_fields_on_cad_id'
    add_index :ichatr_scout_required_fields, %i[scout_id custom_attribute_definition_id],
              unique: true,
              name: 'index_ichatr_scout_req_fields_on_scout_and_cad'

    add_foreign_key :ichatr_scout_required_fields, :accounts, on_delete: :cascade
    add_foreign_key :ichatr_scout_required_fields, :ichatr_scouts, column: :scout_id, on_delete: :cascade
    add_foreign_key :ichatr_scout_required_fields, :custom_attribute_definitions, column: :custom_attribute_definition_id, on_delete: :cascade
  end

  def down
    drop_table :ichatr_scout_required_fields, if_exists: true
  end
end
