# frozen_string_literal: true

class Custom::Scout::ProcessMessageJob < ApplicationJob
  queue_as :default

  LAST_MESSAGE_KEY = 'scout:debounce:conversation:%<conversation_id>s:last_message_at'
  ENQUEUED_KEY = 'scout:debounce:conversation:%<conversation_id>s:enqueued'
  LOCK_TTL = 3600

  def self.enqueue_debounced(conversation, scout)
    last_msg_key = format(LAST_MESSAGE_KEY, conversation_id: conversation.id)
    enqueued_key = format(ENQUEUED_KEY, conversation_id: conversation.id)

    Redis::Alfred.set(last_msg_key, Time.current.to_f, ex: LOCK_TTL)
    delay = scout.debounce_delay_seconds

    return unless Redis::Alfred.set(enqueued_key, true, nx: true, ex: LOCK_TTL)

    set(wait: delay.seconds).perform_later(conversation.id)
  end

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    scout = conversation.inbox&.scout
    return unless scout&.enabled?
    return unless conversation_pending?(conversation)

    process_debounce(conversation, scout)
  end

  private

  def process_debounce(conversation, scout)
    last_msg_key = format(LAST_MESSAGE_KEY, conversation_id: conversation.id)
    enqueued_key = format(ENQUEUED_KEY, conversation_id: conversation.id)

    last_message_at = Redis::Alfred.get(last_msg_key).to_f
    delay = scout.debounce_delay_seconds
    elapsed = Time.current.to_f - last_message_at

    if elapsed < delay
      remaining = [(delay - elapsed).ceil, 1].max
      self.class.set(wait: remaining.seconds).perform_later(conversation.id)
    else
      Redis::Alfred.delete(enqueued_key)
      Redis::Alfred.delete(last_msg_key)
      Custom::Scout::AgentRunner.new(scout: scout, conversation: conversation).perform
    end
  end

  def conversation_pending?(conversation)
    status = Conversation.uncached { Conversation.where(id: conversation.id).pick(:status) }
    status == 'pending' || status == Conversation.statuses[:pending]
  end
end
