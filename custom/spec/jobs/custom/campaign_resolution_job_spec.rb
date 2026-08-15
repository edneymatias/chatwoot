require 'rails_helper'

RSpec.describe Custom::CampaignResolutionJob, type: :job do
  include ActiveJob::TestHelper

  let!(:account) { create(:account) }
  let!(:contact) { create(:contact, account: account) }
  let!(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:stage) { PipelineStage.create!(account: account, name: 'Lead', position: 1) }
  let!(:opportunity) do
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: stage,
      origin_conversation: conversation,
      status: :open,
      title: 'Test Opportunity',
      campaign_platform: 'facebook',
      campaign_source_id: '123',
      campaign_resolution_status: 'pending'
    )
  end
  let!(:setting) { CampaignAttributionSetting.create!(account: account, enabled: true, provider_config: { 'access_token' => 'test_token' }) }

  describe '#perform' do
    let(:graph_client_instance) { instance_double(Meta::GraphApiClient) }

    before do
      Redis::Alfred.delete(Meta::CampaignResolutionCache.cache_key(opportunity.campaign_source_id))
      allow(Meta::GraphApiClient).to receive(:new).and_return(graph_client_instance)
    end

    context 'when resolution is successful (cache miss)' do
      it 'updates the opportunity and transitions status to resolved' do
        allow(graph_client_instance).to receive(:fetch_ad_details).with('123').and_return({
                                                                                            'id' => '123',
                                                                                            'name' => 'Ad 1',
                                                                                            'adset' => { 'id' => '456', 'name' => 'Audience A' },
                                                                                            'campaign' => { 'id' => '789', 'name' => 'Summer Sale' }
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
        allow(graph_client_instance).to receive(:fetch_ad_details).with('123').and_raise(StandardError, 'OAuthException')

        described_class.perform_now(opportunity.id)

        opportunity.reload
        expect(opportunity.campaign_resolution_status).to eq('failed')

        setting.reload
        expect(setting.enabled).to be(false)
        expect(setting.provider_config['access_token']).to be_nil
      end
    end

    context 'when resolution is rate limited' do
      it 'retries the job' do
        allow_any_instance_of(Meta::RateLimiter).to receive(:within_limit?).and_return(false)

        expect do
          described_class.perform_now(opportunity.id)
        end.to have_enqueued_job(described_class).with(opportunity.id)
      end
    end
  end
end
