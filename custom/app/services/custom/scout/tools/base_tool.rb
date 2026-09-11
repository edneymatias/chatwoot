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

  # Human-readable labels for the given custom_attribute keys, scoped to attribute_model. Falls
  # back to a humanized key when no CustomAttributeDefinition matches (e.g. a contact custom
  # attribute the model wrote ad hoc, without a defined schema) — used to tell the model exactly
  # which fields it just wrote, see #scoped_confirmation_reminder.
  def custom_attribute_labels(keys, attribute_model:)
    keys = Array(keys).map(&:to_s)
    return [] if keys.empty?

    known = account.custom_attribute_definitions.where(attribute_model: attribute_model, attribute_key: keys)
                   .pluck(:attribute_key, :attribute_display_name).to_h
    keys.map { |key| known[key] || key.humanize }
  end

  # Just-in-time reminder appended to a data-writing tool's own result, mirroring the pattern
  # used for the no-question handoff nudge (OpportunityStageTransitionService). Telling the model
  # in the system prompt to "only confirm what's new" is not enough on its own — the model still
  # narrates the full accumulated state from memory. Naming the exact fields this call just wrote,
  # right in the tool result, scales to any number of future data-writing tools without the risk
  # growing with each one.
  def scoped_confirmation_reminder(field_labels)
    return '' if field_labels.blank?

    " Dados registrados nesta chamada: #{field_labels.join(', ')}. Ao confirmar ao cliente, mencione apenas isso — " \
      'não repita dados já confirmados em mensagens anteriores desta conversa.'
  end
end
