# frozen_string_literal: true

class AddPipelineFieldsToIchatrScouts < ActiveRecord::Migration[7.0]
  def up
    change_table :ichatr_scouts, bulk: true do |t|
      t.integer :debounce_delay_seconds, null: false, default: 5
      t.boolean :feature_memory, null: false, default: true
      t.bigint :qualified_stage_id
      t.bigint :unqualified_stage_id
      t.bigint :handover_team_id
      t.jsonb :product_catalog, null: false, default: {}
      t.jsonb :knowledge_sources, null: false, default: {}
    end

    add_index :ichatr_scouts, :qualified_stage_id, name: 'index_ichatr_scouts_on_qualified_stage_id'
    add_index :ichatr_scouts, :unqualified_stage_id, name: 'index_ichatr_scouts_on_unqualified_stage_id'
    add_index :ichatr_scouts, :handover_team_id, name: 'index_ichatr_scouts_on_handover_team_id'

    add_foreign_key :ichatr_scouts, :ichatr_pipeline_stages, column: :qualified_stage_id, on_delete: :nullify
    add_foreign_key :ichatr_scouts, :ichatr_pipeline_stages, column: :unqualified_stage_id, on_delete: :nullify
    add_foreign_key :ichatr_scouts, :teams, column: :handover_team_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :ichatr_scouts, column: :handover_team_id
    remove_foreign_key :ichatr_scouts, column: :unqualified_stage_id
    remove_foreign_key :ichatr_scouts, column: :qualified_stage_id

    remove_index :ichatr_scouts, name: 'index_ichatr_scouts_on_handover_team_id'
    remove_index :ichatr_scouts, name: 'index_ichatr_scouts_on_unqualified_stage_id'
    remove_index :ichatr_scouts, name: 'index_ichatr_scouts_on_qualified_stage_id'

    change_table :ichatr_scouts, bulk: true do |t|
      t.remove :knowledge_sources
      t.remove :product_catalog
      t.remove :handover_team_id
      t.remove :unqualified_stage_id
      t.remove :qualified_stage_id
      t.remove :feature_memory
      t.remove :debounce_delay_seconds
    end
  end
end
