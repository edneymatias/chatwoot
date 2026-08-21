# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScoutAccountConfig, type: :model do
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
      provider: :gemini,
      model_name: 'gemini-2.5-flash',
      api_key: 'test-gemini-api-key'
    }
  end

  describe 'associations' do
    it 'belongs to account' do
      config = described_class.new(valid_attributes)
      expect(config.account).to eq(account)
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(described_class.new(valid_attributes)).to be_valid
    end

    it 'validates presence of account' do
      config = described_class.new(valid_attributes.merge(account: nil))
      expect(config).not_to be_valid
      expect(config.errors[:account]).to be_present
    end

    it 'validates presence of provider' do
      config = described_class.new(valid_attributes.merge(provider: nil))
      expect(config).not_to be_valid
      expect(config.errors[:provider]).to include("can't be blank")
    end

    it 'validates presence of model_name' do
      config = described_class.new(valid_attributes.merge(model_name: nil))
      expect(config).not_to be_valid
      expect(config.errors[:model_name]).to include("can't be blank")
    end

    it 'validates presence of api_key' do
      config = described_class.new(valid_attributes.merge(api_key: nil))
      expect(config).not_to be_valid
      expect(config.errors[:api_key]).to include("can't be blank")
    end

    it 'enforces uniqueness of account_id' do
      described_class.create!(valid_attributes)
      duplicate = described_class.new(valid_attributes)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:account_id]).to include('has already been taken')
    end

    it 'defines provider enum with gemini, openai, anthropic' do
      expect(described_class.providers).to eq({ 'gemini' => 0, 'openai' => 1, 'anthropic' => 2 })
    end
  end

  describe 'encryption at rest' do
    it 'encrypts api_key unconditionally' do
      config = described_class.create!(valid_attributes)

      raw_stored = config.reload.read_attribute_before_type_cast(:api_key).to_s
      expect(raw_stored).to be_present
      expect(raw_stored).not_to include('test-gemini-api-key')
      expect(config.api_key).to eq('test-gemini-api-key')
      expect(config.encrypted_attribute?(:api_key)).to be(true)
    end

    it 'fails closed when encryption keys are not configured' do
      ActiveRecord::Encryption.config.primary_key = nil
      ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)

      expect do
        described_class.create!(valid_attributes)
      end.to raise_error(ActiveRecord::Encryption::Errors::Configuration)
    ensure
      ActiveRecord::Encryption.config.primary_key = 'test-primary-key-32-chars-length'
      ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)
    end
  end

  describe '#validate_credentials!' do
    let(:config) { described_class.new(valid_attributes) }
    let(:fake_context) { instance_double(RubyLLM::Context) }
    let(:fake_chat) { instance_double(RubyLLM::Chat) }

    it 'returns true when probe succeeds' do
      allow(RubyLLM).to receive(:context).and_yield(instance_double(RubyLLM::Configuration, :gemini_api_key= => nil)).and_return(fake_context)
      allow(fake_context).to receive(:chat).with(model: 'gemini-2.5-flash').and_return(fake_chat)
      allow(fake_chat).to receive(:ask).with('ping').and_return(instance_double(RubyLLM::Message, content: 'pong'))

      expect(config.validate_credentials!).to be(true)
      expect(config.errors).to be_empty
    end

    it 'adds error on unauthorized error' do
      allow(RubyLLM).to receive(:context).and_yield(instance_double(RubyLLM::Configuration, :gemini_api_key= => nil)).and_return(fake_context)
      allow(fake_context).to receive(:chat).with(model: 'gemini-2.5-flash').and_return(fake_chat)
      allow(fake_chat).to receive(:ask).with('ping').and_raise(RubyLLM::UnauthorizedError.new('Invalid Key', response: nil))

      expect(config.validate_credentials!).to be(false)
      expect(config.errors[:api_key]).to be_present
    end
  end
end
