# frozen_string_literal: true

module Custom::Concerns::OpportunityConversationManagement
  extend ActiveSupport::Concern

  def attach_conversation!(conversation, set_active: true, transferred_from: nil)
    transaction do
      oc = opportunity_conversations.find_or_initialize_by(
        account_id: account_id,
        conversation_id: conversation.id
      )
      is_new = oc.new_record?
      oc.is_origin = (conversation.id == origin_conversation_id) if is_new
      oc.transferred_from = transferred_from if is_new && transferred_from.present?
      oc.save!

      record_relinked_transfer(conversation, transferred_from) if transferred_from.present? && !is_new
      update!(active_conversation: conversation) if set_active && conversation.open?
    end
  end

  # Re-marks an already-linked conversation as active (e.g. it reopened after being
  # resolved/snoozed) without going through the OpportunityConversation link/transfer bookkeeping.
  def reattach_active_conversation!(conversation, reason:)
    transaction do
      update!(active_conversation: conversation)
      activities.create!(
        account_id: account_id,
        event_type: 'conversation_reopened',
        actor: Current.executed_by || Current.user,
        metadata: { conversation_id: conversation.id, conversation_display_id: conversation.display_id, reason: reason },
        occurred_at: Time.current
      )
    end
  end

  def detach_active_conversation!(transferred_to: nil, reason: nil)
    return if active_conversation_id.blank?

    conv = active_conversation
    transaction do
      record_detached_activity(conv, transferred_to, reason)
      update!(active_conversation: nil)
    end
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

  private

  def record_relinked_transfer(conversation, transferred_from)
    activities.create!(
      account_id: account_id,
      event_type: 'conversation_transferred_in',
      actor: Current.executed_by || Current.user,
      metadata: {
        conversation_id: conversation.id,
        conversation_display_id: conversation.display_id,
        is_origin: false,
        transferred_from_opportunity_id: transferred_from.id,
        transferred_from_opportunity_title: transferred_from.title
      },
      occurred_at: Time.current
    )
  end

  def record_detached_activity(conv, transferred_to, reason)
    if transferred_to.present?
      record_transfer_out_activity(conv, transferred_to)
    else
      record_detached_simple_activity(conv, reason)
    end
  end

  def record_transfer_out_activity(conv, transferred_to)
    activities.create!(
      account_id: account_id,
      event_type: 'conversation_transferred_out',
      actor: Current.executed_by || Current.user,
      metadata: {
        conversation_id: conv.id,
        conversation_display_id: conv.display_id,
        transferred_to_opportunity_id: transferred_to.id,
        transferred_to_opportunity_title: transferred_to.title
      },
      occurred_at: Time.current
    )
  end

  def record_detached_simple_activity(conv, reason)
    activities.create!(
      account_id: account_id,
      event_type: 'conversation_detached',
      actor: Current.executed_by || Current.user,
      metadata: { conversation_id: conv.id, conversation_display_id: conv.display_id, reason: reason },
      occurred_at: Time.current
    )
  end
end
