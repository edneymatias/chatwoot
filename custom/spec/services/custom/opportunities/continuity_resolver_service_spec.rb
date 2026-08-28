# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Opportunities::ContinuityResolverService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:stage) { PipelineStage.create!(account: account, name: 'Lead', position: 1) }

  describe '#call' do
    context 'when contact has zero open opportunities' do
      it 'returns :create_new outcome with empty candidates and descriptive reason' do
        service = described_class.new(account: account, contact: contact)
        decision = service.call

        expect(decision.outcome).to eq(:create_new)
        expect(decision.opportunity).to be_nil
        expect(decision.candidates).to eq([])
        expect(decision.reason).to be_present
      end

      it 'ignores won and lost opportunities and returns :create_new' do
        Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, status: :won, title: 'Won Deal')
        Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, status: :lost, title: 'Lost Deal')

        service = described_class.new(account: account, contact: contact)
        decision = service.call

        expect(decision.outcome).to eq(:create_new)
        expect(decision.opportunity).to be_nil
        expect(decision.candidates).to be_empty
      end
    end

    context 'when contact has open opportunities and a valid matching opportunity_id is declared' do
      let!(:open_opp) do
        Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, status: :open, title: 'Open Deal 1')
      end
      let!(:open_opp2) do
        Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, status: :open, title: 'Open Deal 2')
      end

      it 'returns :reuse with the matched opportunity' do
        service = described_class.new(account: account, contact: contact, declared_opportunity_id: open_opp.id)
        decision = service.call

        expect(decision.outcome).to eq(:reuse)
        expect(decision.opportunity).to eq(open_opp)
        expect(decision.candidates).to contain_exactly(open_opp, open_opp2)
        expect(decision.reason).to include(open_opp.id.to_s)
      end
    end

    context 'when contact has open opportunities and no opportunity_id is declared' do
      let!(:open_opp) do
        Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, status: :open, title: 'Open Deal 1')
      end

      it 'returns :ambiguous without modifying or selecting an opportunity' do
        service = described_class.new(account: account, contact: contact, declared_opportunity_id: nil)
        decision = service.call

        expect(decision.outcome).to eq(:ambiguous)
        expect(decision.opportunity).to be_nil
        expect(decision.candidates).to eq([open_opp])
        expect(decision.reason).to include('1 open opportunity candidate(s)')
      end
    end

    context 'when declared opportunity_id does not belong to contact open opportunities' do
      let!(:open_opp) do
        Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, status: :open, title: 'Open Deal 1')
      end
      let(:other_contact) { create(:contact, account: account) }
      let!(:other_contact_opp) do
        Opportunity.create!(account: account, contact: other_contact, pipeline_stage: stage, status: :open, title: 'Other Deal')
      end

      it 'returns :ambiguous when declared ID belongs to another contact' do
        service = described_class.new(account: account, contact: contact, declared_opportunity_id: other_contact_opp.id)
        decision = service.call

        expect(decision.outcome).to eq(:ambiguous)
        expect(decision.opportunity).to be_nil
        expect(decision.candidates).to eq([open_opp])
        expect(decision.reason).to include(other_contact_opp.id.to_s)
      end

      it 'returns :ambiguous when declared ID does not exist' do
        service = described_class.new(account: account, contact: contact, declared_opportunity_id: 999_999)
        decision = service.call

        expect(decision.outcome).to eq(:ambiguous)
        expect(decision.opportunity).to be_nil
        expect(decision.candidates).to eq([open_opp])
      end
    end

    context 'when account scoping does not match contact account' do
      let(:other_account) { create(:account) }

      it 'returns empty candidates and :create_new' do
        service = described_class.new(account: other_account, contact: contact)
        decision = service.call

        expect(decision.outcome).to eq(:create_new)
        expect(decision.candidates).to be_empty
      end
    end

    context 'when state changes between sequential calls' do
      it 'queries freshly without memoization or stale candidate caching' do
        service = described_class.new(account: account, contact: contact)
        first_decision = service.call

        expect(first_decision.outcome).to eq(:create_new)
        expect(first_decision.candidates).to be_empty

        new_opp = Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: stage,
          status: :open,
          title: 'Newly Created Open Deal'
        )

        second_decision = service.call

        expect(second_decision.outcome).to eq(:ambiguous)
        expect(second_decision.candidates).to eq([new_opp])
      end
    end
  end
end
