# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::ActionClassifierService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Auditor Scout',
      enabled: true,
      feature_response_auditor: true
    )
  end
  let(:service) { described_class.new(scout: scout, conversation: conversation) }

  let(:message_history) do
    [
      { role: 'user', content: 'Quero falar com um humano agora por favor.' }
    ]
  end

  let(:fake_chat) { instance_double(RubyLLM::Chat) }
  let(:fake_response) do
    instance_double(
      RubyLLM::Message,
      content: { 'action' => 'handoff', 'action_reason' => 'explicit_human_request' }.to_json
    )
  end

  before do
    ActiveRecord::Encryption.config.primary_key = 'test-primary-key-32-chars-length'
    ActiveRecord::Encryption.config.deterministic_key = 'test-determ-key-32-chars-length!'
    ActiveRecord::Encryption.config.key_derivation_salt = 'test-derivation-salt-32-chars!'
    ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)

    allow(scout).to receive(:llm_chat).with(temperature: 0.0).and_return(fake_chat)
    allow(fake_chat).to receive(:with_schema).with(Custom::Scout::ActionClassifierSchema).and_return(fake_chat)
    allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
    allow(fake_chat).to receive(:ask).and_return(fake_response)
  end

  describe '#classify' do
    it 'calls llm_chat with temperature 0.0 and schema, returning normalized action and action_reason' do
      expect(scout).to receive(:llm_chat).with(temperature: 0.0).and_return(fake_chat)
      expect(fake_chat).to receive(:with_schema).with(Custom::Scout::ActionClassifierSchema).and_return(fake_chat)
      expect(fake_chat).to receive(:ask) do |prompt|
        expect(prompt).to include('Quero falar com um humano')
        fake_response
      end

      result = service.classify(message_history: message_history)

      expect(result['action']).to eq('handoff')
      expect(result['action_reason']).to eq('explicit_human_request')
    end

    it 'normalizes continue response with omitted action_reason correctly' do
      continue_response = instance_double(RubyLLM::Message, content: { 'action' => 'continue' }.to_json)
      allow(fake_chat).to receive(:ask).and_return(continue_response)

      result = service.classify(message_history: [{ role: 'user', content: 'Qual o horário de atendimento?' }])

      expect(result['action']).to eq('continue')
      expect(result['action_reason']).to be_nil
      expect(result['error']).to be_nil
    end

    it 'instruments the LLM call via instrument_llm_call' do
      expect(service).to receive(:instrument_llm_call).and_call_original

      service.classify(message_history: message_history)
    end

    it 'rescues StandardError, captures exception, logs warning, and returns a sentinel hash' do
      allow(fake_chat).to receive(:ask).and_raise(StandardError, 'LLM API error')
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
      expect(tracker).to receive(:capture_exception).at_least(:once)
      expect(Rails.logger).to receive(:warn).with(/ActionClassifier/)

      result = service.classify(message_history: message_history)

      expect(result['action']).to be_nil
      expect(result['action_reason']).to be_nil
      expect(result['error']).to eq('LLM API error')
    end
  end
end
