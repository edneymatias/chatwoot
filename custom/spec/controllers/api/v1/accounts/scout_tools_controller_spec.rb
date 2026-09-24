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

    it 'masks credentials for all auth types and never exposes decrypted secrets in list (User Story 3)' do
      account.scout_tools.create!(
        name: 'bearer_tool',
        description: 'Bearer',
        endpoint_url: 'https://api.example.com/b',
        http_method: 'GET',
        auth_type: 'bearer',
        auth_headers: { 'token' => 'super-secret-bearer-token' }
      )
      account.scout_tools.create!(
        name: 'basic_tool',
        description: 'Basic',
        endpoint_url: 'https://api.example.com/ba',
        http_method: 'GET',
        auth_type: 'basic',
        auth_headers: { 'username' => 'admin_user', 'password' => 'super-secret-basic-pass' }
      )
      account.scout_tools.create!(
        name: 'api_key_tool',
        description: 'Api Key',
        endpoint_url: 'https://api.example.com/k',
        http_method: 'GET',
        auth_type: 'api_key',
        auth_headers: { 'header_name' => 'X-Secret-Header', 'header_value' => 'super-secret-api-key' }
      )

      get "/api/v1/accounts/#{account.id}/scout_tools",
          headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      body_text = response.body
      expect(body_text).not_to include('super-secret-bearer-token')
      expect(body_text).not_to include('super-secret-basic-pass')
      expect(body_text).not_to include('super-secret-api-key')

      tools = response.parsed_body
      bearer = tools.find { |t| t['name'] == 'bearer_tool' }
      basic = tools.find { |t| t['name'] == 'basic_tool' }
      api_key = tools.find { |t| t['name'] == 'api_key_tool' }

      expect(bearer['auth_headers']).to eq({ 'token' => ScoutTool::MASKED_SECRET })
      expect(basic['auth_headers']).to eq({ 'username' => 'admin_user', 'password' => ScoutTool::MASKED_SECRET })
      expect(api_key['auth_headers']).to eq({ 'header_name' => 'X-Secret-Header', 'header_value' => ScoutTool::MASKED_SECRET })
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/scout_tools/:id (User Story 3)' do
    it 'returns scout tool details with masked auth_headers and never exposes decrypted plain text' do
      tool = account.scout_tools.create!(
        name: 'secret_tool',
        description: 'Tool with sensitive credentials',
        endpoint_url: 'https://api.example.com/check',
        http_method: 'POST',
        auth_type: 'bearer',
        auth_headers: { 'token' => 'confidential-raw-secret-token' },
        response_template: 'Status: {{ r.status }}'
      )

      get "/api/v1/accounts/#{account.id}/scout_tools/#{tool.id}",
          headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('confidential-raw-secret-token')

      json = response.parsed_body
      expect(json['id']).to eq(tool.id)
      expect(json['name']).to eq('secret_tool')
      expect(json['auth_type']).to eq('bearer')
      expect(json['auth_headers']).to eq({ 'token' => ScoutTool::MASKED_SECRET })
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

    context 'when testing an existing saved tool (User Story 1)' do
      let!(:existing_tool) do
        account.scout_tools.create!(
          name: 'existing_tool',
          description: 'Existing tool description',
          endpoint_url: 'https://api.example.com/original/path',
          http_method: 'GET',
          auth_type: 'bearer',
          auth_headers: { 'token' => 'real-saved-bearer-token' }
        )
      end

      it 'uses real saved credential when masked placeholder is submitted' do
        tempfile = Tempfile.new('test')
        tempfile.write({ status: 'ok' }.to_json)
        tempfile.rewind
        result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test', content_type: 'application/json')

        expect(SafeFetch).to receive(:fetch).with(
          'https://api.example.com/original/path',
          method: :get,
          body: nil,
          headers: hash_including('Authorization' => 'Bearer real-saved-bearer-token'),
          sensitive_headers: array_including('Authorization'),
          max_bytes: 1.megabyte,
          validate_content_type: false
        ).and_yield(result_double)

        post "/api/v1/accounts/#{account.id}/scout_tools/test",
             params: {
               id: existing_tool.id,
               endpoint_url: existing_tool.endpoint_url,
               http_method: 'GET',
               auth_type: 'bearer',
               auth_headers: { 'token' => ScoutTool::MASKED_SECRET }
             },
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
      ensure
        tempfile&.close!
      end

      it 'uses real saved credential when credential field is blank or omitted' do
        tempfile = Tempfile.new('test')
        tempfile.write({ status: 'ok' }.to_json)
        tempfile.rewind
        result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test', content_type: 'application/json')

        expect(SafeFetch).to receive(:fetch).with(
          'https://api.example.com/original/path',
          method: :get,
          body: nil,
          headers: hash_including('Authorization' => 'Bearer real-saved-bearer-token'),
          sensitive_headers: array_including('Authorization'),
          max_bytes: 1.megabyte,
          validate_content_type: false
        ).and_yield(result_double)

        post "/api/v1/accounts/#{account.id}/scout_tools/test",
             params: {
               id: existing_tool.id,
               endpoint_url: existing_tool.endpoint_url,
               http_method: 'GET',
               auth_type: 'bearer',
               auth_headers: { 'token' => '' }
             },
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
      ensure
        tempfile&.close!
      end

      it 'preserves saved credential even when a non-credential field like endpoint_url is modified' do
        tempfile = Tempfile.new('test')
        tempfile.write({ status: 'ok' }.to_json)
        tempfile.rewind
        result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test', content_type: 'application/json')

        expect(SafeFetch).to receive(:fetch).with(
          'https://api.example.com/updated/endpoint',
          method: :get,
          body: nil,
          headers: hash_including('Authorization' => 'Bearer real-saved-bearer-token'),
          sensitive_headers: array_including('Authorization'),
          max_bytes: 1.megabyte,
          validate_content_type: false
        ).and_yield(result_double)

        post "/api/v1/accounts/#{account.id}/scout_tools/test",
             params: {
               id: existing_tool.id,
               endpoint_url: 'https://api.example.com/updated/endpoint',
               http_method: 'GET',
               auth_type: 'bearer',
               auth_headers: { 'token' => ScoutTool::MASKED_SECRET }
             },
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
      ensure
        tempfile&.close!
      end

      it 'uses newly typed credential instead of saved credential when provided' do
        tempfile = Tempfile.new('test')
        tempfile.write({ status: 'ok' }.to_json)
        tempfile.rewind
        result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test', content_type: 'application/json')

        expect(SafeFetch).to receive(:fetch).with(
          'https://api.example.com/original/path',
          method: :get,
          body: nil,
          headers: hash_including('Authorization' => 'Bearer newly-typed-token'),
          sensitive_headers: array_including('Authorization'),
          max_bytes: 1.megabyte,
          validate_content_type: false
        ).and_yield(result_double)

        post "/api/v1/accounts/#{account.id}/scout_tools/test",
             params: {
               id: existing_tool.id,
               endpoint_url: existing_tool.endpoint_url,
               http_method: 'GET',
               auth_type: 'bearer',
               auth_headers: { 'token' => 'newly-typed-token' }
             },
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
      ensure
        tempfile&.close!
      end
    end

    context 'when testing a brand-new unsaved tool without id (User Story 2)' do
      let!(:existing_tool) do
        account.scout_tools.create!(
          name: 'some_tool',
          description: 'Desc',
          endpoint_url: 'https://api.example.com/some',
          http_method: 'GET',
          auth_type: 'bearer',
          auth_headers: { 'token' => 'do-not-leak-or-substitute' }
        )
      end

      it 'uses literal submitted value without substituting any saved tool credential' do
        expect(existing_tool).to be_persisted

        tempfile = Tempfile.new('test')
        tempfile.write({ status: 'ok' }.to_json)
        tempfile.rewind
        result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test', content_type: 'application/json')

        expect(SafeFetch).to receive(:fetch).with(
          'https://api.example.com/draft',
          method: :get,
          body: nil,
          headers: hash_including('Authorization' => "Bearer #{ScoutTool::MASKED_SECRET}"),
          sensitive_headers: array_including('Authorization'),
          max_bytes: 1.megabyte,
          validate_content_type: false
        ).and_yield(result_double)

        post "/api/v1/accounts/#{account.id}/scout_tools/test",
             params: {
               endpoint_url: 'https://api.example.com/draft',
               http_method: 'GET',
               auth_type: 'bearer',
               auth_headers: { 'token' => ScoutTool::MASKED_SECRET }
             },
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
      ensure
        tempfile&.close!
      end
    end

    context 'when testing with invalid or cross-account id (User Story 2)' do
      let(:other_account) { create(:account) }
      let!(:other_tool) do
        other_account.scout_tools.create!(
          name: 'foreign_tool',
          description: 'Foreign tool',
          endpoint_url: 'https://api.example.com/foreign',
          http_method: 'GET',
          auth_type: 'bearer',
          auth_headers: { 'token' => 'foreign-secret-token' }
        )
      end

      it 'falls back to literal submitted values and never uses foreign account credentials' do
        tempfile = Tempfile.new('test')
        tempfile.write({ status: 'ok' }.to_json)
        tempfile.rewind
        result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test', content_type: 'application/json')

        expect(SafeFetch).to receive(:fetch).with(
          'https://api.example.com/test',
          method: :get,
          body: nil,
          headers: hash_including('Authorization' => "Bearer #{ScoutTool::MASKED_SECRET}"),
          sensitive_headers: array_including('Authorization'),
          max_bytes: 1.megabyte,
          validate_content_type: false
        ).and_yield(result_double)

        post "/api/v1/accounts/#{account.id}/scout_tools/test",
             params: {
               id: other_tool.id,
               endpoint_url: 'https://api.example.com/test',
               http_method: 'GET',
               auth_type: 'bearer',
               auth_headers: { 'token' => ScoutTool::MASKED_SECRET }
             },
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
      ensure
        tempfile&.close!
      end

      it 'falls back to literal submitted values when id is nonexistent or non-numeric without error' do
        tempfile = Tempfile.new('test')
        tempfile.write({ status: 'ok' }.to_json)
        tempfile.rewind
        result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test', content_type: 'application/json')

        expect(SafeFetch).to receive(:fetch).with(
          'https://api.example.com/test',
          method: :get,
          body: nil,
          headers: hash_including('Authorization' => "Bearer #{ScoutTool::MASKED_SECRET}"),
          sensitive_headers: array_including('Authorization'),
          max_bytes: 1.megabyte,
          validate_content_type: false
        ).and_yield(result_double)

        post "/api/v1/accounts/#{account.id}/scout_tools/test",
             params: {
               id: 'non-numeric-or-not-found',
               endpoint_url: 'https://api.example.com/test',
               http_method: 'GET',
               auth_type: 'bearer',
               auth_headers: { 'token' => ScoutTool::MASKED_SECRET }
             },
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
      ensure
        tempfile&.close!
      end
    end
  end
end
