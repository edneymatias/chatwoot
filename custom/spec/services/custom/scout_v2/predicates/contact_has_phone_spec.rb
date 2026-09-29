# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Predicates::ContactHasPhone do
  subject(:predicate) { described_class.new }

  let(:contact_class) { Struct.new(:phone_number) }

  it 'returns true when contact phone_number is present' do
    contact = contact_class.new('+5511999999999')
    ctx = Custom::ScoutV2::RoutingSnapshot.new(contact: contact)

    expect(predicate.call(ctx)).to be true
  end

  it 'returns false when contact phone_number is blank' do
    contact_nil = contact_class.new(nil)
    contact_empty = contact_class.new('   ')

    expect(predicate.call(Custom::ScoutV2::RoutingSnapshot.new(contact: contact_nil))).to be false
    expect(predicate.call(Custom::ScoutV2::RoutingSnapshot.new(contact: contact_empty))).to be false
  end

  it 'returns false when contact is nil' do
    ctx = Custom::ScoutV2::RoutingSnapshot.new(contact: nil)

    expect(predicate.call(ctx)).to be false
  end

  it 'accepts optional arg parameter without altering behavior' do
    contact = contact_class.new('+5511999999999')
    ctx = Custom::ScoutV2::RoutingSnapshot.new(contact: contact)

    expect(predicate.call(ctx, 'ignored')).to be true
  end
end
