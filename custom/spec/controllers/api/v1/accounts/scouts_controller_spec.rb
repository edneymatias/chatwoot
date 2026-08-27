# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Scouts', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:stage) { PipelineStage.create!(account: account, name: 'Qualified Stage') }
  let!(:attr1) { create(:custom_attribute_definition, account: account, attribute_model: 'opportunity_attribute') }
  let!(:attr2) { create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute') }

  let!(:scout) do
    Scout.create!(
      account: account,
      name: 'Sales Qualifier',
      enabled: true
    )
  end

  before do
    ScoutAccountConfig.create!(
      account: account,
      provider: :gemini,
      model_name: 'gemini-2.5-flash',
      api_key: 'test-key'
    )
  end

  describe 'GET /api/v1/accounts/{account.id}/scouts/{scout.id}' do
    it 'returns scout with required_custom_attribute_definitions' do
      scout.required_custom_attribute_definitions << attr1

      get "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['id']).to eq(scout.id)
      expect(json['required_custom_attribute_definitions'].map { |a| a['id'] }).to eq([attr1.id])
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/scouts/{scout.id}' do
    it 'updates scout funnel fields and synchronizes required custom attributes when wrapped' do
      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: {
              scout: {
                qualified_stage_id: stage.id,
                required_custom_attribute_definition_ids: [attr1.id, attr2.id]
              }
            },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['qualified_stage_id']).to eq(stage.id)
      expect(json['required_custom_attribute_definitions'].map { |a| a['id'] }).to contain_exactly(attr1.id, attr2.id)
      expect(scout.reload.required_custom_attribute_definitions).to contain_exactly(attr1, attr2)
    end

    it 'updates scout funnel fields and synchronizes required custom attributes when unwrapped' do
      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: {
              qualified_stage_id: stage.id,
              required_custom_attribute_definition_ids: [attr1.id, attr2.id]
            },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['qualified_stage_id']).to eq(stage.id)
      expect(json['required_custom_attribute_definitions'].map { |a| a['id'] }).to contain_exactly(attr1.id, attr2.id)
      expect(scout.reload.required_custom_attribute_definitions).to contain_exactly(attr1, attr2)
    end

    it 'clears required custom attributes when empty array is passed' do
      scout.required_custom_attribute_definitions << attr1

      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: {
              scout: {
                required_custom_attribute_definition_ids: []
              }
            },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['required_custom_attribute_definitions']).to be_empty
      expect(scout.reload.required_custom_attribute_definitions).to be_empty
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/scouts/{scout.id}/sync_required_attributes' do
    it 'synchronizes required custom attributes via dedicated action' do
      post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/sync_required_attributes",
           params: {
             custom_attribute_definition_ids: [attr1.id]
           },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['required_custom_attribute_definitions'].map { |a| a['id'] }).to eq([attr1.id])
      expect(scout.reload.required_custom_attribute_definitions).to eq([attr1])
    end
  end
end
