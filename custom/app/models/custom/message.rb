# frozen_string_literal: true

module Custom::Message
  private

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
