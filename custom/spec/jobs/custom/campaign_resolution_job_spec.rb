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
                                                                                            'campaign' => { 'id' => '789', 'name' => 'Summer Sale' },
                                                                                            'creative' => { 'thumbnail_url' => 'https://fbcdn.net/thumb.jpg' }
                                                                                          })

        described_class.perform_now(opportunity.id)

        opportunity.reload
        expect(opportunity.campaign_name).to eq('Summer Sale')
        expect(opportunity.campaign_adset_name).to eq('Audience A')
        expect(opportunity.campaign_ad_name).to eq('Ad 1')
        expect(opportunity.campaign_thumbnail_url).to eq('https://fbcdn.net/thumb.jpg')
        expect(opportunity.campaign_resolution_status).to eq('resolved')
      end
    end

    context 'when token is revoked (Meta::AuthenticationError)' do
      it 'updates status to failed and disconnects setting' do
        allow(graph_client_instance).to receive(:fetch_ad_details).with('123').and_raise(
          Meta::AuthenticationError.new('Session expired', code: 190, error_subcode: 463)
        )

        described_class.perform_now(opportunity.id)

        opportunity.reload
        expect(opportunity.campaign_resolution_status).to eq('failed')

        setting.reload
        expect(setting.enabled).to be(false)
        expect(setting.provider_config['access_token']).to be_nil
      end
    end

    context 'when node is not found or unsupported get on organic post (Meta::NodeNotFoundError)' do
      it 'updates status to failed and keeps setting enabled' do
        allow(graph_client_instance).to receive(:fetch_ad_details).with('123').and_raise(
          Meta::NodeNotFoundError.new('Node not found', code: 100)
        )

        described_class.perform_now(opportunity.id)

        opportunity.reload
        expect(opportunity.campaign_resolution_status).to eq('failed')

        setting.reload
        expect(setting.enabled).to be(true)
        expect(setting.provider_config['access_token']).to eq('test_token')
      end
    end

    context 'when resolution is rate limited via Meta::RateLimitError' do
      it 'retries the job and leaves setting enabled' do
        allow(graph_client_instance).to receive(:fetch_ad_details).with('123').and_raise(
          Meta::RateLimitError.new('Rate limit reached', code: 17)
        )

        expect do
          described_class.perform_now(opportunity.id)
        end.to have_enqueued_job(described_class).with(opportunity.id)

        setting.reload
        expect(setting.enabled).to be(true)
      end
    end

    context 'when resolution is rate limited via internal limiter' do
      it 'retries the job' do
        limiter = instance_double(Meta::RateLimiter, within_limit?: false)
        allow(Meta::RateLimiter).to receive(:new).with(account).and_return(limiter)

        expect do
          described_class.perform_now(opportunity.id)
        end.to have_enqueued_job(described_class).with(opportunity.id)
      end
    end
  end
end
