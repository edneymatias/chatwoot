require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::CampaignPerformanceReports', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let!(:stage) { account.pipeline_stages.create!(name: 'Lead', position: 1, campaign_report_milestone: true) }

  before do
    account.enable_features!('opportunities')
  end

  describe 'GET /api/v1/accounts/{account.id}/campaign_performance_reports' do
    context 'when it is an unauthenticated request' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/campaign_performance_reports"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user lacks report permissions' do
      it 'returns unauthorized for agent without report permissions' do
        get "/api/v1/accounts/#{account.id}/campaign_performance_reports",
            headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when user is authorized administrator' do
      before do
        Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: stage,
          title: 'Camp Opp',
          status: :won,
          campaign_source_id: 'src_10',
          campaign_resolution_status: 'resolved',
          campaign_name: 'Summer Sale',
          campaign_adset_name: 'AdSet 1',
          campaign_ad_name: 'Banner A',
          created_at: Time.current
        )
      end

      it 'returns summary metrics in report payload', :aggregate_failures do
        get "/api/v1/accounts/#{account.id}/campaign_performance_reports",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        data = response.parsed_body

        expect(data['summary']['leads']).to eq(1)
        expect(data['summary']['won_count']).to eq(1)
        expect(data['summary']['milestone_stage_name']).to eq('Lead')
        expect(data['summary']['milestone_count']).to eq(1)
        expect(data['summary']['distinct_campaigns']).to eq(1)
      end

      it 'returns breakdown entries in report payload', :aggregate_failures do
        get "/api/v1/accounts/#{account.id}/campaign_performance_reports",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        data = response.parsed_body

        expect(data['by_campaign'].first['campaign_name']).to eq('Summer Sale')
        expect(data['by_adset'].first['campaign_adset_name']).to eq('AdSet 1')
        expect(data['by_ad'].first['campaign_ad_name']).to eq('Banner A')
      end

      it 'filters by date range params since and until' do
        past_since = 10.days.ago.to_i
        past_until = 5.days.ago.to_i

        get "/api/v1/accounts/#{account.id}/campaign_performance_reports",
            headers: admin.create_new_auth_token,
            params: { since: past_since, until: past_until }

        expect(response).to have_http_status(:success)
        data = response.parsed_body
        expect(data['summary']['leads']).to eq(0)
      end
    end
  end
end
