# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Predicates::Evaluator do
  let(:open_opp) { Struct.new(:status).new('open') }
  let(:won_opp) { Struct.new(:status).new('won') }

  let(:ctx_all_met) do
    Custom::ScoutV2::RoutingContext.new(
      opportunity: open_opp,
      pending_fields: ['email']
    )
  end

  let(:ctx_none_met) do
    Custom::ScoutV2::RoutingContext.new(
      opportunity: won_opp,
      pending_fields: []
    )
  end

  let(:ctx_opp_only) do
    Custom::ScoutV2::RoutingContext.new(
      opportunity: open_opp,
      pending_fields: []
    )
  end

  describe '.call' do
    it 'returns true for empty when_state (vacuous truth)' do
      expect(described_class.call([], ctx_none_met)).to be true
    end

    it 'returns true when all conditions are satisfied' do
      when_state = [
        ['opportunity_open', nil],
        ['pending_required_fields', nil]
      ]
      expect(described_class.call(when_state, ctx_all_met)).to be true
    end

    it 'returns false when any condition is not satisfied' do
      when_state = [
        ['opportunity_open', nil],
        ['pending_required_fields', nil]
      ]
      expect(described_class.call(when_state, ctx_opp_only)).to be false
    end

    it 'returns false when all conditions fail' do
      when_state = [
        ['opportunity_open', nil],
        ['pending_required_fields', nil]
      ]
      expect(described_class.call(when_state, ctx_none_met)).to be false
    end

    it 'propagates ArgumentError for unregistered predicate names' do
      when_state = [['non_existent_predicate', nil]]
      expect { described_class.call(when_state, ctx_all_met) }
        .to raise_error(ArgumentError, /unregistered predicate/i)
    end

    it 'forwards arg parameter to predicate #call' do
      dummy_predicate_class = Class.new(Custom::ScoutV2::Predicates::Base) do
        def call(_ctx, arg = nil)
          arg == 'expected_arg'
        end
      end

      stub_const(
        'Custom::ScoutV2::Predicates::Registry::REGISTRY',
        Custom::ScoutV2::Predicates::Registry::REGISTRY.merge('test_arg_forwarding' => dummy_predicate_class)
      )

      when_state = [%w[test_arg_forwarding expected_arg]]
      expect(described_class.call(when_state, ctx_all_met)).to be true

      when_state_mismatch = [%w[test_arg_forwarding wrong_arg]]
      expect(described_class.call(when_state_mismatch, ctx_all_met)).to be false
    end
  end
end
