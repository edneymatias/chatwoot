# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Predicates::OpportunityInStage do
  subject(:predicate) { described_class.new }

  it 'defines valid ROLES' do
    expect(described_class::ROLES).to contain_exactly('qualified', 'unqualified', 'initial')
  end

  it 'matches qualified role only when opportunity_stage_role is qualified' do
    ctx_qualified = Custom::ScoutV2::RoutingSnapshot.new(opportunity_stage_role: :qualified)
    ctx_unqualified = Custom::ScoutV2::RoutingSnapshot.new(opportunity_stage_role: :unqualified)
    ctx_initial = Custom::ScoutV2::RoutingSnapshot.new(opportunity_stage_role: :initial)

    expect(predicate.call(ctx_qualified, 'qualified')).to be true
    expect(predicate.call(ctx_unqualified, 'qualified')).to be false
    expect(predicate.call(ctx_initial, 'qualified')).to be false
  end

  it 'matches unqualified role only when opportunity_stage_role is unqualified' do
    ctx_unqualified = Custom::ScoutV2::RoutingSnapshot.new(opportunity_stage_role: :unqualified)
    ctx_qualified = Custom::ScoutV2::RoutingSnapshot.new(opportunity_stage_role: :qualified)

    expect(predicate.call(ctx_unqualified, 'unqualified')).to be true
    expect(predicate.call(ctx_qualified, 'unqualified')).to be false
  end

  it 'matches initial role only when opportunity_stage_role is initial' do
    ctx_initial = Custom::ScoutV2::RoutingSnapshot.new(opportunity_stage_role: :initial)
    ctx_qualified = Custom::ScoutV2::RoutingSnapshot.new(opportunity_stage_role: :qualified)

    expect(predicate.call(ctx_initial, 'initial')).to be true
    expect(predicate.call(ctx_qualified, 'initial')).to be false
  end

  it 'returns false when opportunity_stage_role is :none or opportunity is absent' do
    ctx_none = Custom::ScoutV2::RoutingSnapshot.new(opportunity_stage_role: :none)

    expect(predicate.call(ctx_none, 'qualified')).to be false
    expect(predicate.call(ctx_none, 'unqualified')).to be false
    expect(predicate.call(ctx_none, 'initial')).to be false
  end
end
