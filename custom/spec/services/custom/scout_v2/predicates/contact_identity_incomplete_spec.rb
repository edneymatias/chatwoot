# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Predicates::ContactIdentityIncomplete do
  subject(:predicate) { described_class.new }

  let(:contact_class) { Struct.new(:name, :phone_number) }

  it 'returns true when name is a placeholder even if phone is present' do
    contact = contact_class.new('lindo-peixe-123', '+5511999999999')
    ctx = Custom::ScoutV2::RoutingSnapshot.new(contact: contact)

    expect(predicate.call(ctx)).to be true
  end

  it 'returns true when phone is blank even if name is real' do
    contact = contact_class.new('Carlos Silva', '')
    ctx = Custom::ScoutV2::RoutingSnapshot.new(contact: contact)

    expect(predicate.call(ctx)).to be true
  end

  it 'returns true when both name is placeholder and phone is blank' do
    contact = contact_class.new('lindo-peixe-123', nil)
    ctx = Custom::ScoutV2::RoutingSnapshot.new(contact: contact)

    expect(predicate.call(ctx)).to be true
  end

  it 'returns false when name is real and phone is present' do
    contact = contact_class.new('Carlos Silva', '+5511999999999')
    ctx = Custom::ScoutV2::RoutingSnapshot.new(contact: contact)

    expect(predicate.call(ctx)).to be false
  end

  it 'returns true when contact is nil' do
    ctx = Custom::ScoutV2::RoutingSnapshot.new(contact: nil)

    expect(predicate.call(ctx)).to be true
  end

  it 'reads contact data only without checking opportunity or other models' do
    contact = contact_class.new('Ana Costa', '+5511888888888')
    ctx = Custom::ScoutV2::RoutingSnapshot.new(contact: contact, opportunity: nil)

    expect(predicate.call(ctx)).to be false
  end
end
