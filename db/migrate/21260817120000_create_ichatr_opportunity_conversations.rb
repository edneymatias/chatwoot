# frozen_string_literal: true

class CreateIchatrOpportunityConversations < ActiveRecord::Migration[7.0]
  def up
    add_active_conversation_column
    create_opportunity_conversations_table
    backfill_opportunity_conversations
  end

  def down
    drop_table :ichatr_opportunity_conversations, if_exists: true
    return unless column_exists?(:ichatr_opportunities, :active_conversation_id)

    remove_foreign_key :ichatr_opportunities, column: :active_conversation_id if foreign_key_exists?(:ichatr_opportunities,
                                                                                                     column: :active_conversation_id)
    if index_name_exists?(:ichatr_opportunities, 'index_ichatr_opportunities_on_active_conversation_id')
      remove_index :ichatr_opportunities, name: 'index_ichatr_opportunities_on_active_conversation_id'
    end
    remove_column :ichatr_opportunities, :active_conversation_id
  end

  private

  def add_active_conversation_column
    add_column :ichatr_opportunities, :active_conversation_id, :bigint
    add_index :ichatr_opportunities, :active_conversation_id,
              unique: true,
              where: 'active_conversation_id IS NOT NULL',
              name: 'index_ichatr_opportunities_on_active_conversation_id'
    add_foreign_key :ichatr_opportunities, :conversations,
                    column: :active_conversation_id,
                    on_delete: :nullify
  end

  def create_opportunity_conversations_table
    create_table :ichatr_opportunity_conversations do |t|
      t.bigint :account_id, null: false
      t.bigint :opportunity_id, null: false
      t.bigint :conversation_id, null: false
      t.boolean :is_origin, null: false, default: false
      t.timestamps
    end

    add_table_indexes_and_foreign_keys
  end

  def add_table_indexes_and_foreign_keys
    add_index :ichatr_opportunity_conversations, %i[opportunity_id conversation_id],
              unique: true, name: 'index_ichatr_opp_convs_on_opp_and_conv'
    add_index :ichatr_opportunity_conversations, %i[account_id conversation_id],
              name: 'index_ichatr_opp_convs_on_account_and_conv'
    add_index :ichatr_opportunity_conversations, :conversation_id,
              name: 'index_ichatr_opp_convs_on_conv'

    add_foreign_key :ichatr_opportunity_conversations, :accounts, on_delete: :cascade
    add_foreign_key :ichatr_opportunity_conversations, :ichatr_opportunities,
                    column: :opportunity_id, on_delete: :cascade
    add_foreign_key :ichatr_opportunity_conversations, :conversations, on_delete: :cascade
  end

  def backfill_opportunity_conversations
    execute <<-SQL.squish
      INSERT INTO ichatr_opportunity_conversations (account_id, opportunity_id, conversation_id, is_origin, created_at, updated_at)
      SELECT account_id, id, origin_conversation_id, true, created_at, updated_at
      FROM ichatr_opportunities
      WHERE origin_conversation_id IS NOT NULL
      ON CONFLICT (opportunity_id, conversation_id) DO NOTHING;
    SQL

    execute <<-SQL.squish
      UPDATE ichatr_opportunities o
      SET active_conversation_id = o.origin_conversation_id
      FROM conversations c
      WHERE o.origin_conversation_id = c.id
        AND c.status = 0;
    SQL
  end
end
