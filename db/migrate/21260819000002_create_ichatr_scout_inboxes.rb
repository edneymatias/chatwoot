# frozen_string_literal: true

class CreateIchatrScoutInboxes < ActiveRecord::Migration[7.0]
  def up
    create_table :ichatr_scout_inboxes do |t|
      t.bigint :scout_id, null: false
      t.bigint :inbox_id, null: false
      t.timestamps
    end

    add_index :ichatr_scout_inboxes, :scout_id, name: 'index_ichatr_scout_inboxes_on_scout_id'
    add_index :ichatr_scout_inboxes, :inbox_id, unique: true, name: 'index_ichatr_scout_inboxes_on_inbox_id'

    add_foreign_key :ichatr_scout_inboxes, :ichatr_scouts, column: :scout_id, on_delete: :cascade
    add_foreign_key :ichatr_scout_inboxes, :inboxes, column: :inbox_id, on_delete: :cascade
  end

  def down
    drop_table :ichatr_scout_inboxes, if_exists: true
  end
end
