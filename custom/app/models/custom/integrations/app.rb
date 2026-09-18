# frozen_string_literal: true

module Custom::Integrations::App
  def active?(account)
    if params[:category] == 'erp'
      return false if params[:feature_flag].blank?

      account.feature_enabled?(params[:feature_flag])
    else
      super
    end
  end
end
