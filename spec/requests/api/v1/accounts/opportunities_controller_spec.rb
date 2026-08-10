require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Opportunities', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:stage) { account.pipeline_stages.create!(name: 'Test Stage') }
  let(:contact) { create(:contact, account: account) }

  if ChatwootApp.enterprise?
    let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_manage']) }
    let(:custom_role_user) do
      user = create(:user, account: account, role: :agent)
      user.account_users.find_by(account_id: account.id).update!(custom_role: custom_role)
      user
    end
  end

  before do
    # enable the opportunities feature
    account.enable_features!('opportunities')
  end

  describe 'GET /api/v1/accounts/{account.id}/opportunities' do
    it 'returns open opportunities by default, excluding won/lost' do
      Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'Open Opp', status: 'open')
      Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'Won Opp', status: 'won')
      Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'Lost Opp', status: 'lost')

      get "/api/v1/accounts/#{account.id}/opportunities",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.length).to eq(1)
      expect(response.parsed_body.first['title']).to eq('Open Opp')
    end

    it 'returns all opportunities when status=all' do
      Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'Open Opp', status: 'open')
      Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'Won Opp', status: 'won')

      get "/api/v1/accounts/#{account.id}/opportunities",
          params: { status: 'all' },
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.length).to eq(2)
      expect(response.parsed_body.map { |o| o['title'] }).to include('Open Opp', 'Won Opp')
    end

    it 'returns specific status opportunities when explicitly requested' do
      Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'Open Opp', status: 'open')
      Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'Won Opp', status: 'won')

      get "/api/v1/accounts/#{account.id}/opportunities",
          params: { status: 'won' },
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.length).to eq(1)
      expect(response.parsed_body.first['title']).to eq('Won Opp')
    end

    it 'ignores the default when payload targets status' do
      Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'Won Opp', status: 'won')
      Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'Lost Opp', status: 'lost')

      payload = [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['lost'] }].to_json
      get "/api/v1/accounts/#{account.id}/opportunities",
          params: { payload: payload },
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.length).to eq(1)
      expect(response.parsed_body.first['title']).to eq('Lost Opp')
    end

    it 'works for agents too' do
      get "/api/v1/accounts/#{account.id}/opportunities",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
    end

    if ChatwootApp.enterprise?
      it 'works for custom_role sessions too' do
        get "/api/v1/accounts/#{account.id}/opportunities",
            headers: custom_role_user.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
      end
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
      json = response.parsed_body
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
      expect(response.parsed_body['error']).to include('Pipeline stage must belong to the same account')
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
