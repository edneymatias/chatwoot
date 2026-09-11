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
  let(:message_history) do
    [
      { role: 'user', content: 'Que dia é hoje?' },
      { role: 'assistant', content: 'Hoje é sexta-feira.' }
    ]
  end
  let(:runner) { described_class.new(scout: scout, message: 'Tem atendimento hoje?', message_history: message_history) }

  describe '#perform' do
    let(:fake_chat) { instance_double(RubyLLM::Chat) }
    let(:fake_response) { instance_double(RubyLLM::Message, content: 'Sim, atendemos hoje!') }

    before do
      allow(scout).to receive(:llm_chat).and_return(fake_chat)
      allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
      allow(fake_chat).to receive(:with_tool).and_return(fake_chat)
      allow(fake_chat).to receive(:add_message).and_return(fake_chat)
      allow(fake_chat).to receive(:ask).and_return(fake_response)
    end

    it 'executes chat without consuming responses quota and returns simulated response' do
      expect(fake_chat).to receive(:with_tool).with(an_instance_of(Custom::Scout::Tools::SearchKnowledgeBase)).at_least(:once)

      expect do
        result = runner.perform
        expect(result[:reply]).to eq('Sim, atendemos hoje!')
        expect(result[:tool_calls]).to be_an(Array)
      end.not_to(change { scout.reload.responses_consumed })
    end

    it 'injects message history into the chat before asking the current message' do
      expect(fake_chat).to receive(:add_message).with(role: :user, content: 'Que dia é hoje?').ordered
      expect(fake_chat).to receive(:add_message).with(role: :assistant, content: 'Hoje é sexta-feira.').ordered
      expect(fake_chat).to receive(:ask).with('Tem atendimento hoje?').ordered.and_return(fake_response)

      runner.perform
    end

    it 'forwards contact to SystemPromptsService when provided' do
      contact = create(:contact, account: account, name: 'empty-meadow-50')
      runner_with_contact = described_class.new(
        scout: scout,
        contact: contact,
        message: 'Olá',
        message_history: []
      )

      expect(Custom::Scout::SystemPromptsService).to receive(:build).with(
        hash_including(scout: scout, contact: contact)
      ).and_call_original

      runner_with_contact.perform
    end

    it 'calls SystemPromptsService with nil contact when contact is omitted' do
      expect(Custom::Scout::SystemPromptsService).to receive(:build).with(
        hash_including(scout: scout, contact: nil)
      ).and_call_original

      runner.perform
    end
  end
end
