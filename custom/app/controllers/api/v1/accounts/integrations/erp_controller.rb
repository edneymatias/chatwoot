# frozen_string_literal: true

class Api::V1::Accounts::Integrations::ErpController < Api::V1::Accounts::Integrations::BaseController
  before_action :fetch_hook
  before_action :fetch_contact

  def data
    adapter = Erp::AdapterFactory.build(@hook)
    result = adapter.fetch_data(@contact)
    render json: result
  rescue Erp::Error => e
    ChatwootExceptionTracker.new(e).capture_exception
    render json: { error: e.message }, status: :service_unavailable
  end

  private

  def fetch_hook
    @hook = Current.account.hooks.enabled.find do |h|
      h.app_id == 'younus' || h.app&.params&.dig(:category) == 'erp'
    end
    render json: { error: I18n.t('errors.erp.not_enabled') }, status: :not_found unless @hook
  end

  def fetch_contact
    @contact = Current.account.contacts.find_by(id: params[:contact_id])
    render json: { error: I18n.t('errors.erp.contact_not_found') }, status: :not_found unless @contact
  end
end
