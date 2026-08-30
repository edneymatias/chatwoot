# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::ActionClassifierSchema do
  it 'inherits from RubyLLM::Schema' do
    expect(described_class.superclass).to eq(RubyLLM::Schema)
  end

  it 'is a valid schema' do
    expect(described_class.valid?).to be true
  end

  describe '#to_json_schema' do
    subject(:json_schema) { described_class.new.to_json_schema }

    it 'declares required action property' do
      expect(json_schema[:name]).to eq('Custom::Scout::ActionClassifierSchema')
      expect(json_schema[:schema][:type]).to eq('object')
      expect(json_schema[:schema][:properties][:action][:type]).to eq('string')
      expect(json_schema[:schema][:properties][:action][:enum]).to eq(%w[continue handoff])
    end

    it 'declares nullable action_reason property with strict constraints (required, OpenAI-strict-mode compatible)' do
      expected_reasons = %w[
        explicit_human_request
        human_offer_accepted
        repeated_frustration_or_loop
        out_of_scope_commercial_request
      ]
      any_of = json_schema[:schema][:properties][:action_reason][:anyOf]
      expect(any_of).to include({ type: 'string', enum: expected_reasons })
      expect(any_of).to include({ type: 'null' })
      # every property, including the nullable one, must be in `required` — OpenAI's Structured
      # Outputs strict mode rejects a schema where `required` omits any declared property.
      expect(json_schema[:schema][:required]).to contain_exactly(:action, :action_reason)
      expect(json_schema[:schema][:additionalProperties]).to be false
      expect(json_schema[:schema][:strict]).to be true
    end
  end
end
