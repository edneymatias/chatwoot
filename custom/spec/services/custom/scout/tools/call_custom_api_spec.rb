# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::Tools::CallCustomApi do
  before do
    ActiveRecord::Encryption.config.primary_key = 'test-primary-key-32-chars-length'
    ActiveRecord::Encryption.config.deterministic_key = 'test-determ-key-32-chars-length!'
    ActiveRecord::Encryption.config.key_derivation_salt = 'test-derivation-salt-32-chars!'
    ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)
  end

  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Integration Scout',
      provider: :gemini,
      model_name: 'gemini-2.0-flash',
      enabled: true
    )
  end
  let(:tool) { described_class.new(scout, conversation) }

  let!(:stock_tool) do
    account.scout_tools.create!(
      name: 'check_stock',
      description: 'Checks stock for a product SKU',
      endpoint_url: 'https://erp.example.com/api/stock',
      http_method: 'POST',
      auth_headers: { 'Authorization' => 'Bearer stock-secret-token' },
      parameters_schema: {
        'type' => 'object',
        'properties' => {
          'sku' => { 'type' => 'string' },
          'quantity' => { 'type' => 'integer' }
        },
        'required' => ['sku']
      },
      enabled: true
    )
  end

  describe '#name' do
    it 'returns call_custom_api' do
      expect(tool.name).to eq('call_custom_api')
    end
  end

  describe '#description' do
    it 'includes the catalog of enabled tools for the current account' do
      desc = tool.description
      expect(desc).to include('check_stock')
      expect(desc).to include('Checks stock for a product SKU')
      expect(desc).to include("[ID: #{stock_tool.id}]")
    end

    it 'excludes disabled tools from the catalog' do
      disabled_tool = account.scout_tools.create!(
        name: 'disabled_integration',
        description: 'Disabled service',
        endpoint_url: 'https://disabled.example.com',
        http_method: 'GET',
        enabled: false
      )

      desc = tool.description
      expect(desc).not_to include('disabled_integration')
      expect(desc).not_to include("[ID: #{disabled_tool.id}]")
    end

    it 'excludes tools belonging to other accounts' do
      other_tool = other_account.scout_tools.create!(
        name: 'other_secret_tool',
        description: 'Other account service',
        endpoint_url: 'https://other.example.com',
        http_method: 'POST',
        enabled: true
      )

      desc = tool.description
      expect(desc).not_to include('other_secret_tool')
      expect(desc).not_to include("[ID: #{other_tool.id}]")
    end
  end

  describe '#execute' do
    context 'when executing successfully (User Story 1)' do
      it 'executes outbound POST request via SafeFetch with auth headers and returns parsed response' do
        expected_response = { 'in_stock' => true, 'count' => 42 }
        tempfile = Tempfile.new('test-response')
        tempfile.write(expected_response.to_json)
        tempfile.rewind

        result_double = SafeFetch::Result.new(
          tempfile: tempfile,
          filename: 'stock',
          content_type: 'application/json'
        )

        expect(SafeFetch).to receive(:fetch).with(
          'https://erp.example.com/api/stock',
          method: :post,
          body: { 'sku' => 'PROD-123', 'quantity' => 2 }.to_json,
          headers: hash_including('Authorization' => 'Bearer stock-secret-token', 'Content-Type' => 'application/json'),
          sensitive_headers: array_including('Authorization'),
          max_bytes: 1.megabyte,
          validate_content_type: false
        ).and_yield(result_double)

        response = tool.execute(tool_id: stock_tool.id, payload: { sku: 'PROD-123', quantity: 2 })
        expect(response).to eq(expected_response)
      ensure
        tempfile&.close!
      end

      it 'executes outbound GET request properly' do
        weather_tool = account.scout_tools.create!(
          name: 'get_weather',
          description: 'Get weather',
          endpoint_url: 'https://weather.example.com/now',
          http_method: 'GET',
          auth_headers: 'ApiKey custom-key-123',
          parameters_schema: {},
          enabled: true
        )

        tempfile = Tempfile.new('weather-response')
        tempfile.write('Sunny 25C')
        tempfile.rewind

        result_double = SafeFetch::Result.new(
          tempfile: tempfile,
          filename: 'weather',
          content_type: 'text/plain'
        )

        expect(SafeFetch).to receive(:fetch).with(
          'https://weather.example.com/now',
          method: :get,
          body: nil,
          headers: hash_including('Authorization' => 'ApiKey custom-key-123'),
          sensitive_headers: array_including('Authorization'),
          max_bytes: 1.megabyte,
          validate_content_type: false
        ).and_yield(result_double)

        response = tool.execute(tool_id: weather_tool.id)
        expect(response).to eq('Sunny 25C')
      ensure
        tempfile&.close!
      end

      it 'enforces cross-account isolation by refusing tools from other accounts' do
        other_tool = other_account.scout_tools.create!(
          name: 'competitor_stock',
          description: 'Competitor stock',
          endpoint_url: 'https://competitor.example.com',
          http_method: 'POST',
          enabled: true
        )

        expect(SafeFetch).not_to receive(:fetch)

        response = tool.execute(tool_id: other_tool.id, payload: { sku: 'ABC' })
        expect(response).to eq('Tool unavailable or not found.')
      end
    end

    context 'when handling errors and misbehaving systems (User Story 2)' do
      it 'returns structured validation error when required parameter is missing without contacting endpoint' do
        expect(SafeFetch).not_to receive(:fetch)

        response = tool.execute(tool_id: stock_tool.id, payload: { quantity: 5 })
        expect(response).to include('Invalid payload parameters')
        expect(response).to include('sku')
      end

      it 'returns structured validation error when parameter type is invalid without contacting endpoint' do
        expect(SafeFetch).not_to receive(:fetch)

        response = tool.execute(tool_id: stock_tool.id, payload: { sku: 12_345 })
        expect(response).to include('Invalid payload parameters')
        expect(response).to include('string')
      end

      it 'rescues timeout or network fetch errors gracefully and logs error' do
        expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FetchError.new('execution expired'))
        expect(Rails.logger).to receive(:error).with(/Scout CallCustomApi/).at_least(:once)

        response = tool.execute(tool_id: stock_tool.id, payload: { sku: 'PROD-999' })
        expect(response).to include('Request failed or timed out')
      end

      it 'rescues oversized response errors gracefully and logs error' do
        expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FileTooLargeError.new('exceeded 1048576 bytes'))
        expect(Rails.logger).to receive(:error).with(/Scout CallCustomApi/).at_least(:once)

        response = tool.execute(tool_id: stock_tool.id, payload: { sku: 'PROD-999' })
        expect(response).to include('Response exceeded maximum allowed size')
      end

      it 'surfaces HTTP error status cleanly without crashing conversation' do
        expect(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('503 Service Unavailable'))
        expect(Rails.logger).to receive(:error).with(/Scout CallCustomApi/).at_least(:once)

        response = tool.execute(tool_id: stock_tool.id, payload: { sku: 'PROD-999' })
        expect(response).to include('503 Service Unavailable')
      end

      it 'rescues unexpected standard errors without raising' do
        expect(SafeFetch).to receive(:fetch).and_raise(StandardError.new('Unexpected failure'))
        expect(Rails.logger).to receive(:error).with(/Scout CallCustomApi/).at_least(:once)

        expect do
          response = tool.execute(tool_id: stock_tool.id, payload: { sku: 'PROD-999' })
          expect(response).to include('error occurred')
        end.not_to raise_error
      end
    end

    context 'when tools are disabled or nonexistent (User Story 3)' do
      it 'returns unavailable for disabled tools without contacting endpoint' do
        stock_tool.update!(enabled: false)
        expect(SafeFetch).not_to receive(:fetch)

        response = tool.execute(tool_id: stock_tool.id, payload: { sku: 'PROD-123' })
        expect(response).to eq('Tool unavailable or not found.')
      end

      it 'returns unavailable for nonexistent tool_id without contacting endpoint' do
        expect(SafeFetch).not_to receive(:fetch)

        response = tool.execute(tool_id: 999_999, payload: { sku: 'PROD-123' })
        expect(response).to eq('Tool unavailable or not found.')
      end
    end
  end
end
