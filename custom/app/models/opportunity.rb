class Opportunity < ApplicationRecord
  self.table_name = 'ichatr_opportunities'

  belongs_to :account
  belongs_to :contact
  belongs_to :pipeline_stage
  belongs_to :origin_conversation, class_name: 'Conversation', optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  has_many :stage_changes, class_name: 'OpportunityStageChange', dependent: :destroy

  enum status: { open: 0, won: 1, lost: 2 }

  validates :title, :contact_id, :pipeline_stage_id, :account_id, presence: true
  validate :pipeline_stage_belongs_to_account
  validate :validate_forward_stage_move_requirements, on: :update, if: :pipeline_stage_id_changed?
  validate :validate_closing_requirements, on: :update, if: :status_changed?

  attr_accessor :missing_required_fields

  before_save :set_or_clear_closed_at, if: :status_changed?
  before_save :reset_closing_required_attributes, if: :status_changed?
  after_create :record_initial_stage_change
  after_update :record_subsequent_stage_change, if: :saved_change_to_pipeline_stage_id?
  after_commit :broadcast_opportunity_updated, on: %i[create update]

  def as_json(options = {})
    super(options).merge(
      'origin_conversation_display_id' => origin_conversation&.display_id,
      'created_at' => created_at.to_i,
      'current_stage_entered_at' => stage_changes.order(changed_at: :desc).first&.changed_at&.to_i,
      'contact' => contact_json,
      'assignee' => assignee_json
    )
  end

  private

  def pipeline_stage_belongs_to_account
    return unless account_id && pipeline_stage_id

    return unless pipeline_stage&.account_id != account_id

    errors.add(:pipeline_stage, 'must belong to the same account')
  end

  def validate_forward_stage_move_requirements
    return unless pipeline_stage_id_was

    old_stage = account.pipeline_stages.find_by(id: pipeline_stage_id_was)
    return unless old_stage && pipeline_stage

    return if pipeline_stage.position <= old_stage.position

    missing_keys = missing_required_keys(pipeline_stage)

    value_missing = pipeline_stage.requires_deal_value? && value.nil?

    return unless missing_keys.any? || value_missing

    self.missing_required_fields = {
      custom_attribute_keys: missing_keys,
      requires_value: value_missing
    }
    errors.add(:base, 'Missing required fields for this stage')
  end

  def validate_closing_requirements
    return unless status.to_s.in?(%w[won lost])

    missing_keys = []
    attrs = custom_attributes || {}

    PipelineClosingRequiredField.where(account_id: account_id, outcome: status).each do |req|
      definition = req.custom_attribute_definition
      missing_keys << definition.attribute_key unless attrs.key?(definition.attribute_key)
    end

    return unless missing_keys.any?

    self.missing_required_fields = { custom_attribute_keys: missing_keys }
    errors.add(:base, 'Missing required fields to close this opportunity')
  end

  def reset_closing_required_attributes
    return unless status.to_s == 'open' && status_was.to_s.in?(%w[won lost])

    definitions = CustomAttributeDefinition
                  .where(id: PipelineClosingRequiredField.where(account_id: account_id, outcome: status_was)
                                                          .select(:custom_attribute_definition_id))
    return if definitions.none?

    attrs = (custom_attributes || {}).dup
    definitions.each do |definition|
      attrs[definition.attribute_key] = definition.attribute_display_type == 'checkbox' ? false : nil
    end
    self.custom_attributes = attrs
  end

  def set_or_clear_closed_at
    if status.to_s.in?(%w[won lost]) && status_was.to_s == 'open'
      self.closed_at = Time.current
    elsif status.to_s == 'open' && status_was.to_s.in?(%w[won lost])
      self.closed_at = nil
    end
    # won↔lost direct switch: no-op — closed_at left as-is
  end

  def record_initial_stage_change
    stage_changes.create!(
      account_id: account_id,
      opportunity_id: id,
      from_stage_id: nil,
      to_stage_id: pipeline_stage_id,
      changed_at: created_at
    )
  end

  def record_subsequent_stage_change
    stage_changes.create!(
      account_id: account_id,
      opportunity_id: id,
      from_stage_id: pipeline_stage_id_before_last_save,
      to_stage_id: pipeline_stage_id,
      changed_at: Time.current
    )
  end

  def broadcast_opportunity_updated
    payload = {
      id: id,
      pipeline_stage_id: pipeline_stage_id,
      status: status,
      contact_id: contact_id,
      assignee_id: assignee_id,
      updated_at: updated_at,
      account_id: account_id,
      origin_conversation_display_id: origin_conversation&.display_id,
      current_stage_entered_at: stage_changes.order(changed_at: :desc).first&.changed_at&.to_i
    }
    ActionCableBroadcastJob.perform_later(["account_#{account_id}"], 'opportunity_updated', payload)
  end

  def contact_json
    return nil unless contact

    { 'id' => contact.id, 'name' => contact.name, 'email' => contact.email, 'avatar_url' => contact.avatar_url }
  end

  def assignee_json
    return nil unless assignee

    { 'id' => assignee.id, 'name' => assignee.name, 'avatar_url' => assignee.avatar_url }
  end

  def missing_required_keys(stage)
    missing_keys = []
    attrs = custom_attributes || {}

    stage.required_custom_attribute_definitions.each do |definition|
      missing_keys << definition.attribute_key unless attrs.key?(definition.attribute_key)
    end

    missing_keys
  end
end
