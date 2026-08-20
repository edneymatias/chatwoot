# frozen_string_literal: true

class Scout < ApplicationRecord
  self.table_name = 'ichatr_scouts'

  def self.instance_method_already_implemented?(method_name)
    return false if method_name.to_s == 'model_name'

    super
  end

  def model_name
    loc = caller_locations(1, 1).first
    return self.class.model_name if loc&.path&.include?('active_model/error') || loc&.label == 'generate_message'

    super
  end

  encrypts :api_key_override

  enum provider: { gemini: 0, openai: 1, anthropic: 2 }

  alias_attribute :system_prompt, :persona

  belongs_to :account
  belongs_to :default_pipeline_stage, class_name: 'PipelineStage', optional: true
  belongs_to :qualified_stage, class_name: 'PipelineStage', optional: true
  belongs_to :unqualified_stage, class_name: 'PipelineStage', optional: true
  belongs_to :handover_team, class_name: 'Team', optional: true

  has_many :scout_inboxes, class_name: 'ScoutInbox', dependent: :destroy
  has_many :inboxes, through: :scout_inboxes
  has_many :scout_knowledge_sources, class_name: 'ScoutKnowledgeSource', dependent: :destroy
  has_many :scout_required_fields, class_name: 'ScoutRequiredField', dependent: :destroy
  has_many :required_custom_attribute_definitions, through: :scout_required_fields, source: :custom_attribute_definition

  validates :account_id, :name, :provider, :model_name, presence: true
  validates :debounce_delay_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :responses_quota, numericality: { only_integer: true, greater_than_or_equal_to: -1 }
  validates :responses_consumed, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def quota_available?
    return true if responses_quota == -1

    responses_consumed < responses_quota
  end

  def llm_chat
    key = api_key_override.presence || ENV.fetch("#{provider.upcase}_API_KEY", nil)
    context = RubyLLM.context do |config|
      case provider.to_sym
      when :gemini
        config.gemini_api_key = key
      when :openai
        config.openai_api_key = key
      when :anthropic
        config.anthropic_api_key = key
      end
    end

    context.chat(model: model_name)
  end
end
