class AddRequiresDealValueToMatiasPipelineStages < ActiveRecord::Migration[7.1]
  def change
    add_column :matias_pipeline_stages, :requires_deal_value, :boolean, default: false
  end
end
