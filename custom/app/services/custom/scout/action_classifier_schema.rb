# frozen_string_literal: true

class Custom::Scout::ActionClassifierSchema < RubyLLM::Schema
  ACTIONS = %w[continue handoff].freeze
  REASONS = %w[
    explicit_human_request
    human_offer_accepted
    repeated_frustration_or_loop
    out_of_scope_commercial_request
  ].freeze

  string :action, enum: ACTIONS, description: 'Whether the conversation should continue with Scout or handoff to a human agent'

  # OpenAI's Structured Outputs (strict mode) requires every declared property to appear in
  # `required` — a plain `required: false` string field is rejected outright. `any_of` + `null`
  # is the gem's documented way to keep the field required while allowing a null value when
  # action is 'continue' (see ruby_llm-schema README, "Schema Property Types").
  any_of :action_reason, description: 'The reason for the selected action decision; null when action is continue' do
    string enum: REASONS
    null
  end
end
