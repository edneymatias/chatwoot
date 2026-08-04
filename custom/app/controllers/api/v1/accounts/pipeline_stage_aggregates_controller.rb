class Api::V1::Accounts::PipelineStageAggregatesController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard

  before_action :check_authorization

  def index
    stage_ids = params[:stage_ids]
    if stage_ids.blank?
      render json: { error: 'stage_ids is required' }, status: :unprocessable_entity
      return
    end

    open_counts = Current.account.opportunities.where(pipeline_stage_id: stage_ids, status: :open).group(:pipeline_stage_id).count
    open_values = Current.account.opportunities.where(pipeline_stage_id: stage_ids, status: :open).group(:pipeline_stage_id).sum(:value)

    aggregates = open_counts.map do |stage_id, count|
      {
        pipeline_stage_id: stage_id,
        open_count: count,
        open_value_sum: open_values[stage_id] || 0.0
      }
    end

    render json: aggregates
  end

  private

  def check_authorization
    super(PipelineStage)
  end
end
