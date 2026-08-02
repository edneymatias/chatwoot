class Opportunity < ApplicationRecord
  self.table_name = 'matias_opportunities'

  belongs_to :account
  belongs_to :contact
  belongs_to :pipeline_stage
  belongs_to :origin_conversation, class_name: 'Conversation', optional: true
  belongs_to :assignee, class_name: 'User', optional: true

  enum status: { open: 0, won: 1, lost: 2 }

  validates :title, :contact_id, :pipeline_stage_id, :account_id, presence: true
  validate :pipeline_stage_belongs_to_account
  validate :validate_forward_stage_move_requirements, on: :update, if: :pipeline_stage_id_changed?

  attr_accessor :missing_required_fields

  after_commit :broadcast_opportunity_updated, on: %i[create update]

  def as_json(options = {})
    super(options).merge(
      'origin_conversation_display_id' => origin_conversation&.display_id,
      'created_at' => created_at.to_i,
      'contact' => contact ? { 'id' => contact.id, 'name' => contact.name, 'email' => contact.email, 'avatar_url' => contact.avatar_url } : nil,
      'assignee' => assignee ? { 'id' => assignee.id, 'name' => assignee.name, 'avatar_url' => assignee.avatar_url } : nil
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

    missing_keys = []
    attrs = custom_attributes || {}

    pipeline_stage.required_custom_attribute_definitions.each do |definition|
      missing_keys << definition.attribute_key unless attrs.key?(definition.attribute_key)
    end

    value_missing = pipeline_stage.requires_deal_value? && value.nil?

    return unless missing_keys.any? || value_missing

    self.missing_required_fields = {
      custom_attribute_keys: missing_keys,
      requires_value: value_missing
    }
    errors.add(:base, 'Missing required fields for this stage')
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
      origin_conversation_display_id: origin_conversation&.display_id
    }
    ActionCableBroadcastJob.perform_later(["account_#{account_id}"], 'opportunity_updated', payload)
  end
end
