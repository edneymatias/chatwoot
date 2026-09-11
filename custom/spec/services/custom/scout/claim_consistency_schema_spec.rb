# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::ClaimConsistencySchema do
  it 'inherits from RubyLLM::Schema' do
    expect(described_class.superclass).to eq(RubyLLM::Schema)
  end

  it 'is a valid schema' do
    expect(described_class.valid?).to be true
  end

  describe '#to_json_schema' do
    subject(:json_schema) { described_class.new.to_json_schema }

    it 'declares required decision enum property' do
      expect(json_schema[:name]).to eq('Custom::Scout::ClaimConsistencySchema')
      expect(json_schema[:schema][:type]).to eq('object')
      expect(json_schema[:schema][:properties][:decision][:type]).to eq('string')
      expect(json_schema[:schema][:properties][:decision][:enum]).to eq(%w[safe false_promise false_completed_action])
    end

    it 'declares required reason string property with strict object constraints' do
      expect(json_schema[:schema][:properties][:reason][:type]).to eq('string')
      expect(json_schema[:schema][:required]).to contain_exactly(:decision, :reason)
      expect(json_schema[:schema][:additionalProperties]).to be false
      expect(json_schema[:schema][:strict]).to be true
    end
  end
end
