class Api::V1::Accounts::CampaignAttributionSettingsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    render json: response_data
  end

  def update
    if params[:enabled] && !connected?
      render json: { error: 'Campaign attribution cannot be enabled without a connected Meta account.' }, status: :unprocessable_entity
      return
    end

    setting.update!(enabled: params[:enabled]) if params.key?(:enabled)
    render json: response_data
  end

  def connect
    token_data = Meta::MarketingAuthorizationService.new.exchange_for_long_lived(params[:access_token])
    if token_data
      setting.update!(provider_config: token_data)
      render json: response_data
    else
      render json: { error: 'Meta authorization failed.' }, status: :unprocessable_entity
    end
  end

  private

  def setting
    @setting ||= current_account.campaign_attribution_setting || current_account.build_campaign_attribution_setting
  end

  def check_authorization
    authorize(setting)
  end

  def connected?
    setting.provider_config.present? && setting.provider_config['access_token'].present?
  end

  def response_data
    {
      enabled: setting.enabled,
      connected: connected?,
      meta_app_id: GlobalConfigService.load('META_MARKETING_APP_ID', ''),
      meta_api_version: GlobalConfigService.load('META_MARKETING_API_VERSION', 'v22.0')
    }
  end
end
