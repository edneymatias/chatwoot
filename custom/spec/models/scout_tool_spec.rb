# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScoutTool, type: :model do
  before do
    ActiveRecord::Encryption.config.primary_key = 'test-primary-key-32-chars-length'
    ActiveRecord::Encryption.config.deterministic_key = 'test-determ-key-32-chars-length!'
    ActiveRecord::Encryption.config.key_derivation_salt = 'test-derivation-salt-32-chars!'
    ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)
  end

  let(:account) { create(:account) }
  let(:valid_attributes) do
    {
      account: account,
      name: 'fetch_weather',
      description: 'Fetch current weather by city name',
      endpoint_url: 'https://api.weather.example.com/v1/current',
      http_method: 'GET',
      auth_type: 'none',
      auth_headers: 'Bearer secret-token',
      parameter_schema: {
        'type' => 'object',
        'properties' => {
          'city' => { 'type' => 'string' }
        },
        'required' => ['city']
      },
      response_template: 'Weather: {{ r.temp }}C'
    }
  end

  describe 'associations' do
    it 'belongs to account' do
      tool = described_class.new(valid_attributes)
      expect(tool.account).to eq(account)
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(described_class.new(valid_attributes)).to be_valid
    end

    it 'validates presence of account' do
      tool = described_class.new(valid_attributes.merge(account: nil))
      expect(tool).not_to be_valid
      expect(tool.errors[:account]).to be_present
    end

    it 'validates presence of name' do
      tool = described_class.new(valid_attributes.merge(name: nil))
      expect(tool).not_to be_valid
      expect(tool.errors[:name]).to include("can't be blank")
    end

    it 'validates presence of description' do
      tool = described_class.new(valid_attributes.merge(description: nil))
      expect(tool).not_to be_valid
      expect(tool.errors[:description]).to include("can't be blank")
    end

    it 'validates presence of endpoint_url' do
      tool = described_class.new(valid_attributes.merge(endpoint_url: nil))
      expect(tool).not_to be_valid
      expect(tool.errors[:endpoint_url]).to include("can't be blank")
    end

    it 'validates presence of http_method' do
      tool = described_class.new(valid_attributes.merge(http_method: nil))
      expect(tool).not_to be_valid
      expect(tool.errors[:http_method]).to include("can't be blank")
    end

    it 'validates inclusion of auth_type' do
      expect(described_class.new(valid_attributes.merge(auth_type: 'none', auth_headers: nil))).to be_valid
      expect(described_class.new(valid_attributes.merge(auth_type: 'bearer', auth_headers: { 'token' => 'tok' }))).to be_valid
      expect(described_class.new(valid_attributes.merge(auth_type: 'basic', auth_headers: { 'username' => 'u', 'password' => 'p' }))).to be_valid
      valid_api = described_class.new(
        valid_attributes.merge(
          auth_type: 'api_key',
          auth_headers: { 'header_name' => 'k', 'header_value' => 'v' }
        )
      )
      expect(valid_api).to be_valid

      invalid_tool = described_class.new(valid_attributes.merge(auth_type: 'oauth1'))
      expect(invalid_tool).not_to be_valid
      expect(invalid_tool.errors[:auth_type]).to be_present
    end

    it 'validates parameter_schema property names' do
      valid_tool = described_class.new(valid_attributes.merge(
                                         parameter_schema: {
                                           'type' => 'object',
                                           'properties' => {
                                             'order_id' => { 'type' => 'string' },
                                             '_serial123' => { 'type' => 'number' }
                                           }
                                         }
                                       ))
      expect(valid_tool).to be_valid

      invalid_tool = described_class.new(valid_attributes.merge(
                                           parameter_schema: {
                                             'type' => 'object',
                                             'properties' => {
                                               'order id' => { 'type' => 'string' }
                                             }
                                           }
                                         ))
      expect(invalid_tool).not_to be_valid
      expect(invalid_tool.errors[:parameter_schema].join).to include('contains invalid property name')
    end

    it 'validates required auth_headers credentials for selected auth_type' do
      invalid_bearer = described_class.new(valid_attributes.merge(auth_type: 'bearer', auth_headers: {}))
      expect(invalid_bearer).not_to be_valid
      expect(invalid_bearer.errors[:auth_headers]).to be_present

      invalid_basic = described_class.new(valid_attributes.merge(auth_type: 'basic', auth_headers: { 'username' => 'admin' }))
      expect(invalid_basic).not_to be_valid
      expect(invalid_basic.errors[:auth_headers]).to be_present

      invalid_api_key = described_class.new(valid_attributes.merge(auth_type: 'api_key', auth_headers: { 'header_name' => 'X-Key' }))
      expect(invalid_api_key).not_to be_valid
      expect(invalid_api_key.errors[:auth_headers]).to be_present

      valid_api_key = described_class.new(valid_attributes.merge(
                                            auth_type: 'api_key',
                                            auth_headers: { 'header_name' => 'X-Key', 'header_value' => 'Val123' }
                                          ))
      expect(valid_api_key).to be_valid
    end
  end

  describe 'encryption at rest and masked helpers' do
    it 'encrypts auth_headers unconditionally' do
      tool = described_class.create!(valid_attributes)

      raw_stored = tool.reload.read_attribute_before_type_cast(:auth_headers).to_s
      expect(raw_stored).to be_present
      expect(raw_stored).not_to include('Bearer secret-token')
      expect(tool.auth_headers).to eq('Bearer secret-token')
      expect(tool.encrypted_attribute?(:auth_headers)).to be(true)
    end

    it 'serializes Hash auth_headers to valid JSON' do
      tool = described_class.create!(valid_attributes.merge(auth_headers: { 'Authorization' => 'Bearer token123' }))
      expect(tool.reload.auth_headers).to eq({ 'Authorization' => 'Bearer token123' }.to_json)
    end

    it 'returns masked auth_headers for bearer auth_type' do
      tool = described_class.create!(valid_attributes.merge(
                                       auth_type: 'bearer',
                                       auth_headers: { 'token' => 'real-token-123' }
                                     ))
      expect(tool.masked_auth_headers).to eq({ 'token' => '••••••••' })
    end

    it 'returns masked auth_headers for basic auth_type' do
      tool = described_class.create!(valid_attributes.merge(
                                       auth_type: 'basic',
                                       auth_headers: { 'username' => 'admin', 'password' => 'secret-pass' }
                                     ))
      expect(tool.masked_auth_headers).to eq({ 'username' => 'admin', 'password' => '••••••••' })
    end

    it 'returns masked auth_headers for api_key auth_type' do
      tool = described_class.create!(valid_attributes.merge(
                                       auth_type: 'api_key',
                                       auth_headers: { 'header_name' => 'X-API-Key', 'header_value' => 'real-secret-key' }
                                     ))
      expect(tool.masked_auth_headers).to eq({ 'header_name' => 'X-API-Key', 'header_value' => '••••••••' })
    end

    it 'preserves existing secrets when updating with masked values' do
      tool = described_class.create!(valid_attributes.merge(
                                       auth_type: 'bearer',
                                       auth_headers: { 'token' => 'real-token-123' }
                                     ))

      tool.apply_credentials_update({ 'token' => '••••••••' })
      tool.save!

      expect(tool.parsed_auth_headers).to eq({ 'token' => 'real-token-123' })
    end
  end

  describe '#format_response (User Story 3)' do
    it 'renders response_template when present with response and r aliases' do
      tool = described_class.new(valid_attributes.merge(response_template: 'City {{ r.city }} has {{ response.temp }}C.'))
      formatted = tool.format_response({ city: 'Tokyo', temp: 22 }.to_json)
      expect(formatted).to eq('City Tokyo has 22C.')
    end

    it 'returns parsed JSON when response_template is blank' do
      tool = described_class.new(valid_attributes.merge(response_template: nil))
      formatted = tool.format_response({ city: 'Tokyo' }.to_json)
      expect(formatted).to eq({ 'city' => 'Tokyo' })
    end

    it 'raises when template references missing variable in strict mode' do
      tool = described_class.new(valid_attributes.merge(response_template: 'City {{ r.missing }}'))
      expect do
        tool.format_response({ city: 'Tokyo' }.to_json)
      end.to raise_error(/Template rendering failed/)
    end
  end
end
