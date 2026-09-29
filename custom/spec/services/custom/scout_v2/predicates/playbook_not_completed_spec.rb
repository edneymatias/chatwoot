# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Predicates::PlaybookNotCompleted do
  subject(:predicate) { described_class.new }

  it 'returns true when playbook name is absent from completed_playbooks' do
    ctx = Custom::ScoutV2::RoutingSnapshot.new(completed_playbooks: ['identificacao'])

    expect(predicate.call(ctx, 'qualificacao')).to be true
    expect(predicate.call(ctx, :qualificacao)).to be true
  end

  it 'returns false when playbook name is present in completed_playbooks' do
    ctx = Custom::ScoutV2::RoutingSnapshot.new(completed_playbooks: ['identificacao'])

    expect(predicate.call(ctx, 'identificacao')).to be false
    expect(predicate.call(ctx, :identificacao)).to be false
  end

  it 'returns true when completed_playbooks is empty' do
    ctx = Custom::ScoutV2::RoutingSnapshot.new(completed_playbooks: [])

    expect(predicate.call(ctx, 'identificacao')).to be true
  end
end
