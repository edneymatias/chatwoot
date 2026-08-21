# frozen_string_literal: true

class ScoutAccountConfig < ApplicationRecord
  self.table_name = 'ichatr_scout_account_configs'

  def self.instance_method_already_implemented?(method_name)
    return false if method_name.to_s == 'model_name'

    super
  end

  def model_name
    loc = caller_locations(1, 1).first
    return self.class.model_name if loc&.path&.include?('active_model/error') || loc&.label == 'generate_message'

    self[:model_name]
  end

  belongs_to :account

  enum provider: { gemini: 0, openai: 1, anthropic: 2 }

  encrypts :api_key

  validates :account_id, presence: true, uniqueness: true
  validates :provider, :model_name, :api_key, presence: true

  def validate_credentials!
    return if api_key.blank? || self[:model_name].blank? || provider.blank?

    probe_provider_credentials!
    true
  rescue StandardError => e
    handle_verification_error(e)
    false
  end

  private

  def probe_provider_credentials!
    context = build_llm_context
    chat = context.chat(model: self[:model_name])
    chat.ask('ping')
  end

  def build_llm_context
    RubyLLM.context do |config|
      case provider.to_sym
      when :gemini then config.gemini_api_key = api_key
      when :openai then config.openai_api_key = api_key
      when :anthropic then config.anthropic_api_key = api_key
      end
    end
  end

  def handle_verification_error(error)
    case error
    when RubyLLM::UnauthorizedError, RubyLLM::ForbiddenError
      errors.add(:api_key, :invalid, message: "chave de API inválida ou sem permissão: #{error.message}")
    when RubyLLM::ModelNotFoundError, RubyLLM::NotFoundError
      errors.add(:model_name, :invalid, message: "modelo não encontrado ou indisponível para esta chave: #{error.message}")
    when RubyLLM::PaymentRequiredError, RubyLLM::RateLimitError
      errors.add(:api_key, :invalid, message: "limite de cota ou faturamento excedido no provedor: #{error.message}")
    else
      errors.add(:base, "Falha na verificação com o provedor: #{error.message}")
    end
  end
end
