# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::PlaygroundRunner do
  before do
    ActiveRecord::Encryption.config.primary_key = 'test-primary-key-32-chars-length'
    ActiveRecord::Encryption.config.deterministic_key = 'test-determ-key-32-chars-length!'
    ActiveRecord::Encryption.config.key_derivation_salt = 'test-derivation-salt-32-chars!'
    ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)
  end

  let(:account) { create(:account) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Playground Scout',
      persona: 'You are an SDR assistant.',
      responses_quota: 10,
      responses_consumed: 0,
      enabled: true
    )
  end
  let(:runner) { described_class.new(scout: scout, message: 'Olá, gostaria de contratar o plano') }

  describe '#perform' do
    let(:fake_chat) { instance_double(RubyLLM::Chat) }
    let(:fake_response) { instance_double(RubyLLM::Message, content: 'Olá! Perfeito, qual é o seu nome?') }

    before do
      allow(scout).to receive(:llm_chat).and_return(fake_chat)
      allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
      allow(fake_chat).to receive(:with_tool).and_return(fake_chat)
      allow(fake_chat).to receive(:ask).and_return(fake_response)
    end

    it 'executes chat without consuming responses quota and returns simulated response' do
      expect do
        result = runner.perform
        expect(result[:reply]).to eq('Olá! Perfeito, qual é o seu nome?')
        expect(result[:tool_calls]).to be_an(Array)
      end.not_to(change { scout.reload.responses_consumed })
    end
  end
end
