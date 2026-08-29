# frozen_string_literal: true

class Custom::Scout::Tools::BaseTool < RubyLLM::Tool
  include Integrations::LlmInstrumentation

  attr_reader :scout, :conversation, :playground

  def initialize(scout, conversation, playground: false)
    @scout = scout
    @conversation = conversation
    @playground = playground
    super()
  end

  def call(args = {})
    instrument_tool_call(name, args) do
      super(args)
    end
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
