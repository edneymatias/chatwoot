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

    if params.key?(:enabled)
      setting.update!(enabled: params[:enabled])
      Meta::DrainPendingAttributionsJob.perform_later(current_account.id) if params[:enabled]
    end
    render json: response_data
  end

  def connect
    token_data = Meta::MarketingAuthorizationService.new.exchange_for_long_lived(params[:access_token])
    if token_data
      setting.update!(provider_config: token_data)
      Meta::DrainPendingAttributionsJob.perform_later(current_account.id) if setting.enabled?
      render json: response_data
    else
      render json: { error: 'Meta authorization failed.' }, status: :unprocessable_entity
    end
  end

  def reprocess_pending
    unless connected? && setting.enabled?
      error_msg = I18n.t('campaign_attribution.not_connected_error',
                         default: 'Campaign attribution cannot be reprocessed without an active Meta connection.')
      render json: { error: error_msg }, status: :unprocessable_entity
      return
    end

    count = current_account.opportunities.where(campaign_resolution_status: 'pending').where.not(campaign_source_id: [nil, '']).count
    if count.positive?
      Meta::DrainPendingAttributionsJob.perform_later(current_account.id)
      msg = I18n.t('campaign_attribution.reprocess_enqueued', count: count,
                                                              default: "#{count} pending opportunities queued for resolution.")
      render json: { message: msg, count: count }
    else
      msg = I18n.t('campaign_attribution.no_pending', default: 'No pending opportunities to resolve.')
      render json: { message: msg, count: 0 }
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
      pending_count: current_account.opportunities.where(campaign_resolution_status: 'pending').where.not(campaign_source_id: [nil, '']).count,
      resolved_data_present: current_account.opportunities.exists?(campaign_resolution_status: 'resolved'),
      meta_app_id: GlobalConfigService.load('META_MARKETING_APP_ID', ''),
      meta_api_version: GlobalConfigService.load('META_MARKETING_API_VERSION', 'v22.0')
    }
  end
end
