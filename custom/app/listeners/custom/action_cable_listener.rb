# frozen_string_literal: true

module Custom::ActionCableListener
  def opportunity_created(event)
    broadcast_opportunity(event)
  end

  def opportunity_updated(event)
    broadcast_opportunity(event)
  end

  def conversation_resolved(event)
    conversation = event.data[:conversation]
    return if conversation.blank?

    Opportunity.where(account_id: conversation.account_id, active_conversation_id: conversation.id)
               .find_each(&:detach_active_conversation!)
  end

  def conversation_opened(event)
    conversation = event.data[:conversation]
    return if conversation.blank?

    Opportunity.where(account_id: conversation.account_id, status: :open, active_conversation_id: nil)
               .joins(:opportunity_conversations)
               .where(opportunity_conversations: { conversation_id: conversation.id })
               .first
               &.update!(active_conversation: conversation)
  end

  def conversation_deleted(event)
    conversation_data = event.data[:conversation_data]
    return if conversation_data.blank?

    Opportunity.where(account_id: conversation_data[:account_id], active_conversation_id: conversation_data[:id])
               .find_each(&:detach_active_conversation!)
  end

  private

  def broadcast_opportunity(event)
    opportunity = event.data[:opportunity]
    ActionCableBroadcastJob.perform_later(["account_#{opportunity.account_id}"], 'opportunity_updated', opportunity.as_json)
  end
end

ActionCableListener.prepend_mod_with('Custom::ActionCableListener')
