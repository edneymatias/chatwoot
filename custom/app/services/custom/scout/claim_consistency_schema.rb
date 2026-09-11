# frozen_string_literal: true

class Custom::Scout::ClaimConsistencySchema < RubyLLM::Schema
  DECISIONS = %w[safe false_promise false_completed_action].freeze

  string :decision, enum: DECISIONS, description: 'Whether the response is consistent, makes a false promise, or falsely claims a completed action'
  string :reason, description: 'Short justification for the selected decision'
end
