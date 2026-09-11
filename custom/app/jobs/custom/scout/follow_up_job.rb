# frozen_string_literal: true

class Custom::Scout::FollowUpJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Scout.where(enabled: true).find_each do |scout|
      next if scout.rescue_stage_id.blank?

      stalled_conversations(scout).find_each do |conversation|
        process_conversation(scout, conversation)
      end
    end
  end

  private

  def stalled_conversations(scout)
    return Conversation.none if scout.inboxes.none?

    cutoff = scout.follow_up_delays_hours.first.hours.ago
    Conversation.pending
                .where(inbox_id: scout.inboxes.select(:id))
                .where('last_activity_at < ?', cutoff)
  end

  def process_conversation(scout, conversation)
    return unless conversation_pending?(conversation)
    return if conversation.inbox.out_of_office?

    opportunity = open_opportunity_for(conversation)
    return if opportunity.blank?

    attempts = follow_up_attempts(conversation)
    threshold = scout.follow_up_delays_hours[attempts]
    reference_time = last_non_follow_up_activity_at(conversation)
    return if threshold.blank? || reference_time >= threshold.hours.ago

    execute_follow_up_step(scout, conversation, opportunity, attempts)
  end

  def execute_follow_up_step(scout, conversation, opportunity, attempts)
    if attempts < scout.follow_up_delays_hours.size - 1
      send_nudge(conversation)
    else
      perform_rescue_handoff(scout, conversation, opportunity)
    end
  end

  def open_opportunity_for(conversation)
    Opportunity.joins(:opportunity_conversations)
               .where(opportunity_conversations: { conversation_id: conversation.id }, status: :open)
               .order(updated_at: :desc)
               .first
  end

  def follow_up_attempts(conversation)
    conversation.messages
                .reorder(created_at: :desc, id: :desc)
                .take_while { |m| !m.incoming? }
                .count { |m| m.outgoing? && !m.private? && m.content_attributes['scout_follow_up'] == true }
  end

  def last_non_follow_up_activity_at(conversation)
    last_regular_message = conversation.messages
                                       .reorder(created_at: :desc, id: :desc)
                                       .find { |m| m.content_attributes['scout_follow_up'] != true }

    candidates = [last_regular_message&.created_at, conversation.last_activity_at].compact
    candidates.min || conversation.created_at
  end

  def send_nudge(conversation)
    locale = conversation_locale(conversation)
    Messages::MessageBuilder.new(
      nil,
      conversation,
      {
        content: I18n.t('conversations.scout.follow_up_nudge', locale: locale),
        message_type: 'outgoing',
        private: false,
        content_attributes: { scout_follow_up: true }
      }
    ).perform
  end

  def perform_rescue_handoff(scout, conversation, opportunity)
    opportunity.update!(pipeline_stage_id: scout.rescue_stage_id)
    locale = conversation_locale(conversation)
    reason = "Lead sem resposta após #{scout.follow_up_delays_hours.last} horas de inatividade"

    Custom::Scout::HandoffService.new(scout: scout, conversation: conversation).perform(
      reason: reason,
      message: I18n.t('conversations.scout.follow_up_handoff', locale: locale)
    )
  end

  def conversation_locale(conversation)
    conversation.language.presence || conversation.account.locale.presence || I18n.default_locale.to_s
  end

  def conversation_pending?(conversation)
    status = Conversation.uncached { Conversation.where(id: conversation.id).pick(:status) }
    status == 'pending' || status == Conversation.statuses[:pending]
  end
end
