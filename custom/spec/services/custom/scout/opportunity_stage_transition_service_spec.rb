# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::OpportunityStageTransitionService do
  let(:conversation) { create(:conversation, status: :pending) }
  let(:account) { conversation.account }
  let(:team) { create(:team, account: account) }
  let(:stage1) { PipelineStage.create!(account: account, name: 'Triage', position: 1) }
  let(:stage2) { PipelineStage.create!(account: account, name: 'In Progress', position: 2) }
  let(:stage_qualified) { PipelineStage.create!(account: account, name: 'Qualified', position: 3) }
  let(:stage_unqualified) { PipelineStage.create!(account: account, name: 'Unqualified', position: 4) }

  let(:attr_budget) do
    CustomAttributeDefinition.create!(
      account: account,
      attribute_key: 'budget',
      attribute_display_name: 'Budget',
      attribute_display_type: 'currency',
      attribute_model: 'opportunity_attribute'
    )
  end

  let(:attr_timeline) do
    CustomAttributeDefinition.create!(
      account: account,
      attribute_key: 'timeline',
      attribute_display_name: 'Timeline',
      attribute_display_type: 'text',
      attribute_model: 'opportunity_attribute'
    )
  end

  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Sales Scout',
      default_pipeline_stage: stage1,
      qualified_stage: stage_qualified,
      unqualified_stage: stage_unqualified,
      handover_team: team,
      enabled: true
    )
  end

  let(:opportunity) do
    Opportunity.create!(
      account: account,
      contact: conversation.contact,
      origin_conversation: conversation,
      pipeline_stage: stage1,
      title: 'Deal #1',
      status: :open
    )
  end

  let(:service) do
    described_class.new(
      scout: scout,
      conversation: conversation,
      opportunity: opportunity
    )
  end

  describe '#call' do
    context 'when stage does not exist' do
      it 'returns pipeline stage not found message without modifying opportunity' do
        result = service.call(stage_id: 999_999)
        expect(result).to eq('Pipeline stage not found.')
        expect(opportunity.reload.pipeline_stage_id).to eq(stage1.id)
      end
    end

    context 'when transitioning to qualified stage (User Story 2 & 3)' do
      before do
        scout.required_custom_attribute_definitions << attr_budget
        scout.required_custom_attribute_definitions << attr_timeline
      end

      context 'when global qualification requirements are missing' do
        it 'rejects transition, returns missing attribute names, and does not flag handoff as needed' do
          result = service.call(stage_id: stage_qualified.id)
          expect(result).to include('Cannot move to the qualified stage')
          expect(result).to include('Budget')
          expect(result).to include('Timeline')
          expect(opportunity.reload.pipeline_stage_id).to eq(stage1.id)
          expect(service.handoff_needed).to be false
        end
      end

      context 'when global qualification requirements are satisfied' do
        before do
          opportunity.update!(custom_attributes: { 'budget' => 5000, 'timeline' => 'Immediate' })
        end

        it 'persists stage change and flags handoff as needed, without triggering it synchronously' do
          expect(Custom::Scout::HandoffService).not_to receive(:new)

          result = service.call(stage_id: stage_qualified.id)
          expect(result).to include('Opportunity moved to stage Qualified successfully.')
          expect(opportunity.reload.pipeline_stage_id).to eq(stage_qualified.id)
          expect(service.handoff_needed).to be true
        end

        it 'does not flag handoff as needed on subsequent redundant stage-move calls' do
          opportunity.update!(pipeline_stage: stage_qualified)

          result = service.call(stage_id: stage_qualified.id)
          expect(result).to include('Opportunity moved to stage Qualified successfully.')
          expect(service.handoff_needed).to be false
        end
      end
    end

    context 'when moving forward with stage-specific required fields (User Story 4)' do
      before do
        PipelineStageRequiredField.create!(
          pipeline_stage: stage2,
          custom_attribute_definition: attr_timeline
        )
      end

      context 'when stage required field is missing' do
        it 'returns descriptive missing fields error without raising exception' do
          result = service.call(stage_id: stage2.id)
          expect(result).to include('Cannot move to stage In Progress')
          expect(result).to include('Timeline')
          expect(opportunity.reload.pipeline_stage_id).to eq(stage1.id)
        end
      end

      context 'when stage requires deal value and value is nil' do
        before do
          stage2.update!(requires_deal_value: true)
          opportunity.update!(custom_attributes: { 'timeline' => 'Q3' })
        end

        it 'returns descriptive error naming Deal Value' do
          result = service.call(stage_id: stage2.id)
          expect(result).to include('Cannot move to stage In Progress')
          expect(result).to include('Deal Value')
          expect(opportunity.reload.pipeline_stage_id).to eq(stage1.id)
        end
      end

      context 'when stage required fields are satisfied' do
        before do
          opportunity.update!(custom_attributes: { 'timeline' => 'Q3' })
        end

        it 'moves opportunity successfully' do
          result = service.call(stage_id: stage2.id)
          expect(result).to include('Opportunity moved to stage In Progress successfully.')
          expect(opportunity.reload.pipeline_stage_id).to eq(stage2.id)
        end
      end
    end

    context 'when moving backward or laterally (FR-012)' do
      before do
        PipelineStageRequiredField.create!(
          pipeline_stage: stage1,
          custom_attribute_definition: attr_timeline
        )
        opportunity.update!(pipeline_stage: stage2)
      end

      it 'allows backward move without enforcing target stage requirements' do
        result = service.call(stage_id: stage1.id)
        expect(result).to include('Opportunity moved to stage Triage successfully.')
        expect(opportunity.reload.pipeline_stage_id).to eq(stage1.id)
      end
    end

    context 'when moving to unqualified stage (User Story 5)' do
      it 'moves stage to unqualified, leaves status open, and does not flag handoff as needed' do
        result = service.call(stage_id: stage_unqualified.id)
        expect(result).to include('Opportunity moved to stage Unqualified successfully.')
        expect(opportunity.reload.pipeline_stage_id).to eq(stage_unqualified.id)
        expect(opportunity.status).to eq('open')
        expect(service.handoff_needed).to be false
      end
    end
  end
end
