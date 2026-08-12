require 'rails_helper'

RSpec.describe Custom::CampaignResolutionJob, type: :job do
  include ActiveJob::TestHelper

  let!(:account) { create(:account) }
  let!(:contact) { create(:contact, account: account) }
  let!(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:opportunity) do
    Opportunity.create!(
      account: account,
      contact: contact,
      origin_conversation: conversation,
      status: :open,
      title: 'Test Opportunity',
      campaign_platform: 'facebook',
      campaign_source_id: '123',
      campaign_resolution_status: 'pending'
    )
  end
  let!(:setting) { create(:campaign_attribution_setting, account: account, enabled: true) }

  describe '#perform' do
    let(:graph_client_instance) { instance_double(Meta::GraphApiClient) }

    before do
      allow(Meta::GraphApiClient).to receive(:new).and_return(graph_client_instance)
    end

    context 'when resolution is successful (cache miss)' do
      it 'updates the opportunity and transitions status to resolved' do
        allow(graph_client_instance).to receive(:resolve_ad_id).with('123').and_return({
                                                                                         campaign_name: 'Summer Sale',
                                                                                         adset_name: 'Audience A',
                                                                                         ad_name: 'Ad 1',
                                                                                         platform: 'facebook'
                                                                                       })

        described_class.perform_now(opportunity.id)

        opportunity.reload
        expect(opportunity.campaign_name).to eq('Summer Sale')
        expect(opportunity.campaign_adset_name).to eq('Audience A')
        expect(opportunity.campaign_ad_name).to eq('Ad 1')
        expect(opportunity.campaign_resolution_status).to eq('resolved')
      end
    end

    context 'when resolution fails (OAuth error)' do
      it 'updates status to failed and disconnects setting' do
        allow(graph_client_instance).to receive(:resolve_ad_id).with('123').and_raise(Meta::GraphApiClient::OAuthError.new('Token expired'))

        described_class.perform_now(opportunity.id)

        opportunity.reload
        expect(opportunity.campaign_resolution_status).to eq('failed')

        setting.reload
        expect(setting.provider_config).to be_nil
      end
    end

    context 'when resolution is rate limited' do
      it 'raises RateLimitError to be retried' do
        allow(graph_client_instance).to receive(:resolve_ad_id).with('123').and_raise(Meta::RateLimitError.new('Too many requests'))

        expect do
          described_class.perform_now(opportunity.id)
        end.to raise_error(Meta::RateLimitError)
      end
    end
  end
end
