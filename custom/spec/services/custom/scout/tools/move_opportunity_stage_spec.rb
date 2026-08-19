# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::Tools::MoveOpportunityStage do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:stage1) { PipelineStage.create!(account: account, name: 'Triage') }
  let(:stage2) { PipelineStage.create!(account: account, name: 'Negotiation') }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Test Scout',
      provider: :gemini,
      model_name: 'gemini-2.0-flash',
      enabled: true
    )
  end
  let(:tool) { described_class.new(scout, conversation) }

  describe '#execute' do
    context 'when no opportunity exists' do
      it 'returns graceful message without error' do
        result = tool.execute(stage_id: stage1.id)
        expect(result).to eq('No opportunity found for this conversation.')
      end
    end

    context 'when opportunity exists' do
      let!(:opportunity) do
        Opportunity.create!(
          account: account,
          contact: contact,
          origin_conversation: conversation,
          pipeline_stage: stage1,
          title: 'Opp Test'
        )
      end

      it 'moves stage to target stage' do
        result = tool.execute(stage_id: stage2.id)
        expect(result).to include('successfully')
        expect(opportunity.reload.pipeline_stage_id).to eq(stage2.id)
      end

      it 'persists lost_reason when provided' do
        result = tool.execute(stage_id: stage2.id, lost_reason: 'Sem orçamento')
        expect(result).to include('successfully')
        opportunity.reload
        expect(opportunity.pipeline_stage_id).to eq(stage2.id)
        expect(opportunity.lost_reason).to eq('Sem orçamento')
        expect(opportunity.status).to eq('lost')
      end
    end
  end
end
