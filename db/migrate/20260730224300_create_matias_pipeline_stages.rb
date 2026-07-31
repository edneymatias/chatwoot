class CreateMatiasPipelineStages < ActiveRecord::Migration[7.0]
  def change
    create_table :matias_pipeline_stages do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false

      t.timestamps
    end
  end
end
