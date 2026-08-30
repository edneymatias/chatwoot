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

  private

  # A `type: :hash` tool param is sometimes returned by the provider as a JSON-encoded String
  # instead of a parsed object (observed with OpenAI function calling) — coerce it back to a
  # Hash instead of silently dropping the data, matching the pattern already established in
  # AuthHeaderBuilder/CallCustomApi for the same provider quirk.
  def coerce_hash_param(candidate)
    return candidate if candidate.is_a?(Hash)
    return candidate.to_unsafe_h if candidate.respond_to?(:to_unsafe_h)
    return {} unless candidate.is_a?(String)

    JSON.parse(candidate)
  rescue JSON::ParserError
    {}
  end
end
