# frozen_string_literal: true

module Custom::Integrations::Hook
  extend ActiveSupport::Concern

  prepended do
    before_validation :sanitize_erp_settings
    validate :validate_erp_credentials, if: :validate_erp_credentials?
  end

  def erp_integration?
    app_id == 'younus'
  end

  def masked_settings
    return settings unless erp_integration? && settings.is_a?(Hash)

    settings.merge('token' => '••••••••')
  end

  private

  def sanitize_erp_settings
    return unless erp_integration? && settings.is_a?(Hash)

    self.settings = settings.transform_values do |val|
      val.is_a?(String) ? val.strip : val
    end
  end

  def validate_erp_credentials?
    erp_integration? && enabled? && feature_allowed? && (new_record? || will_save_change_to_settings? || will_save_change_to_status?)
  end

  def validate_erp_credentials
    adapter = Erp::AdapterFactory.build(self)
    adapter.test_connection
  rescue Erp::AuthenticationError
    errors.add(:base, I18n.t('errors.erp.invalid_credentials'))
  rescue Erp::ApiError, StandardError
    errors.add(:base, I18n.t('errors.erp.connection_error'))
  end
end
