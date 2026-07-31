class Api::V1::Accounts::PipelineStagesController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard

  before_action :check_authorization

  def index
    PipelineStage.seed_defaults_for!(Current.account)
    @pipeline_stages = Current.account.pipeline_stages
    render json: @pipeline_stages
  end

  def create
    @pipeline_stage = Current.account.pipeline_stages.build(pipeline_stage_params)
    if @pipeline_stage.save
      render json: @pipeline_stage
    else
      render json: { error: @pipeline_stage.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    @pipeline_stage = Current.account.pipeline_stages.find(params[:id])
    if @pipeline_stage.update(pipeline_stage_params)
      render json: @pipeline_stage
    else
      render json: { error: @pipeline_stage.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    @pipeline_stage = Current.account.pipeline_stages.find(params[:id])
    if @pipeline_stage.destroy
      head :ok
    else
      render json: { error: @pipeline_stage.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  private

  def check_authorization
    super(PipelineStage)
  end

  def pipeline_stage_params
    params.require(:pipeline_stage).permit(:name, :description, :position)
  end
end
