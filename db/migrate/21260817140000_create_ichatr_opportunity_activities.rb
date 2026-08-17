# frozen_string_literal: true

class CreateIchatrOpportunityActivities < ActiveRecord::Migration[7.0]
  def up
    create_activities_table
    add_activities_indexes_and_foreign_keys
    backfill_opportunity_activities
  end

  def down
    drop_table :ichatr_opportunity_activities, if_exists: true
  end

  private

  def create_activities_table
    create_table :ichatr_opportunity_activities do |t|
      t.bigint :account_id, null: false
      t.bigint :opportunity_id, null: false
      t.string :event_type, null: false
      t.string :actor_type
      t.bigint :actor_id
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps
    end
  end

  def add_activities_indexes_and_foreign_keys
    add_index :ichatr_opportunity_activities, %i[account_id opportunity_id occurred_at],
              name: 'index_ichatr_opp_activities_on_acc_and_opp_and_occurred'
    add_index :ichatr_opportunity_activities, :account_id,
              name: 'index_ichatr_opportunity_activities_on_account_id'
    add_index :ichatr_opportunity_activities, %i[actor_type actor_id],
              name: 'index_ichatr_opportunity_activities_on_actor'

    add_foreign_key :ichatr_opportunity_activities, :accounts, on_delete: :cascade
    add_foreign_key :ichatr_opportunity_activities, :ichatr_opportunities,
                    column: :opportunity_id, on_delete: :cascade
  end

  def backfill_opportunity_activities
    backfill_created_activities
    backfill_conversation_activities
    backfill_stage_changed_activities
    backfill_terminal_activities
  end

  def backfill_created_activities
    execute <<-SQL.squish
      INSERT INTO ichatr_opportunity_activities (account_id, opportunity_id, event_type, metadata, occurred_at, created_at, updated_at)
      SELECT account_id, id, 'opportunity_created', '{}'::jsonb, created_at, NOW(), NOW()
      FROM ichatr_opportunities;
    SQL
  end

  def backfill_conversation_activities
    execute <<-SQL.squish
      INSERT INTO ichatr_opportunity_activities (account_id, opportunity_id, event_type, metadata, occurred_at, created_at, updated_at)
      SELECT oc.account_id, oc.opportunity_id, 'conversation_opened',
             jsonb_build_object(
               'conversation_id', oc.conversation_id,
               'conversation_display_id', c.display_id,
               'is_origin', oc.is_origin
             ),
             oc.created_at, NOW(), NOW()
      FROM ichatr_opportunity_conversations oc
      JOIN conversations c ON c.id = oc.conversation_id;
    SQL
  end

  def backfill_stage_changed_activities
    execute <<-SQL.squish
      INSERT INTO ichatr_opportunity_activities (account_id, opportunity_id, event_type, metadata, occurred_at, created_at, updated_at)
      SELECT account_id, opportunity_id, 'opportunity_stage_changed',
             jsonb_build_object(
               'from_stage_id', from_stage_id,
               'to_stage_id', to_stage_id
             ),
             changed_at, NOW(), NOW()
      FROM ichatr_opportunity_stage_changes;
    SQL
  end

  def backfill_terminal_activities
    execute <<-SQL.squish
      INSERT INTO ichatr_opportunity_activities (account_id, opportunity_id, event_type, metadata, occurred_at, created_at, updated_at)
      SELECT account_id, id,
             CASE WHEN status = 1 THEN 'opportunity_won' ELSE 'opportunity_lost' END,
             jsonb_build_object(
               'from_stage_id', pipeline_stage_id,
               'approximate', true
             ),
             COALESCE(closed_at, updated_at), NOW(), NOW()
      FROM ichatr_opportunities
      WHERE status IN (1, 2);
    SQL
  end
end
