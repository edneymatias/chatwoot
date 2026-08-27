# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::Tools::AuthHeaderBuilder do
  describe '.build' do
    it 'returns empty hash for auth_type none' do
      headers = described_class.build(auth_type: 'none', auth_headers: { 'token' => 'abc' })
      expect(headers).to eq({})
    end

    it 'builds Bearer Authorization header for auth_type bearer' do
      headers = described_class.build(auth_type: 'bearer', auth_headers: { 'token' => 'secret-tok-123' })
      expect(headers).to eq({ 'Authorization' => 'Bearer secret-tok-123' })
    end

    it 'normalizes raw Bearer string for auth_type bearer' do
      headers = described_class.build(auth_type: 'bearer', auth_headers: 'Bearer raw-tok-456')
      expect(headers).to eq({ 'Authorization' => 'Bearer raw-tok-456' })
    end

    it 'builds Basic Authorization header with strict Base64 encoding for auth_type basic' do
      headers = described_class.build(auth_type: 'basic', auth_headers: { 'username' => 'admin', 'password' => 'p@ss:123' })
      expected_encoded = Base64.strict_encode64('admin:p@ss:123')
      expect(headers).to eq({ 'Authorization' => "Basic #{expected_encoded}" })
    end

    it 'builds custom header for auth_type api_key' do
      headers = described_class.build(auth_type: 'api_key', auth_headers: { 'header_name' => 'X-Custom-Auth', 'header_value' => 'api-key-999' })
      expect(headers).to eq({ 'X-Custom-Auth' => 'api-key-999' })
    end

    it 'returns empty hash if required api_key fields are missing' do
      headers = described_class.build(auth_type: 'api_key', auth_headers: { 'header_name' => 'X-Key' })
      expect(headers).to eq({})
    end
  end
end
