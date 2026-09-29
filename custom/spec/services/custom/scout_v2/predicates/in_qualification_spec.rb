# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Predicates::InQualification do
  subject(:predicate) { described_class.new }

  let(:opp_class) { Struct.new(:status) }

  it 'returns true when opportunity is nil' do
    ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: nil, pending_fields: ['orcamento'])

    expect(predicate.call(ctx)).to be true
  end

  it 'returns true when opportunity is open and has pending fields' do
    open_opp = opp_class.new('open')
    ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: open_opp, pending_fields: ['orcamento'])

    expect(predicate.call(ctx)).to be true
  end

  it 'returns false when opportunity is open but has no pending fields' do
    open_opp = opp_class.new('open')
    ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: open_opp, pending_fields: [])

    expect(predicate.call(ctx)).to be false
  end

  it 'returns false when opportunity is closed (won) even if pending fields exist' do
    won_opp = opp_class.new('won')
    ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: won_opp, pending_fields: ['orcamento'])

    expect(predicate.call(ctx)).to be false
  end

  it 'returns false when opportunity is closed (lost) even if pending fields exist' do
    lost_opp = opp_class.new('lost')
    ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: lost_opp, pending_fields: ['orcamento'])

    expect(predicate.call(ctx)).to be false
  end
end
