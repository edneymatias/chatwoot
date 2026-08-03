class Api::V1::Accounts::PipelineClosingRequiredFieldsController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard

  before_action :check_authorization

  def index
    render json: Current.account.pipeline_closing_required_fields
  end

  def create
    @required_field = Current.account.pipeline_closing_required_fields.build(closing_required_field_params)
    if @required_field.save
      render json: @required_field
    else
      render json: { error: @required_field.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    @required_field = Current.account.pipeline_closing_required_fields.find(params[:id])
    if @required_field.destroy
      head :ok
    else
      render json: { error: @required_field.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  private

  def check_authorization
    authorize(PipelineClosingRequiredField)
  end

  def closing_required_field_params
    params.require(:pipeline_closing_required_field).permit(:custom_attribute_definition_id, :outcome)
  end
end
