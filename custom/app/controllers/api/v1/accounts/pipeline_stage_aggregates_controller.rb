class Api::V1::Accounts::PipelineStageAggregatesController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard

  before_action :check_authorization

  def index
    stage_ids = params[:stage_ids]
    if stage_ids.blank?
      render json: { error: 'stage_ids is required' }, status: :unprocessable_entity
      return
    end

    stage_id_list = Array(stage_ids).map(&:to_i)
    aggregates = build_stage_aggregates(stage_id_list)

    render json: aggregates
  end

  private

  def build_stage_aggregates(stage_ids)
    filtered_relation = OpportunitiesFilter.new(
      Current.account.opportunities.where(pipeline_stage_id: stage_ids),
      params
    ).perform.reorder(nil)

    counts = filtered_relation.group(:pipeline_stage_id).count
    values = filtered_relation.group(:pipeline_stage_id).sum(:value)

    stage_ids.map do |stage_id|
      {
        pipeline_stage_id: stage_id,
        count: counts[stage_id] || 0,
        value_sum: (values[stage_id] || 0.0).to_f
      }
    end
  end

  def check_authorization
    super(PipelineStage)
  end
end
