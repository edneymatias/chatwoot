class AddStaleAfterDaysToMatiasPipelineStages < ActiveRecord::Migration[7.1]
  def change
    add_column :matias_pipeline_stages, :stale_after_days, :integer
  end
end
