# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Tools::OpenPlaybook do
  subject(:tool) do
    described_class.new(
      scout,
      conversation,
      chat: fake_chat,
      catalog: catalog,
      tool_wrapper: tool_wrapper
    )
  end

  let(:account) { create(:account) }
  let(:scout) { Scout.create!(account: account, name: 'Qualifier') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  let(:playbook1) do
    Custom::ScoutV2::Playbook.new(
      name: 'duvida_comercial',
      title: 'Dúvidas Comerciais',
      trigger: 'Quando o cliente tem dúvidas sobre planos e preços.',
      priority: 1,
      when_state: [],
      requires: [],
      needs: [],
      tools: ['manage_opportunity'],
      exits: {},
      body: "## Passos\n1. Esclareça as dúvidas do cliente.",
      file_path: '/dummy/duvida_comercial.md',
      load_errors: []
    )
  end

  let(:playbook2) do
    Custom::ScoutV2::Playbook.new(
      name: 'qualificacao',
      title: 'Qualificação',
      trigger: 'Quando o cliente quer comprar.',
      priority: 2,
      when_state: [],
      requires: [],
      needs: [],
      tools: [],
      exits: {},
      body: "## Passos\n1. Qualifique o cliente.",
      file_path: '/dummy/qualificacao.md',
      load_errors: []
    )
  end

  let(:catalog) { Custom::ScoutV2::Playbook::Catalog.new([playbook1, playbook2]) }
  let(:fake_chat) { instance_double(RubyLLM::Chat, with_tool: nil) }
  let(:wrapped_tools) { [] }
  let(:tool_wrapper) do
    lambda do |t|
      wrapped_tools << t
      t
    end
  end

  describe '#name' do
    it 'returns open_playbook' do
      expect(tool.name).to eq('open_playbook')
    end
  end

  describe '#execute' do
    context 'when playbook name exists in catalog' do
      it 'returns the full markdown body of the playbook' do
        result = tool.execute(name: 'duvida_comercial')
        expect(result).to eq({ body: playbook1.body })
      end

      it 'persists active_playbook and activation_reason = :trigger on ScoutConversationState' do
        freeze_time do
          tool.execute(name: 'duvida_comercial')

          state = ScoutConversationState.for_conversation(conversation)
          expect(state.active_playbook).to eq('duvida_comercial')
          expect(state.activation_reason).to eq('trigger')
          expect(state.activated_at).to eq(Time.current)
          expect(state.trigger?).to be true
        end
      end

      it 'injects declared tools into live chat and wraps them' do
        allow(fake_chat).to receive(:with_tool).and_return(fake_chat)

        tool.execute(name: 'duvida_comercial')

        expect(wrapped_tools.size).to eq(1)
        expect(wrapped_tools.first).to be_a(Custom::Scout::Tools::ManageOpportunity)
        expect(fake_chat).to have_received(:with_tool).with(an_instance_of(Custom::Scout::Tools::ManageOpportunity))
      end
    end

    context 'when playbook name is unknown' do
      it 'returns error hash without raising, without injecting tools, and without mutating state' do
        result = tool.execute(name: 'inexistente')

        expect(result[:error]).to include('Playbook desconhecida: inexistente')
        expect(result[:error]).to include('Disponíveis: duvida_comercial, qualificacao')
        expect(wrapped_tools).to be_empty
        expect(fake_chat).not_to have_received(:with_tool)

        state = ScoutConversationState.for_conversation(conversation)
        expect(state.active_playbook).to be_nil
        expect(state.activation_reason).to be_nil
      end
    end
  end
end
