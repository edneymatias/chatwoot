# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::PipelineStageAggregates', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers_agent) { agent.create_new_auth_token.merge('Content-Type' => 'application/json') }

  let(:stage1) { PipelineStage.create!(account: account, name: 'Stage 1', position: 1) }
  let(:stage2) { PipelineStage.create!(account: account, name: 'Stage 2', position: 2) }
  let(:contact) { create(:contact, account: account, name: 'John Doe') }

  before do
    account.enable_features!('opportunities')
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: stage1,
      title: 'Deal Open 1',
      value: 1000,
      campaign_name: 'Summer Sale',
      status: :open
    )
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: stage1,
      title: 'Deal Open 2',
      value: 500,
      campaign_name: 'Winter Promo',
      status: :open
    )
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: stage1,
      title: 'Deal Won 1',
      value: 2000,
      campaign_name: 'Summer Sale',
      status: :won
    )
  end

  describe 'GET /api/v1/accounts/{account.id}/pipeline_stage_aggregates' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/pipeline_stage_aggregates", params: { stage_ids: [stage1.id] }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when stage_ids parameter is blank' do
      it 'returns unprocessable_entity with error message' do
        get "/api/v1/accounts/#{account.id}/pipeline_stage_aggregates", headers: headers_agent, params: {}
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq({ 'error' => 'stage_ids is required' })
      end
    end

    context 'with default parameters (no filter/status)' do
      it 'returns open-only aggregates with count and value_sum keys' do
        get "/api/v1/accounts/#{account.id}/pipeline_stage_aggregates",
            headers: headers_agent,
            params: { stage_ids: [stage1.id, stage2.id] }

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json).to eq([
                             { 'pipeline_stage_id' => stage1.id, 'count' => 2, 'value_sum' => 1500.0 },
                             { 'pipeline_stage_id' => stage2.id, 'count' => 0, 'value_sum' => 0.0 }
                           ])
      end
    end

    context 'with status parameter' do
      it 'returns won-only aggregates when status=won' do
        get "/api/v1/accounts/#{account.id}/pipeline_stage_aggregates",
            headers: headers_agent,
            params: { stage_ids: [stage1.id], status: 'won' }

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json).to eq([
                             { 'pipeline_stage_id' => stage1.id, 'count' => 1, 'value_sum' => 2000.0 }
                           ])
      end

      it 'returns all aggregates when status=all' do
        get "/api/v1/accounts/#{account.id}/pipeline_stage_aggregates",
            headers: headers_agent,
            params: { stage_ids: [stage1.id], status: 'all' }

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json).to eq([
                             { 'pipeline_stage_id' => stage1.id, 'count' => 3, 'value_sum' => 3500.0 }
                           ])
      end
    end

    context 'with search parameter (q)' do
      it 'scopes aggregates to matching search results' do
        get "/api/v1/accounts/#{account.id}/pipeline_stage_aggregates",
            headers: headers_agent,
            params: { stage_ids: [stage1.id], q: 'Summer' }

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        # opp_open_1 matches (opp_won_1 is won, and default status is open)
        expect(json).to eq([
                             { 'pipeline_stage_id' => stage1.id, 'count' => 1, 'value_sum' => 1000.0 }
                           ])
      end
    end

    context 'with payload filters' do
      it 'scopes aggregates according to advanced filter payload' do
        payload = [
          {
            'attribute_key' => 'campaign_name',
            'filter_operator' => 'contains',
            'values' => ['Winter']
          }
        ].to_json

        get "/api/v1/accounts/#{account.id}/pipeline_stage_aggregates",
            headers: headers_agent,
            params: { stage_ids: [stage1.id], payload: payload }

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json).to eq([
                             { 'pipeline_stage_id' => stage1.id, 'count' => 1, 'value_sum' => 500.0 }
                           ])
      end
    end
  end
end
