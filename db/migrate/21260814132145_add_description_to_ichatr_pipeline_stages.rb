class AddDescriptionToIchatrPipelineStages < ActiveRecord::Migration[7.1]
  def change
    add_column :ichatr_pipeline_stages, :description, :text
  end
end
