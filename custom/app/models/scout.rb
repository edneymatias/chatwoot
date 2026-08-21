# frozen_string_literal: true

class Scout < ApplicationRecord
  self.table_name = 'ichatr_scouts'

  alias_attribute :system_prompt, :persona

  belongs_to :account
  belongs_to :default_pipeline_stage, class_name: 'PipelineStage', optional: true
  belongs_to :qualified_stage, class_name: 'PipelineStage', optional: true
  belongs_to :unqualified_stage, class_name: 'PipelineStage', optional: true
  belongs_to :handover_team, class_name: 'Team', optional: true

  has_many :scout_inboxes, class_name: 'ScoutInbox', dependent: :destroy
  has_many :inboxes, through: :scout_inboxes
  has_many :scout_knowledge_sources, class_name: 'ScoutKnowledgeSource', dependent: :destroy
  has_many :scout_knowledge_embeddings, class_name: 'ScoutKnowledgeEmbedding', dependent: :destroy
  has_many :scout_required_fields, class_name: 'ScoutRequiredField', dependent: :destroy
  has_many :required_custom_attribute_definitions, through: :scout_required_fields, source: :custom_attribute_definition

  validates :account_id, :name, presence: true
  validates :debounce_delay_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :responses_quota, numericality: { only_integer: true, greater_than_or_equal_to: -1 }
  validates :responses_consumed, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def quota_available?
    return true if responses_quota == -1

    responses_consumed < responses_quota
  end

  def llm_chat(temperature: 0.6)
    config = ScoutAccountConfig.find_by(account_id: account_id)
    raise "Configuração de LLM não encontrada para a conta #{account_id}" if config.blank?

    context = RubyLLM.context do |c|
      case config.provider.to_sym
      when :gemini
        c.gemini_api_key = config.api_key
      when :openai
        c.openai_api_key = config.api_key
      end
    end

    chat = context.chat(model: config.model_name)
    chat = chat.with_params(temperature: temperature) if temperature && chat.respond_to?(:with_params)
    chat
  end
end
