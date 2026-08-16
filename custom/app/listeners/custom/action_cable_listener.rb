module Custom::ActionCableListener
  def opportunity_updated(event)
    opportunity = event.data[:opportunity]
    ActionCableBroadcastJob.perform_later(["account_#{opportunity.account_id}"], 'opportunity_updated', opportunity.as_json)
  end
end

ActionCableListener.prepend_mod_with('Custom::ActionCableListener')
