class CreateIchatrOpportunities < ActiveRecord::Migration[7.0]
  def change
    create_table :ichatr_opportunities do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :pipeline_stage, null: false, foreign_key: { to_table: :ichatr_pipeline_stages }
      t.references :origin_conversation, null: true, foreign_key: { to_table: :conversations }
      t.references :assignee, null: true, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.integer :status, default: 0

      t.timestamps
    end
  end
end
