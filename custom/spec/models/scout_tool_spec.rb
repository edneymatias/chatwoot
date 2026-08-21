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
      auth_headers: 'Bearer secret-token',
      parameter_schema: {
        'type' => 'object',
        'properties' => {
          'city' => { 'type' => 'string' }
        },
        'required' => ['city']
      }
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
  end

  describe 'encryption at rest' do
    it 'encrypts auth_headers unconditionally' do
      tool = described_class.create!(valid_attributes)

      raw_stored = tool.reload.read_attribute_before_type_cast(:auth_headers).to_s
      expect(raw_stored).to be_present
      expect(raw_stored).not_to include('Bearer secret-token')
      expect(tool.auth_headers).to eq('Bearer secret-token')
      expect(tool.encrypted_attribute?(:auth_headers)).to be(true)
    end

    it 'fails closed when encryption keys are not configured' do
      ActiveRecord::Encryption.config.primary_key = nil
      ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)

      expect do
        described_class.create!(valid_attributes.merge(auth_headers: 'unencrypted-secret'))
      end.to raise_error(ActiveRecord::Encryption::Errors::Configuration)
    ensure
      ActiveRecord::Encryption.config.primary_key = 'test-primary-key-32-chars-length'
      ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)
    end
  end

  describe 'lifecycle independence' do
    it 'is not destroyed when a Scout in the same account is destroyed' do
      tool = described_class.create!(valid_attributes)
      scout = Scout.create!(
        account: account,
        name: 'Weather Agent'
      )

      expect { scout.destroy! }.not_to(change { described_class.exists?(tool.id) })
      expect(described_class.find(tool.id)).to eq(tool)
    end
  end
end
