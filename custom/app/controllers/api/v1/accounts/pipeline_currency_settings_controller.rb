class Api::V1::Accounts::PipelineCurrencySettingsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    setting = Current.account.pipeline_currency_setting || PipelineCurrencySetting.new(account: Current.account)
    render json: { currency: setting.currency }
  end

  def update
    setting = Current.account.pipeline_currency_setting || Current.account.build_pipeline_currency_setting
    if setting.update(setting_params)
      render json: { currency: setting.currency }
    else
      render json: { error: setting.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  private

  def check_authorization
    authorize(PipelineCurrencySetting)
  end

  def setting_params
    params.permit(:currency)
  end
end
