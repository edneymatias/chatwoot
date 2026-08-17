# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Opportunities::Activities', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:stage) { PipelineStage.create!(account: account, name: 'Stage 1') }
  let(:contact) { create(:contact, account: account) }
  let(:opportunity) { Opportunity.create!(account: account, title: 'Opportunity 1', pipeline_stage: stage, contact: contact) }

  before do
    account.enable_features!('opportunities')
  end

  describe 'GET /api/v1/accounts/{account.id}/opportunities/{opportunity.id}/activities' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get api_v1_account_opportunity_activities_url(account_id: account.id, opportunity_id: opportunity.id), as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      it 'returns the list of activities ordered by occurred_at descending' do
        act1 = opportunity.activities.create!(
          account: account,
          event_type: 'opportunity_created',
          actor: user,
          metadata: {},
          occurred_at: 2.hours.ago
        )
        act2 = opportunity.activities.create!(
          account: account,
          event_type: 'opportunity_stage_changed',
          actor: user,
          metadata: { 'from_stage_id' => stage.id, 'to_stage_id' => stage.id },
          occurred_at: 1.hour.ago
        )

        get api_v1_account_opportunity_activities_url(account_id: account.id, opportunity_id: opportunity.id),
            headers: user.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json.size).to eq(2)
        expect(json.first['id']).to eq(act2.id)
        expect(json.second['id']).to eq(act1.id)
        expect(json.first['event_type']).to eq('opportunity_stage_changed')
        expect(json.first['actor']['name']).to eq(user.name)
      end
    end
  end
end
