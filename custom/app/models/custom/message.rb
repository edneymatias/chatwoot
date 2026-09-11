# frozen_string_literal: true

module Custom::Message
  private

  def reopen_resolved_conversation
    scout = conversation.inbox&.scout

    return super if scout.blank? || !scout.enabled?

    unless scout.engages?(conversation.contact, conversation)
      Current.executed_by = sender if conversation.inbox.api? && reopened_by_contact?
      return conversation.open!
    end

    super
  end

  def mark_pending_conversation_as_open_for_human_response
    super

    return unless scout_pending_conversation?
    return unless human_response?
    return if private?

    conversation.open!
  end

  def scout_pending_conversation?
    return false unless conversation.pending?

    conversation.inbox&.scout&.enabled? || false
  end
end
