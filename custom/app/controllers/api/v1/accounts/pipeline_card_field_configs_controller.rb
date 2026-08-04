class Api::V1::Accounts::PipelineCardFieldConfigsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_config, only: [:update, :destroy]

  def index
    render json: Current.account.pipeline_card_field_configs.order(:position)
  end

  def create
    @config = Current.account.pipeline_card_field_configs.build(config_params)
    if @config.save
      render json: @config
    else
      render json: { error: @config.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    if @config.update(config_params)
      render json: @config
    else
      render json: { error: @config.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    @config.destroy!
    head :ok
  end

  private

  def check_authorization
    authorize(PipelineCardFieldConfig)
  end

  def fetch_config
    @config = Current.account.pipeline_card_field_configs.find(params[:id])
  end

  def config_params
    params.require(:pipeline_card_field_config).permit(:field_type, :custom_attribute_definition_id, :color)
  end
end
