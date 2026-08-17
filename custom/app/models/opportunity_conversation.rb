# frozen_string_literal: true

class OpportunityConversation < ApplicationRecord
  self.table_name = 'ichatr_opportunity_conversations'

  attr_accessor :transferred_from

  belongs_to :account
  belongs_to :opportunity, class_name: 'Opportunity'
  belongs_to :conversation, class_name: 'Conversation'

  validates :account_id, :opportunity_id, :conversation_id, presence: true
  validates :conversation_id, uniqueness: { scope: :opportunity_id }

  after_create :record_activity

  private

  def record_activity
    if transferred_from.present?
      record_transfer_activity
    else
      record_open_activity
    end
  end

  def record_transfer_activity
    opportunity.activities.create!(
      account_id: account_id,
      event_type: 'conversation_transferred_in',
      actor: Current.executed_by || Current.user,
      metadata: {
        conversation_id: conversation_id,
        conversation_display_id: conversation&.display_id,
        is_origin: (conversation_id == opportunity.origin_conversation_id),
        transferred_from_opportunity_id: transferred_from.id,
        transferred_from_opportunity_title: transferred_from.title
      },
      occurred_at: Time.current
    )
  end

  def record_open_activity
    opportunity.activities.create!(
      account_id: account_id,
      event_type: 'conversation_opened',
      actor: Current.executed_by || Current.user,
      metadata: {
        conversation_id: conversation_id,
        conversation_display_id: conversation&.display_id,
        is_origin: (conversation_id == opportunity.origin_conversation_id)
      },
      occurred_at: Time.current
    )
  end
end
