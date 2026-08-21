# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::Tools::ManageOpportunity do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:stage) { PipelineStage.create!(account: account, name: 'Triage') }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Test Scout',
      default_pipeline_stage: stage,
      enabled: true
    )
  end
  let(:tool) { described_class.new(scout, conversation) }

  describe '#execute' do
    context 'when creating opportunity with referral ad message' do
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

      it 'creates opportunity and populates referral attribution' do
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
      end
    end

    context 'when updating existing opportunity' do
      let!(:opportunity) do
        Opportunity.create!(
          account: account,
          contact: contact,
          origin_conversation: conversation,
          pipeline_stage: stage,
          title: 'Opp Existente',
          campaign_platform: 'facebook',
          campaign_headline: 'Headline Original'
        )
      end

      it 'updates fields without modifying existing campaign attribution' do
        result = tool.execute(action: 'update', title: 'Opp Atualizada', estimated_value: 8000.0)
        expect(result).to include('successfully')

        opportunity.reload
        aggregate_failures 'updated fields' do
          expect(opportunity.title).to eq('Opp Atualizada')
          expect(opportunity.value).to eq(8000.0)
          expect(opportunity.campaign_platform).to eq('facebook')
          expect(opportunity.campaign_headline).to eq('Headline Original')
        end
      end
    end
  end
end
