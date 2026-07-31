require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::PipelineStages', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers_admin) { admin.create_new_auth_token.merge('Content-Type' => 'application/json') }
  let(:headers_agent) { agent.create_new_auth_token.merge('Content-Type' => 'application/json') }

  before do
    account.enable_features!('opportunities')
  end

  describe 'GET /api/v1/accounts/{account.id}/pipeline_stages' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/pipeline_stages"
        puts response.body if response.status == 500
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as agent' do
      it 'returns unauthorized (pundit)' do
        get "/api/v1/accounts/#{account.id}/pipeline_stages", headers: headers_agent
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as admin' do
      it 'lazy seeds default stages on first call and is idempotent' do
        expect(account.pipeline_stages.count).to eq(0)

        get "/api/v1/accounts/#{account.id}/pipeline_stages", headers: headers_admin
        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response.length).to eq(2)
        expect(json_response.map { |s| s['name'] }).to contain_exactly('Leads Recebidos', 'Em Contato')

        # Second call
        get "/api/v1/accounts/#{account.id}/pipeline_stages", headers: headers_admin
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body).length).to eq(2)
      end
    end

    context 'when feature flag is disabled' do
      it 'returns forbidden' do
        account.disable_features!('opportunities')
        get "/api/v1/accounts/#{account.id}/pipeline_stages", headers: headers_admin
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/pipeline_stages' do
    let(:valid_params) { { pipeline_stage: { name: 'New Stage' } }.to_json }

    it 'creates a new pipeline stage and auto-assigns position' do
      account.pipeline_stages.create!(name: 'Stage 1', position: 1)

      post "/api/v1/accounts/#{account.id}/pipeline_stages", headers: headers_admin, params: valid_params
      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response['name']).to eq('New Stage')
      expect(json_response['position']).to eq(2)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/pipeline_stages/{id}' do
    let!(:stage) { account.pipeline_stages.create!(name: 'Stage 1') }
    let(:valid_params) { { pipeline_stage: { name: 'Updated Stage' } }.to_json }

    it 'updates the pipeline stage' do
      patch "/api/v1/accounts/#{account.id}/pipeline_stages/#{stage.id}", headers: headers_admin, params: valid_params
      expect(response).to have_http_status(:ok)

      json_response = JSON.parse(response.body)
      expect(json_response['name']).to eq('Updated Stage')
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/pipeline_stages/{id}' do
    let!(:stage) { account.pipeline_stages.create!(name: 'Stage 1') }

    it 'deletes the pipeline stage' do
      delete "/api/v1/accounts/#{account.id}/pipeline_stages/#{stage.id}", headers: headers_admin
      expect(response).to have_http_status(:ok)
      expect(PipelineStage.exists?(stage.id)).to be_falsey
    end

    it 'cannot delete if it has opportunities' do
      contact = create(:contact, account: account)
      Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'Opp 1')

      delete "/api/v1/accounts/#{account.id}/pipeline_stages/#{stage.id}", headers: headers_admin
      expect(response).to have_http_status(:unprocessable_entity)
      expect(PipelineStage.exists?(stage.id)).to be_truthy
    end
  end
end
