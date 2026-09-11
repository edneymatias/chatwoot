# frozen_string_literal: true

class AddValueEstimationToIchatrScouts < ActiveRecord::Migration[7.0]
  def change
    add_reference :ichatr_scouts, :interest_attribute_definition,
                  null: true,
                  index: { name: 'index_ichatr_scouts_on_interest_attribute_definition_id' }
    add_foreign_key :ichatr_scouts, :custom_attribute_definitions,
                    column: :interest_attribute_definition_id,
                    on_delete: :nullify
    add_column :ichatr_scouts, :value_by_interest, :jsonb, null: false, default: {}
  end
end
