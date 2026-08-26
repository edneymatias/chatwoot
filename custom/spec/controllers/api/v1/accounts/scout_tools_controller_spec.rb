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
    it 'returns list of scout tools with response_template and auth_headers' do
      account.scout_tools.create!(
        name: 'test_tool',
        description: 'Test description',
        endpoint_url: 'https://api.example.com/check',
        http_method: 'POST',
        auth_headers: { 'Authorization' => 'Bearer secret' },
        response_template: 'Status: {{ r.status }}'
      )

      get "/api/v1/accounts/#{account.id}/scout_tools",
          headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json.length).to eq(1)
      expect(json.first['name']).to eq('test_tool')
      expect(json.first['response_template']).to eq('Status: {{ r.status }}')
      expect(json.first['auth_headers']).to include('Authorization')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/scout_tools' do
    it 'creates a new scout tool with endpoint_url and response_template' do
      post "/api/v1/accounts/#{account.id}/scout_tools",
           params: {
             name: 'new_tool',
             description: 'New description',
             endpoint_url: 'https://api.example.com/data',
             http_method: 'GET',
             auth_headers: 'ApiKey xyz',
             response_template: 'Data: {{ r.val }}'
           },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json['name']).to eq('new_tool')
      expect(json['endpoint_url']).to eq('https://api.example.com/data')
      expect(json['response_template']).to eq('Data: {{ r.val }}')

      tool = ScoutTool.find_by(account_id: account.id, name: 'new_tool')
      expect(tool).to be_present
      expect(tool.auth_headers).to eq('ApiKey xyz')
    end

    it 'creates a scout tool with nested parameter_schema and auth_headers objects without 500 error' do
      post "/api/v1/accounts/#{account.id}/scout_tools",
           params: {
             name: 'horarios_livres',
             description: 'Obter horários livres',
             endpoint_url: 'https://api.example.com/horarios',
             http_method: 'GET',
             auth_headers: { 'Authorization' => 'Bearer token123' },
             parameter_schema: {
               type: 'object',
               properties: {
                 idEmpresa: { type: 'integer' },
                 data: { type: 'string' }
               },
               required: %w[idEmpresa data]
             },
             response_template: nil
           },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json['name']).to eq('horarios_livres')
      expect(json['parameter_schema']['properties']['idEmpresa']['type']).to eq('integer')

      tool = ScoutTool.find_by(account_id: account.id, name: 'horarios_livres')
      expect(tool).to be_present
      expect(tool.parameter_schema['required']).to eq(%w[idEmpresa data])
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/scout_tools/:id' do
    it 'updates an existing tool with new parameters and auth_headers' do
      tool = account.scout_tools.create!(
        name: 'old_name',
        description: 'Old description',
        endpoint_url: 'https://api.example.com/old',
        http_method: 'POST',
        auth_headers: 'old_secret'
      )

      patch "/api/v1/accounts/#{account.id}/scout_tools/#{tool.id}",
            params: {
              name: 'updated_name',
              auth_headers: { 'X-Api-Key' => 'updated_secret' },
              response_template: 'New: {{ r.out }}',
              parameter_schema: { type: 'object', properties: { count: { type: 'number' } } }
            },
            headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      tool.reload
      expect(tool.name).to eq('updated_name')
      expect(tool.response_template).to eq('New: {{ r.out }}')
      expect(tool.auth_headers).to include('updated_secret')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/scout_tools/test (User Story 1)' do
    it 'executes draft tool call with sample payload and returns shaped preview' do
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
             auth_headers: 'Bearer token123',
             response_template: 'Order {{ r.status }} (code {{ r.code }})',
             payload: { order_id: 999, verbose: true }
           },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'success' => true,
        'status' => 200,
        'raw_body' => include('delivered'),
        'truncated' => false,
        'formatted_response' => 'Order delivered (code 200)',
        'error' => nil
      )
    ensure
      tempfile&.close!
    end

    it 'sets truncated to true when raw_body exceeds 500 characters' do
      long_body = 'A' * 600
      tempfile = Tempfile.new('test_long')
      tempfile.write(long_body)
      tempfile.rewind
      result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test_long', content_type: 'text/plain')

      expect(SafeFetch).to receive(:fetch).and_yield(result_double)

      post "/api/v1/accounts/#{account.id}/scout_tools/test",
           params: {
             endpoint_url: 'https://api.example.com/long',
             http_method: 'GET'
           },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['truncated']).to be(true)
      expect(json['raw_body'].length).to eq(500)
    ensure
      tempfile&.close!
    end

    it 'captures template rendering failure cleanly without raising 500' do
      post "/api/v1/accounts/#{account.id}/scout_tools/test",
           params: {
             endpoint_url: 'https://api.example.com/orders/{{missing_var}}/status',
             http_method: 'GET',
             payload: { other_id: 123 }
           },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['success']).to be(false)
      expect(json['status']).to be_nil
      expect(json['error']).to include('Template rendering failed')
    end

    it 'captures remote HTTP error cleanly with status' do
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('502 Bad Gateway'))

      post "/api/v1/accounts/#{account.id}/scout_tools/test",
           params: {
             endpoint_url: 'https://api.example.com/failing',
             http_method: 'POST',
             payload: {}
           },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['success']).to be(false)
      expect(json['status']).to eq(502)
      expect(json['error']).to include('502 Bad Gateway')
    end

    it 'correctly extracts payload when wrap_parameters nests scout_tool attributes' do
      tempfile = Tempfile.new('test')
      tempfile.write({ ok: true }.to_json)
      tempfile.rewind
      result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test', content_type: 'application/json')

      expect(SafeFetch).to receive(:fetch).with(
        'https://api.example.com/check?data=2026-08-26&idEmpresa=1041',
        method: :get,
        body: nil,
        headers: hash_including('token' => 'abobora'),
        sensitive_headers: array_including('token'),
        max_bytes: 1.megabyte,
        validate_content_type: false
      ).and_yield(result_double)

      post "/api/v1/accounts/#{account.id}/scout_tools/test",
           params: {
             endpoint_url: 'https://api.example.com/check',
             http_method: 'GET',
             auth_headers: { 'token' => 'abobora' },
             payload: { 'data' => '2026-08-26', 'idEmpresa' => 1041 },
             scout_tool: {
               endpoint_url: 'https://api.example.com/check',
               http_method: 'GET',
               auth_headers: { 'token' => 'abobora' }
             }
           },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['success']).to be(true)
    ensure
      tempfile&.close!
    end
  end
end
