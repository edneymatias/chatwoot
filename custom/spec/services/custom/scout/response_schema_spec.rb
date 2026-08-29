# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::ResponseSchema do
  it 'inherits from RubyLLM::Schema' do
    expect(described_class.superclass).to eq(RubyLLM::Schema)
  end

  it 'is a valid schema' do
    expect(described_class.valid?).to be true
  end

  describe '#to_json_schema' do
    subject(:json_schema) { described_class.new.to_json_schema }

    it 'declares required reasoning and response string properties with strict object constraints' do
      expect(json_schema[:name]).to eq('Custom::Scout::ResponseSchema')
      expect(json_schema[:schema][:type]).to eq('object')
      expect(json_schema[:schema][:properties][:reasoning]).to eq(
        { type: 'string', description: "Scout's internal thought process" }
      )
      expect(json_schema[:schema][:properties][:response]).to eq(
        { type: 'string', description: 'The message to send to the customer' }
      )
      expect(json_schema[:schema][:required]).to contain_exactly(:reasoning, :response)
      expect(json_schema[:schema][:additionalProperties]).to be false
      expect(json_schema[:schema][:strict]).to be true
    end
  end
end
