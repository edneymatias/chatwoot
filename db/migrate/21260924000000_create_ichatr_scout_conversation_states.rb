# frozen_string_literal: true

class CreateIchatrScoutConversationStates < ActiveRecord::Migration[7.0]
  def change
    create_conversation_states_table
    add_conversation_states_indexes
    add_conversation_states_foreign_keys
  end

  private

  def create_conversation_states_table
    create_table :ichatr_scout_conversation_states do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.string :active_playbook
      t.datetime :activated_at
      t.integer :activation_reason
      t.integer :transition_count, default: 0, null: false
      t.datetime :handoff_limit_reached_at
      t.string :last_exit
      t.jsonb :unsatisfied_flags, default: {}, null: false
      t.timestamps
    end
  end

  def add_conversation_states_indexes
    add_index :ichatr_scout_conversation_states, :account_id,
              name: 'index_ichatr_scout_conversation_states_on_account_id'
    add_index :ichatr_scout_conversation_states, :conversation_id,
              unique: true,
              name: 'index_ichatr_scout_conversation_states_on_conversation_id'
  end

  def add_conversation_states_foreign_keys
    add_foreign_key :ichatr_scout_conversation_states, :accounts, on_delete: :cascade
    add_foreign_key :ichatr_scout_conversation_states, :conversations, on_delete: :cascade
  end
end
