# frozen_string_literal: true

class CreateIchatrScoutKnowledgeSources < ActiveRecord::Migration[7.0]
  def up
    create_table :ichatr_scout_knowledge_sources do |t|
      t.bigint :account_id, null: false
      t.bigint :scout_id, null: false
      t.integer :kind, null: false
      t.string :url
      t.text :question
      t.text :answer
      t.integer :status, null: false, default: 0
      t.text :error_message
      t.text :content
      t.timestamps
    end

    add_index :ichatr_scout_knowledge_sources, :account_id, name: 'index_ichatr_scout_knowledge_sources_on_account_id'
    add_index :ichatr_scout_knowledge_sources, :scout_id, name: 'index_ichatr_scout_knowledge_sources_on_scout_id'
    add_index :ichatr_scout_knowledge_sources, %i[scout_id status], name: 'index_ichatr_scout_ks_on_scout_and_status'

    add_foreign_key :ichatr_scout_knowledge_sources, :accounts, on_delete: :cascade
    add_foreign_key :ichatr_scout_knowledge_sources, :ichatr_scouts, column: :scout_id, on_delete: :cascade
  end

  def down
    drop_table :ichatr_scout_knowledge_sources, if_exists: true
  end
end
