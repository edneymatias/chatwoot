# frozen_string_literal: true

class Custom::OpportunityActivityListener < BaseListener
  def opportunity_created(event)
    record(event, 'opportunity_created')
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
