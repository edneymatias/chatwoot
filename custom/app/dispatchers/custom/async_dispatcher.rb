# frozen_string_literal: true

module Custom::AsyncDispatcher
  def listeners
    super + [
      Custom::OpportunityActivityListener.instance,
      Custom::ScoutListener.instance
    ]
  end
end
