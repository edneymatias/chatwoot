# frozen_string_literal: true

class Custom::ScoutListener < BaseListener
  def message_created(event)
    message = extract_message_and_account(event)[0]
    return if message.blank?
    return unless message.incoming? && !message.private?

    inbox = message.inbox
    scout = inbox&.scout
    return unless scout&.enabled?

    conversation = message.conversation
    return unless conversation&.pending?

    Custom::Scout::ProcessMessageJob.enqueue_debounced(conversation, scout)
  end
end
