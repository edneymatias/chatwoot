# frozen_string_literal: true

module Custom::AsyncDispatcher
  def listeners
    super + [Custom::OpportunityActivityListener.instance]
  end
end
