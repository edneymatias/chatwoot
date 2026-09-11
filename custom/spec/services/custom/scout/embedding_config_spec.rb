# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::EmbeddingConfig do
  before do
    ActiveRecord::Encryption.config.primary_key = 'test-primary-key-32-chars-length'
    ActiveRecord::Encryption.config.deterministic_key = 'test-determ-key-32-chars-length!'
    ActiveRecord::Encryption.config.key_derivation_salt = 'test-derivation-salt-32-chars!'
    ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)
  end

  let(:account) { create(:account) }
  let(:fake_context) { instance_double(RubyLLM::Context) }
  let(:fake_embedding) { instance_double(RubyLLM::Embedding, vectors: Array.new(768, 0.05)) }

  describe '#supported?' do
    it 'returns false when no ScoutAccountConfig exists' do
      config = described_class.for(account)
      expect(config.supported?).to be(false)
    end

    it 'returns true when ScoutAccountConfig is configured for gemini' do
      ScoutAccountConfig.create!(
        account: account,
        provider: :gemini,
        model_name: 'gemini-2.5-flash',
        api_key: 'test-key'
      )
      config = described_class.for(account)
      expect(config.supported?).to be(true)
    end

    it 'returns true when ScoutAccountConfig is configured for openai' do
      ScoutAccountConfig.create!(
        account: account,
        provider: :openai,
        model_name: 'gpt-4o-mini',
        api_key: 'test-key'
      )
      config = described_class.for(account)
      expect(config.supported?).to be(true)
    end
  end

  describe '#embed' do
    it 'returns empty array when text is blank' do
      config = described_class.for(account)
      expect(config.embed('')).to eq([])
    end

    context 'with gemini provider' do
      before do
        ScoutAccountConfig.create!(
          account: account,
          provider: :gemini,
          model_name: 'gemini-2.5-flash',
          api_key: 'test-gemini-key'
        )
      end

      it 'calls context.embed with text-embedding-004 and returns vectors' do
        fake_config = instance_double(RubyLLM::Configuration, :gemini_api_key= => nil)
        allow(RubyLLM).to receive(:context).and_yield(fake_config).and_return(fake_context)
        allow(fake_context).to receive(:embed).with('Sample text', model: 'text-embedding-004').and_return(fake_embedding)

        service = described_class.for(account)
        vectors = service.embed('Sample text')

        expect(vectors.length).to eq(768)
        expect(fake_context).to have_received(:embed).with('Sample text', model: 'text-embedding-004')
      end
    end

    context 'with openai provider' do
      before do
        ScoutAccountConfig.create!(
          account: account,
          provider: :openai,
          model_name: 'gpt-4o-mini',
          api_key: 'test-openai-key'
        )
      end

      it 'calls context.embed with text-embedding-3-small, dimensions: 768 and returns vectors' do
        fake_config = instance_double(RubyLLM::Configuration, :openai_api_key= => nil)
        allow(RubyLLM).to receive(:context).and_yield(fake_config).and_return(fake_context)
        allow(fake_context).to receive(:embed).with('Sample text', model: 'text-embedding-3-small', dimensions: 768).and_return(fake_embedding)

        service = described_class.for(account)
        vectors = service.embed('Sample text')

        expect(vectors.length).to eq(768)
        expect(fake_context).to have_received(:embed).with('Sample text', model: 'text-embedding-3-small', dimensions: 768)
      end
    end

    it 'rescues errors and returns empty array' do
      ScoutAccountConfig.create!(
        account: account,
        provider: :gemini,
        model_name: 'gemini-2.5-flash',
        api_key: 'test-gemini-key'
      )
      allow(RubyLLM).to receive(:context).and_raise(StandardError.new('API Error'))

      service = described_class.for(account)
      expect(service.embed('Sample text')).to eq([])
    end
  end
end
