# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::AgentRunner do
  before do
    ActiveRecord::Encryption.config.primary_key = 'test-primary-key-32-chars-length'
    ActiveRecord::Encryption.config.deterministic_key = 'test-determ-key-32-chars-length!'
    ActiveRecord::Encryption.config.key_derivation_salt = 'test-derivation-salt-32-chars!'
    ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)
  end

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :pending) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Runner Scout',
      provider: :gemini,
      model_name: 'gemini-2.0-flash',
      api_key_override: 'test-api-key',
      responses_quota: 10,
      responses_consumed: 0,
      enabled: true,
      feature_memory: false
    )
  end
  let(:runner) { described_class.new(scout: scout, conversation: conversation) }

  describe '#perform' do
    let(:fake_chat) { instance_double(RubyLLM::Chat) }
    let(:fake_response) { instance_double(RubyLLM::Message, content: 'Olá! Como posso ajudar você hoje?') }

    before do
      allow(scout).to receive(:llm_chat).and_return(fake_chat)
      allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
      allow(fake_chat).to receive(:with_tool).and_return(fake_chat)
      allow(fake_chat).to receive(:add_message).and_return(fake_chat)
      allow(fake_chat).to receive(:ask).and_return(fake_response)
    end

    context 'when qualifying conversation executes normally' do
      before do
        conversation.messages.create!(
          account: account,
          inbox: inbox,
          sender: contact,
          message_type: :incoming,
          content: 'Quero conhecer os planos'
        )
      end

      it 'dispatches outgoing response and increments responses_consumed' do
        expect do
          runner.perform
        end.to change { scout.reload.responses_consumed }.by(1)

        outgoing = conversation.messages.where(message_type: :outgoing).last
        expect(outgoing).to be_present
        expect(outgoing.content).to eq('Olá! Como posso ajudar você hoje?')
        expect(conversation.reload.status).to eq('pending')
      end

      it 'registers CallCustomApi tool including account enabled tools catalog' do
        account.scout_tools.create!(
          name: 'erp_stock',
          description: 'Lookup ERP stock',
          endpoint_url: 'https://api.example.com/stock',
          http_method: 'POST',
          enabled: true
        )
        expect(fake_chat).to receive(:with_tool).with(an_instance_of(Custom::Scout::Tools::CallCustomApi)) do |tool|
          expect(tool.description).to include('erp_stock')
          expect(tool.description).to include('Lookup ERP stock')
          fake_chat
        end.at_least(:once)

        runner.perform
      end
    end

    context 'when fail-safe pre-call check fails (quota exhausted)' do
      before do
        scout.update!(responses_quota: 0)
      end

      it 'hands over conversation to human with alert note without calling LLM' do
        runner.perform

        expect(conversation.reload.status).to eq('open')
        expect(conversation.messages.where(private: true).last.content).to include('⚠️ [IA Pausada]')
        expect(fake_chat).not_to have_received(:ask)
      end
    end

    context 'when runtime error occurs during LLM execution' do
      before do
        conversation.messages.create!(
          account: account,
          inbox: inbox,
          sender: contact,
          message_type: :incoming,
          content: 'Quero saber mais'
        )
        allow(fake_chat).to receive(:ask).and_raise(StandardError.new('Provider 500'))
      end

      it 'rescues error, triggers fail-safe handoff and alert note' do
        runner.perform

        expect(conversation.reload.status).to eq('open')
        expect(conversation.messages.where(private: true).last.content).to include('⚠️ [IA Pausada]')
      end
    end

    context 'when memory feature is enabled' do
      let(:memory_service) { instance_double(Custom::Scout::ContactNotesService, generate_and_update_notes: []) }

      before do
        scout.update!(feature_memory: true, responses_quota: 0)
        allow(Custom::Scout::ContactNotesService).to receive(:new).and_return(memory_service)
      end

      it 'triggers contact memory generation on fail-safe handoff' do
        runner.perform
        expect(memory_service).to have_received(:generate_and_update_notes)
      end
    end
  end
end
