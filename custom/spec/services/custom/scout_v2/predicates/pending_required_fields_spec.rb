# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Predicates::PendingRequiredFields do
  subject(:predicate) { described_class.new }

  it 'returns true when pending_fields has elements' do
    ctx = Custom::ScoutV2::RoutingContext.new(pending_fields: %w[email phone])
    expect(predicate.call(ctx)).to be true
  end

  it 'returns false when pending_fields is empty' do
    ctx = Custom::ScoutV2::RoutingContext.new(pending_fields: [])
    expect(predicate.call(ctx)).to be false
  end

  it 'returns false when pending_fields is nil' do
    ctx = Custom::ScoutV2::RoutingContext.new(pending_fields: nil)
    expect(predicate.call(ctx)).to be false
  end

  it 'accepts optional arg parameter without altering behavior' do
    ctx = Custom::ScoutV2::RoutingContext.new(pending_fields: ['email'])
    expect(predicate.call(ctx, 'some_arg')).to be true
  end
end
