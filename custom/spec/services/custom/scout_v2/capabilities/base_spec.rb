# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Capabilities::Base do
  let(:test_capability_class) do
    Class.new(described_class) do
      capability_name 'test_cap'

      operation :sample do
        input :date, type: 'date', required: true
        input :notes, type: 'string', required: false
        output required: %w[id], shape: :record
      end
    end
  end

  describe 'DSL' do
    it 'declares and returns capability_name' do
      expect(test_capability_class.capability_name).to eq('test_cap')
    end

    it 'declares and exposes operations map' do
      operations = test_capability_class.operations
      expect(operations).to have_key('sample')

      sample_op = operations['sample']
      expect(sample_op.name).to eq('sample')
      expect(sample_op.inputs.map(&:name)).to eq(%w[date notes])
      expect(sample_op.output.required).to eq(%w[id])
      expect(sample_op.output.shape).to eq(:record)
    end

    it 'initializes with provider and conversation' do
      provider = Erp::BaseAdapter.new(nil)
      conversation = create(:conversation)
      instance = test_capability_class.new(provider: provider, conversation: conversation)

      expect(instance.provider).to eq(provider)
      expect(instance.conversation).to eq(conversation)
    end
  end

  describe 'catalog parity' do
    it 'has defined subclasses whose capability_names exactly match Catalog::KNOWN_NAMES' do
      known_names = Custom::ScoutV2::Capabilities::Catalog::KNOWN_NAMES
      defined_names = [
        Custom::ScoutV2::Capabilities::Scheduling.capability_name,
        Custom::ScoutV2::Capabilities::CustomerRegistry.capability_name
      ]

      expect(defined_names).to match_array(known_names)
    end
  end
end
