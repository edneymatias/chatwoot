class AddTotalDisplayModeAndAccentColorToMatiasPipelineStages < ActiveRecord::Migration[7.1]
  def change
    add_column :matias_pipeline_stages, :total_display_mode, :integer, null: false, default: 0
    add_column :matias_pipeline_stages, :accent_color, :string
  end
end
