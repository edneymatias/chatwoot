# frozen_string_literal: true

module Custom::ActionCableListener
  def opportunity_created(event)
    broadcast_opportunity(event)
  end

  def opportunity_updated(event)
    broadcast_opportunity(event)
  end

  private

  def broadcast_opportunity(event)
    opportunity = event.data[:opportunity]
    ActionCableBroadcastJob.perform_later(["account_#{opportunity.account_id}"], 'opportunity_updated', opportunity.as_json)
  end
end

ActionCableListener.prepend_mod_with('Custom::ActionCableListener')
