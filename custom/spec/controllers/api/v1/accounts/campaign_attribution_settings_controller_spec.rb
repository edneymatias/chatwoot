require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::CampaignAttributionSettings', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:stage) { PipelineStage.create!(account: account, name: 'Lead', position: 1) }

  describe 'GET /api/v1/accounts/{account.id}/campaign_attribution_setting' do
    let!(:contact) { create(:contact, account: account) }
    let!(:setting) { CampaignAttributionSetting.create!(account: account, enabled: true, provider_config: { 'access_token' => 'token_123' }) }

    before do
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: stage,
        status: :open,
        title: 'Pending Op',
        campaign_source_id: '123',
        campaign_resolution_status: 'pending'
      )
    end

    it 'returns the setting data with pending_count' do
      get "/api/v1/accounts/#{account.id}/campaign_attribution_setting",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      data = JSON.parse(response.body)
      expect(data['enabled']).to be(true)
      expect(data['connected']).to be(true)
      expect(data['pending_count']).to eq(1)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/campaign_attribution_setting/reprocess_pending' do
    let!(:contact) { create(:contact, account: account) }
    let!(:setting) { CampaignAttributionSetting.create!(account: account, enabled: true, provider_config: { 'access_token' => 'token_123' }) }

    context 'when setting is connected and enabled with pending opportunities' do
      before do
        Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: stage,
          status: :open,
          title: 'Pending Op 1',
          campaign_source_id: '123',
          campaign_resolution_status: 'pending'
        )
      end

      it 'enqueues DrainPendingAttributionsJob and returns success' do
        expect do
          post "/api/v1/accounts/#{account.id}/campaign_attribution_setting/reprocess_pending",
               headers: admin.create_new_auth_token
        end.to have_enqueued_job(Meta::DrainPendingAttributionsJob).with(account.id)

        expect(response).to have_http_status(:success)
        data = JSON.parse(response.body)
        expect(data['count']).to eq(1)
      end
    end

    context 'when setting is not connected' do
      before do
        setting.update!(provider_config: {})
      end

      it 'returns unprocessable_entity error' do
        post "/api/v1/accounts/#{account.id}/campaign_attribution_setting/reprocess_pending",
             headers: admin.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/campaign_attribution_setting' do
    let!(:setting) { CampaignAttributionSetting.create!(account: account, enabled: false, provider_config: { 'access_token' => 'token_123' }) }

    it 'enables setting and triggers DrainPendingAttributionsJob' do
      expect do
        patch "/api/v1/accounts/#{account.id}/campaign_attribution_setting",
              params: { enabled: true },
              headers: admin.create_new_auth_token
      end.to have_enqueued_job(Meta::DrainPendingAttributionsJob).with(account.id)

      expect(response).to have_http_status(:success)
      setting.reload
      expect(setting.enabled).to be(true)
    end
  end
end
