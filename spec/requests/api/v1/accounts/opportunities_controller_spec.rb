require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Opportunities', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:stage) { account.pipeline_stages.create!(name: 'Test Stage') }
  let(:contact) { create(:contact, account: account) }

  before do
    # enable the opportunities feature
    account.enable_features!('opportunities')
  end

  describe 'GET /api/v1/accounts/{account.id}/opportunities' do
    it 'returns opportunities' do
      Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'My Opp')

      get "/api/v1/accounts/#{account.id}/opportunities",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).length).to eq(1)
      expect(JSON.parse(response.body).first['title']).to eq('My Opp')
    end

    it 'works for agents too' do
      get "/api/v1/accounts/#{account.id}/opportunities",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/opportunities' do
    it 'creates an opportunity' do
      post "/api/v1/accounts/#{account.id}/opportunities",
           headers: agent.create_new_auth_token,
           params: {
             opportunity: {
               title: 'New Opp',
               contact_id: contact.id,
               pipeline_stage_id: stage.id,
               status: 'open'
             }
           },
           as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['title']).to eq('New Opp')
      expect(json['status']).to eq('open')
    end

    it 'rejects cross-account pipeline_stage_id' do
      other_account = create(:account)
      other_stage = other_account.pipeline_stages.create!(name: 'Other Stage')

      post "/api/v1/accounts/#{account.id}/opportunities",
           headers: admin.create_new_auth_token,
           params: {
             opportunity: {
               title: 'New Opp',
               contact_id: contact.id,
               pipeline_stage_id: other_stage.id
             }
           },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['error']).to include('Pipeline stage must belong to the same account')
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/opportunities/{id}' do
    it 'updates the opportunity' do
      opp = Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, assignee: agent, title: 'My Opp')

      patch "/api/v1/accounts/#{account.id}/opportunities/#{opp.id}",
            headers: agent.create_new_auth_token,
            params: { opportunity: { status: 'won' } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(opp.reload.status).to eq('won')
    end

    it 'rejects attempt to change origin_conversation_id' do
      conversation = create(:conversation, account: account)
      opp = Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, assignee: agent, title: 'My Opp',
                                origin_conversation_id: conversation.id)

      patch "/api/v1/accounts/#{account.id}/opportunities/#{opp.id}",
            headers: agent.create_new_auth_token,
            params: { opportunity: { title: 'Updated Title', origin_conversation_id: nil } },
            as: :json

      expect(response).to have_http_status(:ok)
      expect(opp.reload.title).to eq('Updated Title')
      expect(opp.reload.origin_conversation_id).to eq(conversation.id)
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/opportunities/{id}' do
    it 'deletes the opportunity' do
      opp = Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'My Opp')

      delete "/api/v1/accounts/#{account.id}/opportunities/#{opp.id}",
             headers: admin.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:ok)
      expect(Opportunity.exists?(opp.id)).to be(false)
    end
  end
end
