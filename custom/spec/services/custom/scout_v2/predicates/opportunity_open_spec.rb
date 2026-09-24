# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Predicates::OpportunityOpen do
  subject(:predicate) { described_class.new }

  let(:open_opp) { Struct.new(:status).new('open') }
  let(:won_opp) { Struct.new(:status).new('won') }
  let(:lost_opp) { Struct.new(:status).new('lost') }

  it 'returns true when opportunity status is open' do
    ctx = Custom::ScoutV2::RoutingContext.new(opportunity: open_opp)
    expect(predicate.call(ctx)).to be true
  end

  it 'returns false when opportunity status is won or lost' do
    ctx_won = Custom::ScoutV2::RoutingContext.new(opportunity: won_opp)
    ctx_lost = Custom::ScoutV2::RoutingContext.new(opportunity: lost_opp)

    expect(predicate.call(ctx_won)).to be false
    expect(predicate.call(ctx_lost)).to be false
  end

  it 'returns false when opportunity is nil' do
    ctx = Custom::ScoutV2::RoutingContext.new(opportunity: nil)
    expect(predicate.call(ctx)).to be false
  end

  it 'accepts optional arg parameter without altering behavior' do
    ctx = Custom::ScoutV2::RoutingContext.new(opportunity: open_opp)
    expect(predicate.call(ctx, 'some_arg')).to be true
  end
end
