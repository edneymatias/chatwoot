class CreateMatiasOpportunityStageChanges < ActiveRecord::Migration[7.1]
  def change
    create_table :matias_opportunity_stage_changes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :opportunity, null: false, foreign_key: { to_table: :matias_opportunities }
      t.references :from_stage, null: true, foreign_key: { to_table: :matias_pipeline_stages }
      t.references :to_stage, null: false, foreign_key: { to_table: :matias_pipeline_stages }
      t.datetime :changed_at, null: false

      t.timestamps
    end

    add_index :matias_opportunity_stage_changes, [:opportunity_id, :changed_at]
    add_index :matias_opportunity_stage_changes, [:to_stage_id, :changed_at]
  end
end
