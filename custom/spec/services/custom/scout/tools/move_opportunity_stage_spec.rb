# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::Tools::MoveOpportunityStage do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:stage1) { PipelineStage.create!(account: account, name: 'Triage', position: 1) }
  let(:stage2) { PipelineStage.create!(account: account, name: 'Negotiation', position: 2) }
  let(:stage_unqualified) { PipelineStage.create!(account: account, name: 'Unqualified', position: 3) }

  let(:attr_budget) do
    CustomAttributeDefinition.create!(
      account: account,
      attribute_key: 'budget',
      attribute_display_name: 'Budget',
      attribute_display_type: 'currency',
      attribute_model: 'opportunity_attribute'
    )
  end

  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Test Scout',
      default_pipeline_stage: stage1,
      unqualified_stage: stage_unqualified,
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
          title: 'Opp Test',
          status: :open
        )
      end

      it 'moves stage to target stage successfully' do
        result = tool.execute(stage_id: stage2.id)
        expect(result).to include('successfully')
        expect(opportunity.reload.pipeline_stage_id).to eq(stage2.id)
      end

      it 'returns descriptive failure message when stage required fields are missing' do
        stage2.required_custom_attribute_definitions << attr_budget

        result = tool.execute(stage_id: stage2.id)
        expect(result).to include('Cannot move to stage Negotiation')
        expect(result).to include('Budget')
        expect(opportunity.reload.pipeline_stage_id).to eq(stage1.id)
      end

      it 'moves to unqualified stage leaving status open (User Story 5)' do
        result = tool.execute(stage_id: stage_unqualified.id)
        expect(result).to include('successfully')
        opportunity.reload
        expect(opportunity.pipeline_stage_id).to eq(stage_unqualified.id)
        expect(opportunity.status).to eq('open')
      end

      it 'delegates transition to Custom::Scout::OpportunityStageTransitionService' do
        transition_service = instance_double(Custom::Scout::OpportunityStageTransitionService, call: 'Transition executed')
        allow(Custom::Scout::OpportunityStageTransitionService).to receive(:new).with(
          scout: scout,
          conversation: conversation,
          opportunity: opportunity
        ).and_return(transition_service)

        result = tool.execute(stage_id: stage2.id)
        expect(result).to eq('Transition executed')
        expect(transition_service).to have_received(:call).with(stage_id: stage2.id)
      end
    end
  end
end
