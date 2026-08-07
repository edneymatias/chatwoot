class CreateIchatrPipelineClosingRequiredFields < ActiveRecord::Migration[7.1]
  def change
    create_table :ichatr_pipeline_closing_required_fields do |t|
      t.references :account, null: false, foreign_key: true
      t.references :custom_attribute_definition, null: false, foreign_key: true
      t.integer :outcome, null: false

      t.timestamps
    end

    add_index :ichatr_pipeline_closing_required_fields,
              [:account_id, :custom_attribute_definition_id, :outcome],
              unique: true,
              name: 'idx_ichatr_pipeline_closing_req_fields_on_acc_attr_outcome'
  end
end
