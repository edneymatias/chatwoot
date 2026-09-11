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

    it 'updates default_country_code and default_area_code' do
      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: { scout: { default_country_code: '+55', default_area_code: '41' } },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['default_country_code']).to eq('+55')
      expect(json['default_area_code']).to eq('41')
      scout.reload
      expect(scout.default_country_code).to eq('+55')
      expect(scout.default_area_code).to eq('41')
    end

    it 'updates rescue_stage_id and follow_up_delays_hours' do
      rescue_stage = PipelineStage.create!(account: account, name: 'Rescue Stage')

      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: {
              scout: {
                rescue_stage_id: rescue_stage.id,
                follow_up_delays_hours: [3, 6, 18]
              }
            },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['rescue_stage_id']).to eq(rescue_stage.id)
      expect(json['follow_up_delays_hours']).to eq([3, 6, 18])
      scout.reload
      expect(scout.rescue_stage_id).to eq(rescue_stage.id)
      expect(scout.follow_up_delays_hours).to eq([3, 6, 18])
    end

    it 'returns unprocessable_entity when follow_up_delays_hours is invalid' do
      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: {
              scout: {
                follow_up_delays_hours: [10, 2]
              }
            },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      json = response.parsed_body
      expect(json['error']).to be_present
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

    it 'updates audience conditions when passed' do
      conditions = [
        {
          'attribute_key' => 'phone_number',
          'filter_operator' => 'equal_to',
          'values' => ['+5511999999999'],
          'query_operator' => 'and'
        }
      ]

      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: {
              scout: {
                audience: conditions
              }
            },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['audience']).to eq(conditions)
      expect(scout.reload.audience).to eq(conditions)
    end

    it 'clears audience when empty array is passed' do
      scout.update!(audience: [{ 'attribute_key' => 'phone_number', 'filter_operator' => 'equal_to', 'values' => ['+5511999999999'] }])

      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: {
              scout: {
                audience: []
              }
            },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['audience']).to eq([])
      expect(scout.reload.audience).to eq([])
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
