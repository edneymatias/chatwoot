class OpportunityStageChange < ApplicationRecord
  self.table_name = 'ichatr_opportunity_stage_changes'

  belongs_to :account
  belongs_to :opportunity
  belongs_to :from_stage, class_name: 'PipelineStage', optional: true
  belongs_to :to_stage, class_name: 'PipelineStage'
end
