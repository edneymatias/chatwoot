require 'rails_helper'

RSpec.describe Reports::StageReachCalculator, type: :service do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let!(:stage1) { account.pipeline_stages.create!(name: 'Stage 1', position: 1) }
  let!(:stage2) { account.pipeline_stages.create!(name: 'Stage 2', position: 2) }
  let!(:stage3) { account.pipeline_stages.create!(name: 'Stage 3', position: 3) }
  let(:stages) { [stage1, stage2, stage3] }

  let(:contact) { create(:contact, account: account) }
  let(:opp1) { Opportunity.create!(account: account, contact: contact, pipeline_stage: stage1, title: 'Opp 1') }
  let(:opp2) { Opportunity.create!(account: account, contact: contact, pipeline_stage: stage1, title: 'Opp 2') }

  it 'returns empty hash default 0 when opportunity_ids is empty' do
    calculator = described_class.new(account: account, opportunity_ids: [], stages: stages)
    result = calculator.calculate
    expect(result[999]).to eq(0)
  end

  it 'computes max stage position reached across stage changes' do
    OpportunityStageChange.create!(account: account, opportunity: opp1, from_stage: stage1, to_stage: stage2, changed_at: Time.current)
    OpportunityStageChange.create!(account: account, opportunity: opp1, from_stage: stage2, to_stage: stage3, changed_at: Time.current)
    OpportunityStageChange.create!(account: account, opportunity: opp2, from_stage: stage1, to_stage: stage2, changed_at: Time.current)

    calculator = described_class.new(account: account, opportunity_ids: [opp1.id, opp2.id], stages: stages)
    result = calculator.calculate

    expect(result[opp1.id]).to eq(3)
    expect(result[opp2.id]).to eq(2)
  end

  it 'does not count stage changes belonging to another account' do
    other_stage = other_account.pipeline_stages.create!(name: 'Other Stage', position: 5)
    OpportunityStageChange.create!(account: other_account, opportunity: opp1, from_stage: nil, to_stage: other_stage, changed_at: Time.current)

    calculator = described_class.new(account: account, opportunity_ids: [opp1.id], stages: stages)
    result = calculator.calculate

    expect(result[opp1.id]).to eq(1)
  end
end
