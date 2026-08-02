class Api::V1::Accounts::PipelineStageRequiredFieldsController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard

  before_action :fetch_pipeline_stage
  before_action :check_authorization

  def create
    PipelineStageRequiredField.where(
      account_id: Current.account.id,
      custom_attribute_definition_id: required_field_params[:custom_attribute_definition_id]
    ).destroy_all

    @required_field = @pipeline_stage.pipeline_stage_required_fields.build(required_field_params)
    @required_field.account = Current.account
    if @required_field.save
      render json: @required_field
    else
      render json: { error: @required_field.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    @required_field = @pipeline_stage.pipeline_stage_required_fields.find_by!(custom_attribute_definition_id: params[:id])
    if @required_field.destroy
      head :ok
    else
      render json: { error: @required_field.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  private

  def fetch_pipeline_stage
    @pipeline_stage = Current.account.pipeline_stages.find(params[:pipeline_stage_id])
  end

  def check_authorization
    authorize(PipelineStageRequiredField)
  end

  def required_field_params
    params.require(:pipeline_stage_required_field).permit(:custom_attribute_definition_id)
  end
end
