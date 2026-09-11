# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::ScoutAccountConfigs', type: :request do
  before do
    ActiveRecord::Encryption.config.primary_key = 'test-primary-key-32-chars-length'
    ActiveRecord::Encryption.config.deterministic_key = 'test-determ-key-32-chars-length!'
    ActiveRecord::Encryption.config.key_derivation_salt = 'test-derivation-salt-32-chars!'
    ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/{account.id}/scout_account_config' do
    context 'when user is administrator' do
      it 'returns unconfigured state when no record exists' do
        get "/api/v1/accounts/#{account.id}/scout_account_config",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json['configured']).to be(false)
        expect(json['has_api_key']).to be(false)
      end

      it 'returns configured state when record exists' do
        ScoutAccountConfig.create!(
          account: account,
          provider: :gemini,
          model_name: 'gemini-2.5-flash',
          api_key: 'test-key'
        )

        get "/api/v1/accounts/#{account.id}/scout_account_config",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json['configured']).to be(true)
        expect(json['provider']).to eq('gemini')
        expect(json['model_name']).to eq('gemini-2.5-flash')
        expect(json['has_api_key']).to be(true)
      end
    end

    context 'when user is not administrator' do
      it 'returns unauthorized/forbidden status' do
        get "/api/v1/accounts/#{account.id}/scout_account_config",
            headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/scout_account_config' do
    let(:fake_context) { instance_double(RubyLLM::Context) }
    let(:fake_chat) { instance_double(RubyLLM::Chat) }

    before do
      fake_config = instance_double(RubyLLM::Configuration, :gemini_api_key= => nil, :openai_api_key= => nil)
      allow(RubyLLM).to receive(:context).and_yield(fake_config).and_return(fake_context)
      allow(fake_context).to receive(:chat).and_return(fake_chat)
      allow(fake_chat).to receive(:ask).with('ping').and_return(instance_double(RubyLLM::Message, content: 'pong'))
    end

    context 'when user is administrator' do
      it 'creates and validates new account configuration' do
        patch "/api/v1/accounts/#{account.id}/scout_account_config",
              params: {
                scout_account_config: {
                  provider: 'gemini',
                  model_name: 'gemini-2.5-flash',
                  api_key: 'valid-api-key'
                }
              },
              headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json['configured']).to be(true)
        expect(json['provider']).to eq('gemini')

        config = ScoutAccountConfig.find_by(account_id: account.id)
        expect(config).to be_present
        expect(config.api_key).to eq('valid-api-key')
      end

      it 'returns unprocessable entity when provider test fails' do
        allow(fake_chat).to receive(:ask).with('ping').and_raise(RubyLLM::UnauthorizedError.new('Bad Key', response: nil))

        patch "/api/v1/accounts/#{account.id}/scout_account_config",
              params: {
                scout_account_config: {
                  provider: 'gemini',
                  model_name: 'gemini-2.5-flash',
                  api_key: 'invalid-api-key'
                }
              },
              headers: admin.create_new_auth_token

        expect(response).to have_http_status(:unprocessable_entity)
        json = response.parsed_body
        expect(json['error']).to include('inválida')
      end

      it 'preserves existing api_key if updated with blank key on persisted config' do
        ScoutAccountConfig.create!(
          account: account,
          provider: :gemini,
          model_name: 'gemini-2.5-flash',
          api_key: 'original-api-key'
        )

        patch "/api/v1/accounts/#{account.id}/scout_account_config",
              params: {
                scout_account_config: {
                  provider: 'openai',
                  model_name: 'gpt-4o',
                  api_key: ''
                }
              },
              headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        config = ScoutAccountConfig.find_by(account_id: account.id)
        expect(config.provider).to eq('openai')
        expect(config.model_name).to eq('gpt-4o')
        expect(config.api_key).to eq('original-api-key')
      end
    end

    context 'when user is not administrator' do
      it 'returns unauthorized/forbidden status' do
        patch "/api/v1/accounts/#{account.id}/scout_account_config",
              params: {
                scout_account_config: {
                  provider: 'gemini',
                  model_name: 'gemini-2.5-flash',
                  api_key: 'valid-api-key'
                }
              },
              headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
