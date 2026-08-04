class Api::V1::Accounts::PipelineStagesController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard

  before_action :check_authorization

  def index
    PipelineStage.seed_defaults_for!(Current.account)
    @pipeline_stages = Current.account.pipeline_stages.includes(:required_custom_attribute_definitions)
    render json: @pipeline_stages,
           include: { required_custom_attribute_definitions: { only: [:id, :attribute_key, :attribute_display_name, :attribute_display_type,
                                                                      :attribute_values] } }
  end

  def create
    @pipeline_stage = Current.account.pipeline_stages.build(pipeline_stage_params)
    if @pipeline_stage.save
      render json: @pipeline_stage,
             include: { required_custom_attribute_definitions: { only: [:id, :attribute_key, :attribute_display_name, :attribute_display_type,
                                                                        :attribute_values] } }
    else
      render json: { error: @pipeline_stage.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    @pipeline_stage = Current.account.pipeline_stages.find(params[:id])
    is_reorder = pipeline_stage_params[:position].present? && pipeline_stage_params[:position].to_i != @pipeline_stage.position

    begin
      result = perform_update(@pipeline_stage, pipeline_stage_params, is_reorder)

      if result
        render json: result,
               include: { required_custom_attribute_definitions: { only: [:id, :attribute_key, :attribute_display_name, :attribute_display_type,
                                                                          :attribute_values] } }
      else
        render json: { error: @pipeline_stage.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
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

  def perform_update(stage, stage_params, is_reorder)
    if is_reorder
      other_params = stage_params.except(:position)
      stage.update!(other_params) if other_params.present?
      stage.reorder_to!(stage_params[:position])
    else
      stage.update(stage_params) ? stage : nil
    end
  end

  def pipeline_stage_params
    params.require(:pipeline_stage).permit(:name, :description, :position, :requires_deal_value, :total_display_mode, :accent_color,
                                           :stale_after_days)
  end
end
