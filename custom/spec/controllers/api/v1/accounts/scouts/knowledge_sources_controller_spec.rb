# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Scouts::KnowledgeSources', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Test Scout',
      enabled: true
    )
  end

  describe 'POST /api/v1/accounts/{account.id}/scouts/{scout.id}/knowledge_sources' do
    it 'creates a URL knowledge source when nested inside knowledge_source key' do
      post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/knowledge_sources",
           params: {
             knowledge_source: {
               kind: 'url',
               url: 'https://www.example.com'
             }
           },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json['kind']).to eq('url')
      expect(json['url']).to eq('https://www.example.com')
      expect(json['status']).to eq('pending')
    end

    it 'creates a FAQ knowledge source when nested inside knowledge_source key' do
      post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/knowledge_sources",
           params: {
             knowledge_source: {
               kind: 'faq',
               question: 'What is the price?',
               answer: '$10 per month'
             }
           },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json['kind']).to eq('faq')
      expect(json['question']).to eq('What is the price?')
      expect(json['answer']).to eq('$10 per month')
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/scouts/{scout.id}/knowledge_sources' do
    it 'returns list of knowledge sources for the scout' do
      scout.scout_knowledge_sources.create!(
        account: account,
        kind: :faq,
        question: 'Q1?',
        answer: 'A1.'
      )

      get "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/knowledge_sources",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json.size).to eq(1)
      expect(json.first['question']).to eq('Q1?')
      expect(json.first['embeddings_count']).to eq(0)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/scouts/{scout.id}/knowledge_sources/{source.id}' do
    it 'reprocesses knowledge source when reprocess param is passed' do
      source = scout.scout_knowledge_sources.create!(
        account: account,
        kind: :url,
        url: 'https://www.example.com',
        status: :ready
      )
      source.scout_knowledge_embeddings.create!(question: 'Q?', answer: 'A.')

      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/knowledge_sources/#{source.id}",
            params: { reprocess: true },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['status']).to eq('pending')
      expect(source.reload.status).to eq('pending')
      expect(source.scout_knowledge_embeddings.count).to eq(0)
    end
  end
end
