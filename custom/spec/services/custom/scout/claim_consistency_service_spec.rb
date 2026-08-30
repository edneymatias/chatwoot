# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::ClaimConsistencyService do
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
      { role: 'user', content: 'Pode atualizar meu interesse para Enterprise?' },
      { role: 'assistant', content: 'Vou atualizar agora.' }
    ]
  end
  let(:assistant_response) { 'Já atualizei sua oportunidade para Enterprise com sucesso!' }
  let(:recorded_tool_calls) do
    [
      { tool_name: 'manage_opportunity', arguments: { value: 10_000 }, simulated: false, result: { success: true } }
    ]
  end

  let(:fake_chat) { instance_double(RubyLLM::Chat) }
  let(:fake_response) { instance_double(RubyLLM::Message, content: { 'decision' => 'safe', 'reason' => 'Tool call matched update' }.to_json) }

  before do
    ActiveRecord::Encryption.config.primary_key = 'test-primary-key-32-chars-length'
    ActiveRecord::Encryption.config.deterministic_key = 'test-determ-key-32-chars-length!'
    ActiveRecord::Encryption.config.key_derivation_salt = 'test-derivation-salt-32-chars!'
    ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)

    allow(scout).to receive(:llm_chat).with(temperature: 0.0).and_return(fake_chat)
    allow(fake_chat).to receive(:with_schema).with(Custom::Scout::ClaimConsistencySchema).and_return(fake_chat)
    allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
    allow(fake_chat).to receive(:ask).and_return(fake_response)
  end

  describe '#check' do
    it 'calls llm_chat with temperature 0.0 and schema, returning normalized decision' do
      expect(scout).to receive(:llm_chat).with(temperature: 0.0).and_return(fake_chat)
      expect(fake_chat).to receive(:with_schema).with(Custom::Scout::ClaimConsistencySchema).and_return(fake_chat)
      expect(fake_chat).to receive(:ask) do |prompt|
        expect(prompt).to include('Pode atualizar meu interesse')
        fake_response
      end

      result = service.check(
        message_history: message_history,
        assistant_response: assistant_response,
        recorded_tool_calls: recorded_tool_calls
      )

      expect(result['decision']).to eq('safe')
      expect(result['reason']).to eq('Tool call matched update')
    end

    it 'instruments the LLM call via instrument_llm_call' do
      expect(service).to receive(:instrument_llm_call).and_call_original

      service.check(
        message_history: message_history,
        assistant_response: assistant_response,
        recorded_tool_calls: recorded_tool_calls
      )
    end

    it 'passes recorded tool calls including failures into the prompt' do
      failed_calls = [
        { tool_name: 'move_opportunity_stage', arguments: { stage_id: 1 }, simulated: false, error: 'Stage not found' }
      ]

      expect(fake_chat).to receive(:ask) do |prompt|
        expect(prompt).to include('move_opportunity_stage')
        expect(prompt).to include('Stage not found')
        fake_response
      end

      service.check(
        message_history: message_history,
        assistant_response: assistant_response,
        recorded_tool_calls: failed_calls
      )
    end

    it 'rescues StandardError, captures exception, logs warning, and returns a sentinel hash' do
      allow(fake_chat).to receive(:ask).and_raise(StandardError, 'LLM API timeout')
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
      expect(tracker).to receive(:capture_exception).at_least(:once)
      expect(Rails.logger).to receive(:warn).with(/ClaimConsistency/)

      result = service.check(
        message_history: message_history,
        assistant_response: assistant_response,
        recorded_tool_calls: recorded_tool_calls
      )

      expect(result['decision']).to be_nil
      expect(result['reason']).to be_nil
      expect(result['error']).to eq('LLM API timeout')
    end
  end
end
