class AddCampaignReportMilestoneToIchatrPipelineStages < ActiveRecord::Migration[7.1]
  def change
    add_column :ichatr_pipeline_stages, :campaign_report_milestone, :boolean, default: false, null: false
  end
end
