# frozen_string_literal: true

class Custom::Scout::EmbeddingConfig
  attr_reader :account, :config

  def self.for(account)
    new(account)
  end

  def initialize(account)
    @account = account
    @config = ScoutAccountConfig.find_by(account_id: account&.id)
  end

  def supported?
    @config.present? && @config.api_key.present? && %w[gemini openai].include?(@config.provider.to_s)
  end

  def embed(text)
    return [] if text.blank? || !supported?

    context = build_llm_context
    case @config.provider.to_sym
    when :gemini
      response = context.embed(text, model: 'text-embedding-004')
      response.vectors
    when :openai
      response = context.embed(text, model: 'text-embedding-3-small', dimensions: 768)
      response.vectors
    else
      []
    end
  rescue StandardError => e
    Rails.logger.error "[Custom::Scout::EmbeddingConfig] Embedding error: #{e.message}"
    []
  end

  private

  def build_llm_context
    RubyLLM.context do |c|
      case @config.provider.to_sym
      when :gemini
        c.gemini_api_key = @config.api_key
      when :openai
        c.openai_api_key = @config.api_key
      end
    end
  end
end
