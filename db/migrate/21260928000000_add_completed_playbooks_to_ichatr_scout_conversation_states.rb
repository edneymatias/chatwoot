# frozen_string_literal: true

class AddCompletedPlaybooksToIchatrScoutConversationStates < ActiveRecord::Migration[7.0]
  def change
    add_column :ichatr_scout_conversation_states, :completed_playbooks, :jsonb, default: [], null: false
  end
end
