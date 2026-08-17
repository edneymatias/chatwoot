# frozen_string_literal: true

class Opportunity < ApplicationRecord
  self.table_name = 'ichatr_opportunities'

  include Custom::Concerns::OpportunityValidations
  include Custom::Concerns::OpportunityCampaignAttribution

  belongs_to :account
  belongs_to :contact
  belongs_to :pipeline_stage
  belongs_to :origin_conversation, class_name: 'Conversation', optional: true
  belongs_to :active_conversation, class_name: 'Conversation', optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  has_many :stage_changes, class_name: 'OpportunityStageChange', dependent: :destroy
  has_many :opportunity_conversations, class_name: 'OpportunityConversation', dependent: :destroy
  has_many :conversations, through: :opportunity_conversations

  enum status: { open: 0, won: 1, lost: 2 }

  attr_accessor :missing_required_fields

  before_save :set_or_clear_closed_at, if: :status_changed?
  before_save :reset_closing_required_attributes, if: :status_changed?
  before_create :set_default_active_conversation
  after_create :record_initial_stage_change
  after_create :record_origin_conversation_link
  after_update :record_subsequent_stage_change, if: :saved_change_to_pipeline_stage_id?
  after_commit :broadcast_opportunity_updated, on: %i[create update]

  def attach_conversation!(conversation, set_active: true)
    transaction do
      opportunity_conversations.find_or_create_by!(
        account_id: account_id,
        conversation_id: conversation.id
      ) do |oc|
        oc.is_origin = (conversation.id == origin_conversation_id)
      end
      update!(active_conversation: conversation) if set_active && conversation.open?
    end
  end

  def detach_active_conversation!
    update!(active_conversation: nil) if active_conversation_id.present?
  end

  def associated_conversations_json
    opportunity_conversations.includes(conversation: :inbox).order(created_at: :desc).filter_map do |oc|
      conv = oc.conversation
      next unless conv

      {
        'id' => conv.id,
        'display_id' => conv.display_id,
        'status' => conv.status,
        'inbox_id' => conv.inbox_id,
        'inbox_name' => conv.inbox&.name,
        'channel_type' => conv.inbox&.channel_type,
        'created_at' => conv.created_at.to_i,
        'is_active' => (conv.id == active_conversation_id),
        'is_origin' => oc.is_origin
      }
    end
  end

  def as_json(options = {})
    super(options).merge(
      'active_conversation_id' => active_conversation_id,
      'active_conversation_display_id' => active_conversation&.display_id,
      'origin_conversation_display_id' => origin_conversation&.display_id,
      'associated_conversations' => associated_conversations_json,
      'created_at' => created_at.to_i,
      'current_stage_entered_at' => stage_changes.order(changed_at: :desc).first&.changed_at&.to_i,
      'contact' => contact_json,
      'assignee' => assignee_json
    ).merge(campaign_json)
  end

  private

  def set_default_active_conversation
    return if active_conversation_id.present? || origin_conversation_id.blank?
    return unless origin_conversation&.open?

    self.active_conversation_id = origin_conversation_id
  end

  def record_origin_conversation_link
    return if origin_conversation_id.blank?

    opportunity_conversations.find_or_create_by!(
      account_id: account_id,
      conversation_id: origin_conversation_id
    ) do |oc|
      oc.is_origin = true
    end
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
    event_data = {
      opportunity: self,
      changed_attributes: saved_changes,
      from_pipeline_stage_id: pipeline_stage_id_before_last_save,
      performed_by: Current.executed_by || Current.user
    }

    if previously_new_record?
      dispatch_event('opportunity_created', event_data)
    else
      dispatch_event('opportunity_updated', event_data)
      dispatch_status_and_stage_events(event_data)
    end
  end

  def dispatch_status_and_stage_events(event_data)
    dispatch_event('opportunity_stage_changed', event_data) if saved_change_to_pipeline_stage_id?
    return unless saved_change_to_status?

    dispatch_status_transition_event(event_data)
  end

  def dispatch_status_transition_event(event_data)
    case status.to_s
    when 'won'
      dispatch_event('opportunity_won', event_data)
    when 'lost'
      dispatch_event('opportunity_lost', event_data)
    when 'open'
      dispatch_event('opportunity_reopened', event_data) if status_before_last_save.in?(%w[won lost])
    end
  end

  def dispatch_event(name, event_data)
    Rails.configuration.dispatcher.dispatch(name, Time.zone.now, event_data)
  end

  def contact_json
    return nil unless contact

    { 'id' => contact.id, 'name' => contact.name, 'email' => contact.email, 'avatar_url' => contact.avatar_url }
  end

  def assignee_json
    return nil unless assignee

    { 'id' => assignee.id, 'name' => assignee.name, 'avatar_url' => assignee.avatar_url }
  end
end
