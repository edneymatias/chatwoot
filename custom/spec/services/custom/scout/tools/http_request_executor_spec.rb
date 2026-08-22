# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::Tools::HttpRequestExecutor do
  let(:base_url) { 'https://api.example.com/v1/resource' }
  let(:valid_headers) { { 'Authorization' => 'Bearer test-token' } }

  describe 'URL template resolution & consumed keys (User Story 2)' do
    it 'replaces dynamic path placeholders with payload variables' do
      tempfile = Tempfile.new('test')
      tempfile.write('{"status": "ok"}')
      tempfile.rewind
      result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test', content_type: 'application/json')

      expect(SafeFetch).to receive(:fetch).with(
        'https://api.example.com/orders/123/items/456',
        method: :post,
        body: { 'note' => 'urgent' }.to_json,
        headers: hash_including('Content-Type' => 'application/json'),
        sensitive_headers: anything,
        max_bytes: 1.megabyte,
        validate_content_type: false
      ).and_yield(result_double)

      result = described_class.execute(
        endpoint_url: 'https://api.example.com/orders/{{order_id}}/items/{{item_id}}',
        http_method: 'POST',
        payload: { order_id: 123, item_id: '456', note: 'urgent' }
      )

      expect(result.success?).to be true
      expect(result.raw_body).to eq('{"status": "ok"}')
    ensure
      tempfile&.close!
    end

    it 'fails strictly without dispatching request when path variable is missing' do
      expect(SafeFetch).not_to receive(:fetch)

      result = described_class.execute(
        endpoint_url: 'https://api.example.com/orders/{{order_id}}/status',
        http_method: 'GET',
        payload: { other_id: 999 }
      )

      expect(result.success?).to be false
      expect(result.error).to include('Template rendering failed')
    end
  end

  describe 'Query string serialization for GET requests (User Story 2)' do
    it 'appends unconsumed scalar and complex parameters as query string for GET' do
      tempfile = Tempfile.new('test')
      tempfile.write('{"results": []}')
      tempfile.rewind
      result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test', content_type: 'application/json')

      expected_url = 'https://api.example.com/orders/101?limit=10&filters=%7B%22status%22%3A%22active%22%7D'

      expect(SafeFetch).to receive(:fetch).with(
        expected_url,
        method: :get,
        body: nil,
        headers: anything,
        sensitive_headers: anything,
        max_bytes: 1.megabyte,
        validate_content_type: false
      ).and_yield(result_double)

      result = described_class.execute(
        endpoint_url: 'https://api.example.com/orders/{{order_id}}',
        http_method: 'GET',
        payload: {
          'order_id' => 101,
          'limit' => 10,
          'filters' => { 'status' => 'active' }
        }
      )

      expect(result.success?).to be true
    ensure
      tempfile&.close!
    end

    it 'correctly joins query params with ampersand when URL already contains question mark' do
      tempfile = Tempfile.new('test')
      tempfile.write('ok')
      tempfile.rewind
      result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test', content_type: 'text/plain')

      expect(SafeFetch).to receive(:fetch).with(
        'https://api.example.com/search?v=1&query=test',
        method: :get,
        body: nil,
        headers: anything,
        sensitive_headers: anything,
        max_bytes: 1.megabyte,
        validate_content_type: false
      ).and_yield(result_double)

      result = described_class.execute(
        endpoint_url: 'https://api.example.com/search?v=1',
        http_method: 'GET',
        payload: { query: 'test' }
      )

      expect(result.success?).to be true
    ensure
      tempfile&.close!
    end
  end

  describe 'Response shaping with response_template (User Story 3)' do
    it 'renders shaped text output using response and r aliases' do
      tempfile = Tempfile.new('test')
      tempfile.write({ 'order' => { 'id' => 42, 'status' => 'shipped' } }.to_json)
      tempfile.rewind
      result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test', content_type: 'application/json')

      allow(SafeFetch).to receive(:fetch).and_yield(result_double)

      result = described_class.execute(
        endpoint_url: base_url,
        http_method: 'POST',
        response_template: 'Order #{{ r.order.id }} is {{ response.order.status }}.',
        payload: {}
      )

      expect(result.success?).to be true
      expect(result.formatted_response).to eq('Order #42 is shipped.')
    ensure
      tempfile&.close!
    end

    it 'returns parsed JSON when response_template is blank' do
      tempfile = Tempfile.new('test')
      tempfile.write({ 'count' => 5 }.to_json)
      tempfile.rewind
      result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test', content_type: 'application/json')

      allow(SafeFetch).to receive(:fetch).and_yield(result_double)

      result = described_class.execute(
        endpoint_url: base_url,
        http_method: 'GET',
        response_template: '',
        payload: {}
      )

      expect(result.success?).to be true
      expect(result.formatted_response).to eq({ 'count' => 5 })
    ensure
      tempfile&.close!
    end

    it 'returns template error when response_template references non-existent key in strict mode' do
      tempfile = Tempfile.new('test')
      tempfile.write({ 'order' => { 'id' => 42 } }.to_json)
      tempfile.rewind
      result_double = SafeFetch::Result.new(tempfile: tempfile, filename: 'test', content_type: 'application/json')

      allow(SafeFetch).to receive(:fetch).and_yield(result_double)

      result = described_class.execute(
        endpoint_url: base_url,
        http_method: 'GET',
        response_template: 'Status: {{ r.order.missing_key }}',
        payload: {}
      )

      expect(result.success?).to be false
      expect(result.error).to include('Template rendering failed')
    ensure
      tempfile&.close!
    end
  end

  describe 'Error handling & diagnostics (User Story 1)' do
    it 'captures SafeFetch::HttpError cleanly with status code and error message' do
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('404 Not Found'))

      result = described_class.execute(
        endpoint_url: base_url,
        http_method: 'GET'
      )

      expect(result.success?).to be false
      expect(result.status).to eq(404)
      expect(result.error).to include('404 Not Found')
    end

    it 'captures SafeFetch::FetchError on network timeout' do
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FetchError.new('execution expired'))

      result = described_class.execute(
        endpoint_url: base_url,
        http_method: 'GET'
      )

      expect(result.success?).to be false
      expect(result.status).to be_nil
      expect(result.error).to include('timed out')
    end

    it 'truncates raw body to specified preview limit' do
      long_body = 'A' * 600
      result = described_class::Result.new(
        success: true,
        status: 200,
        raw_body: long_body,
        formatted_response: long_body,
        error: nil
      )

      expect(result.truncated_raw_body(500).length).to be <= 503 # 500 chars + '...'
    end
  end
end
