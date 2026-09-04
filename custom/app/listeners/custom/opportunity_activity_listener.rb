# frozen_string_literal: true

class Custom::OpportunityActivityListener < BaseListener
  # Fields whose change is worth surfacing in "Histórico da Oportunidade" even when it
  # didn't come from the edit form — e.g. the campaign-resolution job, the referral
  # attribution service, or an automation rule action. pipeline_stage_id/status/
  # active_conversation_id are excluded because they already get their own richer,
  # dedicated events elsewhere.
  AUTO_LOGGED_FIELDS = %w[
    title value assignee_id contact_id custom_attributes lost_reason
    campaign_name campaign_adset_name campaign_ad_name campaign_thumbnail_url
    campaign_resolution_status campaign_platform campaign_source_id campaign_source_url
    campaign_headline campaign_body
  ].freeze

  def opportunity_created(event)
    record(event, 'opportunity_created')
  end

  def opportunity_updated(event)
    data = event_data(event)
    changed_fields = (data[:changed_attributes] || {}).keys & AUTO_LOGGED_FIELDS
    return if changed_fields.empty?

    record(event, 'opportunity_updated', changed_fields: changed_fields)
  end

  def opportunity_stage_changed(event)
    data = event_data(event)
    opportunity = data[:opportunity]
    return if opportunity.blank?

    record(event, 'opportunity_stage_changed',
           from_stage_id: data[:from_pipeline_stage_id],
           to_stage_id: opportunity.pipeline_stage_id)
  end

  def opportunity_won(event)
    data = event_data(event)
    record(event, 'opportunity_won', from_stage_id: data[:from_pipeline_stage_id])
  end

  def opportunity_lost(event)
    data = event_data(event)
    record(event, 'opportunity_lost', from_stage_id: data[:from_pipeline_stage_id])
  end

  def opportunity_reopened(event)
    record(event, 'opportunity_reopened')
  end

  # Hooks into Conversation's existing CONVERSATION_STATUS_CHANGED dispatch (fired on every
  # status transition, snooze included) rather than requiring a new upstream event.
  def conversation_status_changed(event)
    conversation = event.data[:conversation]
    return if conversation.blank? || !conversation.snoozed?

    Opportunity.where(account_id: conversation.account_id, active_conversation_id: conversation.id).find_each do |opportunity|
      opportunity.activities.create!(
        account_id: opportunity.account_id,
        event_type: 'conversation_snoozed',
        actor: event.data[:performed_by],
        metadata: {
          conversation_id: conversation.id,
          conversation_display_id: conversation.display_id,
          snoozed_until: conversation.snoozed_until&.to_i
        },
        occurred_at: event.timestamp || Time.current
      )
    end
  end

  private

  def event_data(event)
    return {}.with_indifferent_access if event&.data.blank?

    event.data.is_a?(Hash) ? event.data.with_indifferent_access : {}.with_indifferent_access
  end

  def record(event, event_type, metadata = {})
    data = event_data(event)
    opportunity = data[:opportunity]
    return if opportunity.blank?

    opportunity.activities.create!(
      account_id: opportunity.account_id,
      event_type: event_type,
      actor: data[:performed_by],
      metadata: metadata,
      occurred_at: event.timestamp || Time.current
    )
  end
end
