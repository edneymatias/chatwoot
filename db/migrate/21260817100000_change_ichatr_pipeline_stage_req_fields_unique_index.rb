class ChangeIchatrPipelineStageReqFieldsUniqueIndex < ActiveRecord::Migration[7.1]
  def change
    remove_index :ichatr_pipeline_stage_required_fields,
                 column: [:account_id, :custom_attribute_definition_id],
                 unique: true,
                 name: 'idx_ichatr_pipeline_stage_req_fields_on_acc_and_attr_def'

    add_index :ichatr_pipeline_stage_required_fields,
              [:account_id, :pipeline_stage_id, :custom_attribute_definition_id],
              unique: true,
              name: 'idx_ichatr_pipeline_stage_req_fields_on_acc_stage_attr'
  end
end
