# frozen_string_literal: true

class Custom::Scout::Tools::BaseTool < RubyLLM::Tool
  attr_reader :scout, :conversation

  def initialize(scout, conversation)
    @scout = scout
    @conversation = conversation
    super()
  end

  def account
    @conversation.account
  end

  def contact
    @conversation.contact
  end
end
