# frozen_string_literal: true

class AddRescueStageAndFollowUpDelaysToIchatrScouts < ActiveRecord::Migration[7.0]
  def up
    change_table :ichatr_scouts, bulk: true do |t|
      t.bigint :rescue_stage_id
      t.jsonb :follow_up_delays_hours, null: false, default: [2, 12, 24]
    end

    add_index :ichatr_scouts, :rescue_stage_id, name: 'index_ichatr_scouts_on_rescue_stage_id'
    add_foreign_key :ichatr_scouts, :ichatr_pipeline_stages, column: :rescue_stage_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :ichatr_scouts, column: :rescue_stage_id
    remove_index :ichatr_scouts, name: 'index_ichatr_scouts_on_rescue_stage_id'

    change_table :ichatr_scouts, bulk: true do |t|
      t.remove :follow_up_delays_hours
      t.remove :rescue_stage_id
    end
  end
end
