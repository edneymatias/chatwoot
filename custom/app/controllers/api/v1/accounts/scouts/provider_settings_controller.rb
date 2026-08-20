# frozen_string_literal: true

class Api::V1::Accounts::Scouts::ProviderSettingsController < Api::V1::Accounts::BaseController
  before_action :set_scout
  before_action :authorize_admin!

  def show
    render json: {
      provider: @scout.provider,
      model_name: @scout.model_name,
      has_api_key_override: @scout.api_key_override.present?
    }
  end

  def update
    update_params = provider_params.to_h
    update_params.delete(:api_key_override) if update_params[:api_key_override].blank?

    if @scout.update(update_params)
      render json: {
        provider: @scout.provider,
        model_name: @scout.model_name,
        has_api_key_override: @scout.api_key_override.present?
      }
    else
      render json: { error: @scout.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  private

  def set_scout
    @scout = Current.account.scouts.find(params[:scout_id])
  end

  def authorize_admin!
    authorize @scout, :provider_settings?
  end

  def provider_params
    params.require(:provider_settings).permit(:provider, :model_name, :api_key_override)
  end
end
