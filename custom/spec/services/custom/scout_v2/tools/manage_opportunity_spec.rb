# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Tools::ManageOpportunity do
  subject(:tool) { described_class.new(scout, conversation, playground: false) }

  let(:account) { create(:account) }
  let(:lead_stage) { PipelineStage.create!(account: account, name: 'Lead', position: 0) }
  let(:qualified_stage) { PipelineStage.create!(account: account, name: 'Qualificado', position: 1) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Qualifier',
      default_pipeline_stage: lead_stage,
      qualified_stage: qualified_stage
    )
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:opportunity) do
    Opportunity.create!(
      account: account,
      active_conversation: conversation,
      origin_conversation: conversation,
      contact: contact,
      title: 'Negócio Teste',
      pipeline_stage: lead_stage
    )
  end

  before do
    account.enable_features!('scout', 'scout_v2', 'opportunities')
    CustomAttributeDefinition.create!(
      account: account,
      attribute_key: 'orcamento',
      attribute_display_name: 'Orçamento',
      attribute_model: 'opportunity_attribute',
      attribute_display_type: 'number'
    )
  end

  describe 'parameters' do
    it 'does not declare stage_id parameter' do
      expect(described_class.parameters.keys).not_to include(:stage_id)
      expect(described_class.parameters.keys).to include(:action, :title, :estimated_value, :custom_attributes, :opportunity_id)
    end
  end

  describe '#execute' do
    context 'when stage_id is passed' do
      it 'returns error and leaves opportunity stage unchanged' do
        result = tool.execute(
          action: 'update',
          opportunity_id: opportunity.id,
          stage_id: qualified_stage.id
        )

        expect(result).to eq(
          error: 'stage_id não é aceito: a mudança de estágio acontece apenas pelos exits da playbook.'
        )
        expect(opportunity.reload.pipeline_stage_id).to eq(lead_stage.id)
      end
    end

    context 'when updating an already-qualified opportunity' do
      before do
        opportunity.update!(pipeline_stage: qualified_stage)
      end

      it 'keeps the requalification private note and returns result without closing instructions' do
        result = tool.execute(
          action: 'update',
          opportunity_id: opportunity.id,
          custom_attributes: { 'orcamento' => '5000' }
        )

        expect(result).to be_a(String)
        expect(result).to include("Opportunity updated successfully (ID: #{opportunity.id}).")
        expect(result).not_to include('sem perguntas')
        expect(result).not_to include('encerramento')

        note = conversation.messages.where(private: true).last
        expect(note).to be_present
        expect(note.content).to include('já estava no estágio "Qualificado"')
      end
    end
  end
end
