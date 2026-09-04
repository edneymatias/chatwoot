# frozen_string_literal: true

module Custom::Whatsapp::IncomingMessageBaseService
  private

  def process_statuses
    status = @processed_params[:statuses].first
    return if status.blank?

    recipient = Custom::CampaignRecipient.find_by(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      source_id: status[:id]
    )
    recipient&.update_from_whatsapp_status!(status)

    message_found = find_message_by_source_id(status[:id])
    if message_found
      update_whatsapp_identifiers_from_status(status)
      update_message_with_status(@message, status)
    end

    enqueue_deferred_recipient_status_update(status) if recipient.blank? && message_found.blank?
  rescue ArgumentError => e
    Rails.logger.error "Error while processing whatsapp status update #{e.message}"
  end

  # Mirrors Enterprise::Whatsapp::IncomingMessageBaseService's own deferred-reconciliation
  # safety net (Campaigns::UpdateRecipientStatusJob), retargeted at Custom::CampaignRecipient —
  # Enterprise's job only ever queries the Enterprise campaign_recipients table, which this
  # fork never writes to, so it cannot help our own recipients. Guards against the rare race
  # where a status webhook beats our own mark_sent! write to Custom::CampaignRecipient.
  def enqueue_deferred_recipient_status_update(status)
    return unless inbox.account.feature_enabled?(:whatsapp_campaign)
    return unless %w[delivered read failed].include?(status[:status].to_s)

    Custom::UpdateCampaignRecipientStatusJob.set(wait: 2.seconds).perform_later(inbox.id, status.to_h)
  end

  def set_conversation
    is_new = @conversation.nil?
    super

    correlate_campaign_and_backfill_context if is_new && @conversation&.previously_new_record?
  end

  def correlate_campaign_and_backfill_context
    return if @contact.blank? || messages_data.blank?

    raw_message = messages_data.first
    recipient = find_campaign_recipient_for_reply(raw_message)
    return if recipient.blank?

    @conversation.update!(campaign_id: recipient.campaign_id)
    record_recipient_reply(recipient, raw_message)
    backfill_campaign_context_message(recipient)
  end

  def find_campaign_recipient_for_reply(raw_message)
    context_id = raw_message['context']&.[]('id') || raw_message.dig(:context, :id)
    if context_id.present?
      Custom::CampaignRecipient.find_by(
        account_id: inbox.account_id,
        inbox_id: inbox.id,
        source_id: context_id
      )
    else
      find_single_candidate_recipient
    end
  end

  def find_single_candidate_recipient
    candidates = Custom::CampaignRecipient.where(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: @contact.id,
      status: %i[sent delivered read],
      replied_at: nil
    ).where('sent_at > ?', 72.hours.ago)

    candidates.count == 1 ? candidates.first : nil
  end

  def record_recipient_reply(recipient, raw_message)
    reply_label = raw_message.dig(:interactive, :button_reply, :title) ||
                  raw_message.dig('interactive', 'button_reply', 'title') ||
                  raw_message.dig(:button, :text) ||
                  raw_message.dig('button', 'text')

    reply_type = reply_label.present? ? :quick_reply : :free_text
    inbound_source_id = (raw_message[:id] || raw_message['id']).to_s

    recipient.mark_replied!(
      reply_source_id: inbound_source_id,
      reply_type: reply_type,
      reply_label: reply_label
    )
  end

  def backfill_campaign_context_message(recipient)
    return if recipient.campaign_message_id.present? || recipient.message_content.blank?

    campaign = recipient.campaign
    context_msg = @conversation.messages.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: :outgoing,
      status: :sent,
      content: recipient.message_content,
      sender: campaign.sender,
      source_id: recipient.source_id,
      created_at: recipient.sent_at || Time.current,
      content_attributes: { campaign_context: true }
    )
    recipient.update!(campaign_message_id: context_msg.id)
  end
end
