# frozen_string_literal: true

class CreateIchatrCampaignRecipients < ActiveRecord::Migration[7.0]
  def change
    create_recipients_table
    add_recipients_indexes
    add_recipients_foreign_keys
  end

  private

  def create_recipients_table
    create_table :ichatr_campaign_recipients do |t|
      add_core_columns(t)
      add_tracking_columns(t)
      t.timestamps
    end
  end

  def add_core_columns(table)
    table.bigint :account_id, null: false
    table.bigint :campaign_id, null: false
    table.bigint :contact_id, null: false
    table.bigint :inbox_id, null: false
    table.string :source_id
    table.integer :status, default: 0, null: false
    table.string :error_code
    table.string :error_title
    table.text :error_message
    table.text :message_content
  end

  def add_tracking_columns(table)
    table.datetime :sent_at
    table.datetime :delivered_at
    table.datetime :read_at
    table.datetime :replied_at
    table.datetime :failed_at
    table.string :reply_source_id
    table.integer :reply_type
    table.string :reply_label
    table.bigint :campaign_message_id
  end

  def add_recipients_indexes
    add_index :ichatr_campaign_recipients, %i[account_id campaign_id],
              name: 'index_ichatr_campaign_recipients_on_account_and_campaign'
    add_index :ichatr_campaign_recipients, %i[campaign_id status],
              name: 'index_ichatr_campaign_recipients_on_campaign_and_status'
    add_index :ichatr_campaign_recipients, %i[campaign_id contact_id],
              unique: true, name: 'index_ichatr_campaign_recipients_on_campaign_and_contact'
    add_index :ichatr_campaign_recipients, :source_id,
              unique: true, where: 'source_id IS NOT NULL',
              name: 'index_ichatr_campaign_recipients_on_source_id'
    add_index :ichatr_campaign_recipients, :reply_source_id,
              unique: true, where: 'reply_source_id IS NOT NULL',
              name: 'index_ichatr_campaign_recipients_on_reply_source_id'
  end

  def add_recipients_foreign_keys
    add_foreign_key :ichatr_campaign_recipients, :accounts, on_delete: :cascade
    add_foreign_key :ichatr_campaign_recipients, :campaigns, on_delete: :cascade
    add_foreign_key :ichatr_campaign_recipients, :contacts, on_delete: :cascade
    add_foreign_key :ichatr_campaign_recipients, :inboxes, on_delete: :cascade
  end
end
