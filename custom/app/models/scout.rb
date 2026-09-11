# frozen_string_literal: true

class Scout < ApplicationRecord
  self.table_name = 'ichatr_scouts'

  alias_attribute :system_prompt, :persona

  belongs_to :account
  belongs_to :default_pipeline_stage, class_name: 'PipelineStage', optional: true
  belongs_to :qualified_stage, class_name: 'PipelineStage', optional: true
  belongs_to :unqualified_stage, class_name: 'PipelineStage', optional: true
  belongs_to :rescue_stage, class_name: 'PipelineStage', optional: true
  belongs_to :handover_team, class_name: 'Team', optional: true
  belongs_to :interest_attribute_definition, class_name: 'CustomAttributeDefinition', optional: true

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
  validate :validate_follow_up_delays_hours
  validate :validate_interest_attribute_definition

  def quota_available?
    return true if responses_quota == -1

    responses_consumed < responses_quota
  end

  def sync_required_attribute_ids!(attribute_ids)
    target_ids = Array(attribute_ids).map(&:to_i).reject(&:zero?).uniq
    valid_ids = account.custom_attribute_definitions
                       .where(id: target_ids)
                       .where(attribute_model: %i[contact_attribute opportunity_attribute])
                       .pluck(:id)

    transaction do
      scout_required_fields.where.not(custom_attribute_definition_id: valid_ids).destroy_all
      existing_ids = scout_required_fields.pluck(:custom_attribute_definition_id)
      (valid_ids - existing_ids).each do |def_id|
        scout_required_fields.create!(
          account_id: account_id,
          custom_attribute_definition_id: def_id
        )
      end
    end
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

  def follow_up_delays_hours=(values)
    if values.is_a?(Array)
      coerced = values.map do |v|
        (Integer(v, exception: false) if v.is_a?(Numeric) || v.is_a?(String))
      end
      super(coerced.any?(&:nil?) ? values : coerced)
    else
      super(values)
    end
  end

  def engages?(contact, _conversation = nil)
    return true if audience.blank?

    Custom::Scout::AudienceMatcherService.new(audience: audience, contact: contact).matches?
  end

  private

  def validate_follow_up_delays_hours
    delays = follow_up_delays_hours
    return if valid_follow_up_delays?(delays)

    errors.add(:follow_up_delays_hours, :invalid)
  end

  def valid_follow_up_delays?(delays)
    delays.is_a?(Array) &&
      delays.length == 3 &&
      delays.all? { |d| d.is_a?(Integer) && d.positive? } &&
      delays.each_cons(2).all? { |a, b| a < b }
  end

  def validate_interest_attribute_definition
    return if interest_attribute_definition.blank?
    return if interest_attribute_definition.list? && interest_attribute_definition.opportunity_attribute?

    errors.add(:interest_attribute_definition, :invalid)
  end
end
