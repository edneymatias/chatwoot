# frozen_string_literal: true

class Custom::ScoutV2::Capabilities::Registry
  Resolution = Data.define(:capability, :provider) do
    def satisfied?
      !provider.nil?
    end
  end

  PROVIDERS = { 'younus' => Erp::Younus::Adapter }.freeze

  class << self
    def resolve(name, account:, hook: nil)
      name_str = name.to_s
      return Resolution.new(capability: name_str, provider: nil) if account.blank? && hook.blank?

      hook ||= find_erp_hook(account)
      return Resolution.new(capability: name_str, provider: nil) unless hook

      adapter_class = PROVIDERS[hook.app_id]
      return Resolution.new(capability: name_str, provider: nil) unless adapter_class

      required_settings = adapter_class.capability_settings[name_str]
      return Resolution.new(capability: name_str, provider: nil) unless required_settings

      return Resolution.new(capability: name_str, provider: nil) unless settings_satisfied?(hook.settings, required_settings)

      Resolution.new(capability: name_str, provider: adapter_class.new(hook))
    end

    def satisfied_names(account:)
      return [] if account.blank?

      hook = find_erp_hook(account)
      return [] unless hook

      Custom::ScoutV2::Capabilities::Catalog::KNOWN_NAMES.select do |name|
        resolve(name, account: account, hook: hook).satisfied?
      end
    end

    def find_erp_hook(account)
      return nil if account.blank?

      account.hooks.where(status: :enabled).find do |h|
        h.app&.params&.dig(:category) == 'erp' &&
          h.feature_allowed? &&
          PROVIDERS.key?(h.app_id)
      end
    end

    private

    def settings_satisfied?(settings, required_settings)
      return false if settings.blank?

      required_settings.all? do |key|
        val = settings[key]
        next false if val.nil? || (val.is_a?(String) && val.strip.empty?)

        if key.start_with?('id_')
          val.to_s.strip.match?(/\A\d+\z/)
        else
          true
        end
      end
    end
  end
end
