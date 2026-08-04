class CreateMatiasPipelineCardFieldConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :matias_pipeline_card_field_configs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :custom_attribute_definition, null: true, foreign_key: true
      t.integer :field_type, null: false
      t.string :color, null: false
      t.integer :position, null: false

      t.timestamps
    end
  end
end
