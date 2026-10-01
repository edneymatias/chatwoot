# frozen_string_literal: true

class AddCapabilityStateToIchatrScoutConversationStates < ActiveRecord::Migration[7.0]
  def change
    add_column :ichatr_scout_conversation_states, :capability_state, :jsonb, default: {}, null: false
  end
end
