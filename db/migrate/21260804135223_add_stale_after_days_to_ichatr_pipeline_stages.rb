class AddStaleAfterDaysToIchatrPipelineStages < ActiveRecord::Migration[7.1]
  def change
    add_column :ichatr_pipeline_stages, :stale_after_days, :integer
  end
end
