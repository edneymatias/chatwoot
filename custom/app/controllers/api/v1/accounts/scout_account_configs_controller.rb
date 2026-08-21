# frozen_string_literal: true

class Api::V1::Accounts::ScoutAccountConfigsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    config = ScoutAccountConfig.find_by(account_id: Current.account.id)
    if config.present?
      render json: format_config_response(config)
    else
      render json: {
        provider: nil,
        model_name: nil,
        has_api_key: false,
        configured: false
      }
    end
  end

  def update
    config = ScoutAccountConfig.find_or_initialize_by(account_id: Current.account.id)
    update_params = config_params.to_h
    update_params.delete(:api_key) if update_params[:api_key].blank? && config.persisted?

    config.assign_attributes(update_params)

    if config.valid? && config.validate_credentials! && config.save
      render json: format_config_response(config)
    else
      render json: { error: config.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  private

  def check_authorization
    authorize(ScoutAccountConfig)
  end

  def config_params
    params.require(:scout_account_config).permit(:provider, :model_name, :api_key)
  end

  def format_config_response(config)
    {
      provider: config.provider,
      model_name: config.model_name,
      has_api_key: config.api_key.present?,
      configured: true
    }
  end
end
