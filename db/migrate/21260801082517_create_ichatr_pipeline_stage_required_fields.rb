class CreateIchatrPipelineStageRequiredFields < ActiveRecord::Migration[7.1]
  def change
    create_table :ichatr_pipeline_stage_required_fields do |t|
      t.references :account, null: false, foreign_key: true
      t.references :pipeline_stage, null: false, foreign_key: { to_table: :ichatr_pipeline_stages }
      t.references :custom_attribute_definition, null: false, foreign_key: true

      t.timestamps
    end

    add_index :ichatr_pipeline_stage_required_fields,
              [:account_id, :custom_attribute_definition_id],
              unique: true,
              name: 'idx_ichatr_pipeline_stage_req_fields_on_acc_and_attr_def'
  end
end
