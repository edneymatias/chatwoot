# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::ScoutTools', type: :request do
  before do
    ActiveRecord::Encryption.config.primary_key = 'test-primary-key-32-chars-length'
    ActiveRecord::Encryption.config.deterministic_key = 'test-determ-key-32-chars-length!'
    ActiveRecord::Encryption.config.key_derivation_salt = 'test-derivation-salt-32-chars!'
    ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)
  end

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/{account.id}/scout_tools' do
    it 'returns list of scout tools with response_template and masked auth_headers' do
      account.scout_tools.create!(
        name: 'test_tool',
        description: 'Test description',
        endpoint_url: 'https://api.example.com/check',
        http_method: 'POST',
        auth_type: 'bearer',
        auth_headers: { 'token' => 'real-secret-token' },
        response_template: 'Status: {{ r.status }}'
      )

      get "/api/v1/accounts/#{account.id}/scout_tools",
          headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json.length).to eq(1)
      expect(json.first['name']).to eq('test_tool')
      expect(json.first['auth_type']).to eq('bearer')
      expect(json.first['auth_headers']).to eq({ 'token' => '••••••••' })
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/scout_tools' do
    it 'creates a new scout tool with auth_type and encrypted credentials' do
      post "/api/v1/accounts/#{account.id}/scout_tools",
           params: {
             name: 'new_tool',
             description: 'New description',
             endpoint_url: 'https://api.example.com/data',
             http_method: 'GET',
             auth_type: 'bearer',
             auth_headers: { 'token' => 'live_token_123' },
             response_template: 'Data: {{ r.val }}'
           },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json['name']).to eq('new_tool')
      expect(json['auth_type']).to eq('bearer')
      expect(json['auth_headers']).to eq({ 'token' => '••••••••' })

      tool = ScoutTool.find_by(account_id: account.id, name: 'new_tool')
      expect(tool).to be_present
      expect(tool.parsed_auth_headers).to eq({ 'token' => 'live_token_123' })
    end

    it 'creates a scout tool with nested parameter_schema' do
      post "/api/v1/accounts/#{account.id}/scout_tools",
           params: {
             name: 'horarios_livres',
             description: 'Obter horários livres',
             endpoint_url: 'https://api.example.com/horarios',
             http_method: 'GET',
             auth_type: 'basic',
             auth_headers: { 'username' => 'admin', 'password' => 'pass123' },
             parameter_schema: {
               type: 'object',
               properties: {
                 idEmpresa: { type: 'integer' },
                 data: { type: 'string' }
               },
               required: %w[idEmpresa data]
             }
           },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json['name']).to eq('horarios_livres')
      expect(json['parameter_schema']['properties']['idEmpresa']['type']).to eq('integer')

      tool = ScoutTool.find_by(account_id: account.id, name: 'horarios_livres')
      expect(tool).to be_present
      expect(tool.parsed_auth_headers).to eq({ 'username' => 'admin', 'password' => 'pass123' })
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/scout_tools/:id' do
    it 'preserves existing secret when masked placeholder is submitted' do
      tool = account.scout_tools.create!(
        name: 'old_name',
        description: 'Old description',
        endpoint_url: 'https://api.example.com/old',
        http_method: 'POST',
        auth_type: 'bearer',
        auth_headers: { 'token' => 'existing-secret-token' }
      )

      patch "/api/v1/accounts/#{account.id}/scout_tools/#{tool.id}",
            params: {
              name: 'updated_name',
              auth_type: 'bearer',
              auth_headers: { 'token' => '••••••••' }
            },
            headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      tool.reload
      expect(tool.name).to eq('updated_name')
      expect(tool.parsed_auth_headers).to eq({ 'token' => 'existing-secret-token' })
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/scout_tools/test' do
    it 'executes draft tool call with auth_type and sample payload' do
      tempfile = Tempfile.new('test')
      tempfile.write({ status: 'delivered', code: 200 }.to_json)
      tempfile.rewind
      result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test', content_type: 'application/json')

      expect(SafeFetch).to receive(:fetch).with(
        'https://api.example.com/orders/999/status?verbose=true',
        method: :get,
        body: nil,
        headers: hash_including('Authorization' => 'Bearer token123'),
        sensitive_headers: array_including('Authorization'),
        max_bytes: 1.megabyte,
        validate_content_type: false
      ).and_yield(result_double)

      post "/api/v1/accounts/#{account.id}/scout_tools/test",
           params: {
             endpoint_url: 'https://api.example.com/orders/{{order_id}}/status',
             http_method: 'GET',
             auth_type: 'bearer',
             auth_headers: { 'token' => 'token123' },
             response_template: 'Order {{ r.status }} (code {{ r.code }})',
             payload: { order_id: 999, verbose: true }
           },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'success' => true,
        'status' => 200,
        'formatted_response' => 'Order delivered (code 200)'
      )
    ensure
      tempfile&.close!
    end
  end
end
