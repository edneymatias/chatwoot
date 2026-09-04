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

    reason = event.data[:performed_by].present? ? :resolved_by_agent : :resolved_automatically
    Opportunity.where(account_id: conversation.account_id, active_conversation_id: conversation.id)
               .find_each { |opportunity| opportunity.detach_active_conversation!(reason: reason) }
  end

  def conversation_opened(event)
    conversation = event.data[:conversation]
    return if conversation.blank?

    opportunity = Opportunity.where(account_id: conversation.account_id, status: :open, active_conversation_id: nil)
                             .joins(:opportunity_conversations)
                             .where(opportunity_conversations: { conversation_id: conversation.id })
                             .first
    reason = event.data[:performed_by].present? ? :reopened_by_agent : :reopened_automatically
    opportunity&.reattach_active_conversation!(conversation, reason: reason)
  end

  private

  def broadcast_opportunity(event)
    opportunity = event.data[:opportunity]
    ActionCableBroadcastJob.perform_later(["account_#{opportunity.account_id}"], 'opportunity_updated', opportunity.as_json)
  end
end

ActionCableListener.prepend_mod_with('Custom::ActionCableListener')
