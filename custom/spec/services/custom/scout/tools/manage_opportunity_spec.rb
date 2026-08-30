# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::Tools::ManageOpportunity do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:stage1) { PipelineStage.create!(account: account, name: 'Triage', position: 1) }
  let(:stage2) { PipelineStage.create!(account: account, name: 'Negotiation', position: 2) }

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
      enabled: true
    )
  end
  let(:tool) { described_class.new(scout, conversation) }

  describe '#execute' do
    context 'when creating opportunity for contact with zero open deals (US3)' do
      let(:referral_data) do
        {
          'source_url' => 'https://facebook.com/ads/123?ad_id=987654321',
          'headline' => 'Promoção Especial',
          'body' => 'Texto do anúncio',
          'thumbnail_url' => 'https://example.com/thumb.png',
          'source_type' => 'ad'
        }
      end

      before do
        conversation.messages.create!(
          account: account,
          inbox: inbox,
          sender: contact,
          message_type: :incoming,
          content: 'Quero saber mais',
          content_attributes: { referral: referral_data }
        )
      end

      it 'creates opportunity and populates referral attribution without private notes' do
        expect do
          result = tool.execute(action: 'create', title: 'Opp de Anúncio', estimated_value: 5000.0)
          expect(result).to include('successfully')
        end.to change(Opportunity, :count).by(1)

        opp = Opportunity.find_by(origin_conversation_id: conversation.id)
        aggregate_failures 'opportunity attributes' do
          expect(opp.title).to eq('Opp de Anúncio')
          expect(opp.value).to eq(5000.0)
          expect(opp.campaign_platform).to eq('facebook')
          expect(opp.campaign_source_id).to eq('987654321')
          expect(opp.campaign_headline).to eq('Promoção Especial')
          expect(opp.campaign_thumbnail_url).to eq('https://example.com/thumb.png')
        end

        expect(conversation.messages.where(private: true)).to be_empty
      end

      context 'when custom_attributes arrives malformed from the model' do
        it 'parses a JSON-encoded String into a Hash instead of dropping it (observed OpenAI function-calling behavior)' do
          attr_budget
          result = tool.execute(action: 'create', title: 'Lead JSON String', custom_attributes: '{"budget":5000}')
          expect(result).to include('successfully')

          opp = Opportunity.find_by(origin_conversation_id: conversation.id)
          expect(opp.custom_attributes).to eq('budget' => 5000)
        end

        it 'ignores a String value that is not valid JSON instead of raising or corrupting the jsonb column' do
          result = tool.execute(action: 'create', title: 'Lead Malformado', custom_attributes: '{not valid json')
          expect(result).to include('successfully')

          opp = Opportunity.find_by(origin_conversation_id: conversation.id)
          expect(opp.custom_attributes).to eq({})
        end

        it 'strips keys that are not real custom attribute definitions (e.g. a char-indexed hash)' do
          attr_budget
          garbled = { '0' => '{', '1' => '"', 'budget' => 4000 }
          result = tool.execute(action: 'create', title: 'Lead Malformado', custom_attributes: garbled)
          expect(result).to include('successfully')

          opp = Opportunity.find_by(origin_conversation_id: conversation.id)
          expect(opp.custom_attributes).to eq('budget' => 4000)
        end
      end

      context 'when creating directly with a stage_id targeting the scout qualified stage' do
        let(:stage_qualified) { PipelineStage.create!(account: account, name: 'Qualified', position: 2) }

        before { scout.update!(qualified_stage: stage_qualified) }

        it 'flags handoff_needed instead of bypassing the qualification gate' do
          expect(Custom::Scout::HandoffService).not_to receive(:new)

          result = tool.execute(action: 'create', title: 'Lead Quente', stage_id: stage_qualified.id)

          expect(result).to include('successfully')
          expect(tool.handoff_needed).to be true
          opp = Opportunity.find_by(origin_conversation_id: conversation.id)
          expect(opp.pipeline_stage_id).to eq(stage_qualified.id)
        end

        it 'rejects the direct qualified-stage placement when required fields are missing' do
          scout.required_custom_attribute_definitions << attr_budget

          result = tool.execute(action: 'create', title: 'Lead Quente', stage_id: stage_qualified.id)

          expect(result).to include('Cannot move to the qualified stage')
          expect(tool.handoff_needed).to be false
          opp = Opportunity.find_by(origin_conversation_id: conversation.id)
          expect(opp.pipeline_stage_id).to eq(stage1.id)
        end
      end
    end

    context 'when continuing an existing open deal with declared opportunity_id (US1)' do
      let(:past_conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
      let(:attr_timeline) do
        CustomAttributeDefinition.create!(
          account: account,
          attribute_key: 'timeline',
          attribute_display_name: 'Timeline',
          attribute_display_type: 'text',
          attribute_model: 'opportunity_attribute'
        )
      end
      let!(:existing_opportunity) do
        Opportunity.create!(
          account: account,
          contact: contact,
          origin_conversation: past_conversation,
          pipeline_stage: stage1,
          status: :open,
          title: 'Negócio Anterior',
          value: 3000.0,
          campaign_platform: 'facebook',
          campaign_headline: 'Headline Original'
        )
      end

      it 'updates existing opportunity in place and does not create duplicate' do
        expect do
          result = tool.execute(
            action: 'create',
            opportunity_id: existing_opportunity.id,
            title: 'Negócio Atualizado',
            estimated_value: 8000.0
          )
          expect(result).to include('successfully')
        end.not_to change(Opportunity, :count)

        existing_opportunity.reload
        aggregate_failures 'updated fields' do
          expect(existing_opportunity.title).to eq('Negócio Atualizado')
          expect(existing_opportunity.value).to eq(8000.0)
          expect(existing_opportunity.campaign_platform).to eq('facebook')
          expect(existing_opportunity.campaign_headline).to eq('Headline Original')
          expect(existing_opportunity.pipeline_stage_id).to eq(stage1.id)
        end
      end

      it 'delegates stage transition to OpportunityStageTransitionService when stage_id is present' do
        result = tool.execute(
          action: 'update',
          opportunity_id: existing_opportunity.id,
          stage_id: stage2.id,
          estimated_value: 10_000.0
        )
        expect(result).to include('successfully')

        existing_opportunity.reload
        expect(existing_opportunity.value).to eq(10_000.0)
        expect(existing_opportunity.pipeline_stage_id).to eq(stage2.id)
      end

      it 'returns descriptive failure message without crashing when stage required field is missing' do
        stage2.required_custom_attribute_definitions << attr_budget

        result = tool.execute(action: 'update', opportunity_id: existing_opportunity.id, stage_id: stage2.id)
        expect(result).to include('Cannot move to stage Negotiation')
        expect(result).to include('Budget')
        expect(existing_opportunity.reload.pipeline_stage_id).to eq(stage1.id)
      end

      it 'persists title, value and custom_attributes even when the stage transition is rejected' do
        stage2.required_custom_attribute_definitions << attr_budget
        attr_timeline

        result = tool.execute(
          action: 'update',
          opportunity_id: existing_opportunity.id,
          stage_id: stage2.id,
          title: 'Negócio Atualizado',
          estimated_value: 9000.0,
          custom_attributes: { 'timeline' => 'Q4' }
        )
        expect(result).to include('Cannot move to stage Negotiation')

        existing_opportunity.reload
        expect(existing_opportunity.title).to eq('Negócio Atualizado')
        expect(existing_opportunity.value).to eq(9000.0)
        expect(existing_opportunity.custom_attributes).to include('timeline' => 'Q4')
        expect(existing_opportunity.pipeline_stage_id).to eq(stage1.id)
      end

      context 'when the target stage is the scout qualified stage' do
        let(:stage_qualified) { PipelineStage.create!(account: account, name: 'Qualified', position: 3) }

        before { scout.update!(qualified_stage: stage_qualified) }

        it 'flags handoff_needed on the tool instance without triggering it synchronously' do
          expect(Custom::Scout::HandoffService).not_to receive(:new)

          result = tool.execute(action: 'update', opportunity_id: existing_opportunity.id, stage_id: stage_qualified.id)

          expect(result).to include('successfully')
          expect(tool.handoff_needed).to be true
        end

        it 'resets handoff_needed to false on a fresh call that does not qualify' do
          tool.execute(action: 'update', opportunity_id: existing_opportunity.id, stage_id: stage_qualified.id)
          expect(tool.handoff_needed).to be true

          tool.execute(action: 'update', opportunity_id: existing_opportunity.id, title: 'Só um ajuste de título')
          expect(tool.handoff_needed).to be false
        end
      end
    end

    context 'when continuity is ambiguous (US2)' do
      let!(:opp1) do
        Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: stage1,
          status: :open,
          title: 'Plano 1'
        )
      end
      let!(:opp2) do
        Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: stage1,
          status: :open,
          title: 'Plano 2'
        )
      end
      let(:other_contact) { create(:contact, account: account) }
      let!(:other_opp) do
        Opportunity.create!(
          account: account,
          contact: other_contact,
          pipeline_stage: stage1,
          status: :open,
          title: 'Outro Contato'
        )
      end

      it 'does not create or modify deals when contact has multiple open deals and no opportunity_id is passed' do
        expect do
          result = tool.execute(action: 'create', title: 'Nova Tentativa')
          expect(result).to include('deferred')
        end.not_to change(Opportunity, :count)

        expect(opp1.reload.title).to eq('Plano 1')
        expect(opp2.reload.title).to eq('Plano 2')

        private_note = conversation.messages.where(private: true).last
        expect(private_note).to be_present
        expect(private_note.content).to include('⚠️ [Continuidade de Oportunidade]')
        expect(private_note.content).to include('2 open opportunity candidate(s)')
      end

      it 'rejects and flags declared opportunity_id belonging to another contact' do
        expect do
          result = tool.execute(action: 'create', opportunity_id: other_opp.id, title: 'Tentativa Inválida')
          expect(result).to include('deferred')
        end.not_to change(Opportunity, :count)

        private_note = conversation.messages.where(private: true).last
        expect(private_note).to be_present
        expect(private_note.content).to include('⚠️ [Continuidade de Oportunidade]')
        expect(private_note.content).to include(other_opp.id.to_s)
      end

      it 'rejects and flags non-existent declared opportunity_id' do
        expect do
          result = tool.execute(action: 'update', opportunity_id: 999_999)
          expect(result).to include('deferred')
        end.not_to change(Opportunity, :count)

        private_note = conversation.messages.where(private: true).last
        expect(private_note).to be_present
        expect(private_note.content).to include('⚠️ [Continuidade de Oportunidade]')
      end
    end
  end
end
