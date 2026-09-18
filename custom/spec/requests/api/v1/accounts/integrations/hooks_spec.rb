# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Integrations::Hooks', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base_url) { 'https://wfh.ichatr.com.br/webhook/pessoas' }

  before do
    account.enable_features!('erp_integration')
  end

  describe 'POST /api/v1/accounts/{account.id}/integrations/hooks' do
    let(:url) { "/api/v1/accounts/#{account.id}/integrations/hooks" }
    let(:valid_params) do
      {
        hook: {
          app_id: 'younus',
          settings: {
            token: 'valid-secret-token',
            id_empresa: '42'
          }
        }
      }
    end

    it 'persists enabled hook and returns 200 with masked token and cleartext id_empresa (A10, U32)' do
      stub_request(:get, base_url)
        .with(query: { idEmpresa: '42', nrTelcelpessoa: '0' }, headers: { 'token' => 'valid-secret-token' })
        .to_return(status: 200, body: { sucesso: false, dados: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

      post url,
           headers: admin.create_new_auth_token,
           params: valid_params,
           as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body['app_id']).to eq('younus')
      expect(body['status']).to be(true)
      expect(body['settings']['id_empresa']).to eq('42')
      expect(body['settings']['token']).to eq('••••••••')

      hook = account.hooks.find_by(app_id: 'younus')
      expect(hook).to be_present
      expect(hook.settings['token']).to eq('valid-secret-token')
    end

    it 'rejects invalid credentials with 422 and invalid credentials message (A8)' do
      stub_request(:get, base_url)
        .with(query: { idEmpresa: '42', nrTelcelpessoa: '0' }, headers: { 'token' => 'valid-secret-token' })
        .to_return(status: 401, body: { error: 'Unauthorized' }.to_json)

      post url,
           headers: admin.create_new_auth_token,
           params: valid_params,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['message']).to include(I18n.t('errors.erp.invalid_credentials'))
      expect(account.hooks.where(app_id: 'younus')).to be_empty
    end

    it 'rejects remote service failure with 422 and connection error message (A9)' do
      stub_request(:get, base_url)
        .with(query: { idEmpresa: '42', nrTelcelpessoa: '0' }, headers: { 'token' => 'valid-secret-token' })
        .to_return(status: 503, body: 'Service Unavailable')

      post url,
           headers: admin.create_new_auth_token,
           params: valid_params,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['message']).to include(I18n.t('errors.erp.connection_error'))
      expect(account.hooks.where(app_id: 'younus')).to be_empty
    end

    it 'rejects request with 422 when erp_integration feature flag is disabled' do
      account.disable_features!('erp_integration')

      post url,
           headers: admin.create_new_auth_token,
           params: valid_params,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.hooks.where(app_id: 'younus')).to be_empty
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/integrations/apps' do
    let(:url) { "/api/v1/accounts/#{account.id}/integrations/apps" }

    it 'includes younus in catalog when erp_integration is enabled' do
      get url,
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      younus = body['payload'].find { |app| app['id'] == 'younus' }
      expect(younus).to be_present
      expect(younus['category']).to eq('erp')
    end

    it 'omits younus from catalog when erp_integration is disabled' do
      account.disable_features!('erp_integration')

      get url,
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      younus = body['payload'].find { |app| app['id'] == 'younus' }
      expect(younus).to be_nil
    end
  end
end
