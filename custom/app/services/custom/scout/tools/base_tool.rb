# frozen_string_literal: true

class Custom::Scout::Tools::BaseTool < RubyLLM::Tool
  attr_reader :scout, :conversation, :playground

  def initialize(scout, conversation, playground: false)
    @scout = scout
    @conversation = conversation
    @playground = playground
    super()
  end

  def playground?
    @playground == true
  end

  def account
    @conversation&.account || @scout&.account
  end

  def contact
    @conversation&.contact
  end
end
