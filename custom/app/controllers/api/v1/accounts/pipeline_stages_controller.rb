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
    stage_params = pipeline_stage_params.to_h
    req_attr_ids = stage_params.delete('required_custom_attribute_definition_ids')
    @pipeline_stage = Current.account.pipeline_stages.build(stage_params)
    if @pipeline_stage.save
      sync_required_attributes(@pipeline_stage, req_attr_ids) if req_attr_ids
      render json: @pipeline_stage.reload,
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
      result = perform_update(@pipeline_stage, pipeline_stage_params.to_h, is_reorder)

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
    req_attr_ids = stage_params.delete('required_custom_attribute_definition_ids')

    if is_reorder
      other_params = stage_params.except('position')
      stage.update!(other_params) if other_params.present?
      result = stage.reorder_to!(stage_params['position'])
    else
      stage.update!(stage_params)
      result = stage
    end

    sync_required_attributes(stage, req_attr_ids) if req_attr_ids
    result.is_a?(PipelineStage) ? result.reload : result
  end

  def sync_required_attributes(stage, attr_ids)
    attr_ids = Array(attr_ids).map(&:to_i).compact_blank
    stage.pipeline_stage_required_fields.where.not(custom_attribute_definition_id: attr_ids).destroy_all
    existing_ids = stage.pipeline_stage_required_fields.pluck(:custom_attribute_definition_id)
    (attr_ids - existing_ids).each do |cad_id|
      stage.pipeline_stage_required_fields.create!(account: Current.account, custom_attribute_definition_id: cad_id)
    end
  end

  def pipeline_stage_params
    params.require(:pipeline_stage).permit(
      :name, :description, :position, :requires_deal_value, :total_display_mode, :accent_color,
      :stale_after_days, :campaign_report_milestone, required_custom_attribute_definition_ids: []
    )
  end
end
