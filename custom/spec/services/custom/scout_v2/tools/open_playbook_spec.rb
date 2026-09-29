# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Tools::OpenPlaybook do
  subject(:tool) do
    described_class.new(
      scout,
      conversation,
      openable: openable,
      scope: scope
    )
  end

  let(:account) { create(:account) }
  let(:scout) { Scout.create!(account: account, name: 'Qualifier') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  let(:pausa) do
    Custom::ScoutV2::Playbook.new(
      name: 'pausa',
      title: 'Pausa solicitada',
      trigger: 'O cliente pede para pausar ou continuar a conversa mais tarde.',
      priority: 20,
      when_state: [],
      requires: [],
      needs: [],
      tools: [],
      exits: {},
      body: "## Passos\n1. Confirme a pausa com gentileza.",
      file_path: '/dummy/pausa.md',
      load_errors: []
    )
  end

  let(:duvida_comercial) do
    Custom::ScoutV2::Playbook.new(
      name: 'duvida_comercial',
      title: 'Dúvidas Comerciais',
      trigger: 'O cliente tem dúvidas sobre preços, planos ou serviços comerciais.',
      priority: 5,
      when_state: [],
      requires: [],
      needs: [],
      tools: ['manage_opportunity'],
      exits: {},
      body: "## Passos\n1. Esclareça as dúvidas comerciais do cliente.",
      file_path: '/dummy/duvida_comercial.md',
      load_errors: []
    )
  end

  let(:qualificacao) do
    Custom::ScoutV2::Playbook.new(
      name: 'qualificacao',
      title: 'Qualificação',
      trigger: 'Quando o cliente quer comprar.',
      priority: 10,
      when_state: [['opportunity_open', nil]],
      requires: [],
      needs: [],
      tools: ['manage_opportunity'],
      exits: {},
      body: "## Passos\n1. Qualifique o cliente.",
      file_path: '/dummy/qualificacao.md',
      load_errors: []
    )
  end

  let(:openable) { Custom::ScoutV2::Playbook::Catalog.new([pausa, duvida_comercial, qualificacao]) }
  let(:baseline_instructions) { 'BASELINE' }
  let(:baseline_tools) { [Custom::Scout::Tools::SearchKnowledgeBase.new(scout, conversation, playground: false)] }
  let(:tool_wrapper) { ->(t) { Object.new.extend(Custom::Scout::Tools::CallRecorder).wrap_tool(t, simulated: false) } }
  let(:chat) { scout.llm_chat }
  let(:scope) do
    Custom::ScoutV2::TurnScope.new(
      chat: chat,
      catalog: openable,
      baseline_instructions: baseline_instructions,
      tool_wrapper: tool_wrapper
    )
  end

  before do
    account.enable_features!('scout', 'scout_v2', 'opportunities')
    ScoutAccountConfig.create!(account_id: account.id, api_key: 'test-key', model_name: 'gemini-2.0-flash')
    ctx = Custom::ScoutV2::RoutingSnapshot::Builder.call(conversation: conversation, catalog: openable)
    decision = Custom::ScoutV2::Router.call(ctx, openable)
    scope.setup_initial_tools!(
      decision: decision,
      ctx: ctx,
      scout: scout,
      conversation: conversation,
      openable: openable.playbooks
    )
  end

  describe '#name' do
    it 'returns open_playbook' do
      expect(tool.name).to eq('open_playbook')
    end
  end

  describe '#execute' do
    context 'when a procedure is pinned' do
      before do
        ScoutConversationState.for_conversation(conversation).record_state_activation!('qualificacao')
        chat.with_instructions('PROCEDURE BODY')
        baseline_tools.each { |t| chat.with_tool(tool_wrapper.call(t)) }
        chat.with_tool(tool)
        chat.with_tool(tool_wrapper.call(Custom::Scout::Tools::ManageOpportunity.new(scout, conversation)))
      end

      it 'returns error hash when playbook name is unknown without mutating state, tools, or instructions' do
        result = tool.execute(name: 'inexistente')

        expect(result[:error]).to include('Playbook desconhecida: inexistente')
        expect(result[:error]).to include('Disponíveis: pausa, duvida_comercial, qualificacao')
        expect(chat.tools.keys).to contain_exactly(:search_knowledge_base, :open_playbook, :manage_opportunity, :exit_handoff)
        expect(chat.messages.first.content.to_s).to eq('PROCEDURE BODY')
        state = ScoutConversationState.for_conversation(conversation)
        expect(state.active_playbook).to eq('qualificacao')
        expect(state.activation_reason).to eq('state')
      end

      context 'when the openable set contains only situational playbooks' do
        let(:openable) { Custom::ScoutV2::Playbook::Catalog.new([duvida_comercial, pausa]) }

        it 'rejects a procedure playbook name as outside the openable set without mutating state, tools, or instructions' do
          result = tool.execute(name: 'qualificacao')

          expect(result).to eq(
            error: 'Playbook desconhecida: qualificacao. Disponíveis: duvida_comercial, pausa'
          )
          expect(chat.tools.keys).to contain_exactly(:search_knowledge_base, :open_playbook, :manage_opportunity, :exit_handoff)
          expect(chat.messages.first.content.to_s).to eq('PROCEDURE BODY')

          state = ScoutConversationState.for_conversation(conversation)
          expect(state.active_playbook).to eq('qualificacao')
          expect(state.activation_reason).to eq('state')
        end
      end

      it 'takes over the turn for situational playbook without tools, replacing instructions and tools without state mutation' do
        state = ScoutConversationState.for_conversation(conversation)
        initial_state_attributes = state.attributes.dup

        result = tool.execute(name: 'pausa')

        expect(result).to eq({ body: pausa.body })
        expect(chat.messages.first.content.to_s).to eq(baseline_instructions)
        expect(chat.tools.keys).to contain_exactly(:search_knowledge_base, :open_playbook, :exit_handoff)
        expect(state.reload.attributes).to eq(initial_state_attributes)
      end

      it 'takes over the turn for situational playbook with declared tools, replacing instructions and tools without state mutation' do
        state = ScoutConversationState.for_conversation(conversation)
        initial_state_attributes = state.attributes.dup
        initial_procedure_tool = chat.tools[:manage_opportunity]
        result = tool.execute(name: 'duvida_comercial')

        expect(result).to eq({ body: duvida_comercial.body })
        expect(chat.messages.first.content.to_s).to eq(baseline_instructions)
        expect(chat.tools.keys).to contain_exactly(:search_knowledge_base, :open_playbook, :manage_opportunity, :exit_handoff)
        expect(chat.tools[:manage_opportunity]).to be_a(Custom::Scout::Tools::ManageOpportunity)
        expect(chat.tools[:manage_opportunity]).not_to equal(initial_procedure_tool)
        expect(state.reload.attributes).to eq(initial_state_attributes)
      end

      it 'returns the body for each consecutive takeover including immediate re-opening' do
        expect(tool.execute(name: 'pausa')).to eq({ body: pausa.body })
        expect(tool.execute(name: 'duvida_comercial')).to eq({ body: duvida_comercial.body })
        expect(tool.execute(name: 'pausa')).to eq({ body: pausa.body })
        expect(tool.execute(name: 'pausa')).to eq({ body: pausa.body })
      end

      it 'updates available tools on each consecutive takeover without accumulation' do
        tool.execute(name: 'pausa')
        expect(chat.tools.keys).to contain_exactly(:search_knowledge_base, :open_playbook, :exit_handoff)

        tool.execute(name: 'duvida_comercial')
        expect(chat.tools.keys).to contain_exactly(:search_knowledge_base, :open_playbook, :manage_opportunity, :exit_handoff)

        tool.execute(name: 'pausa')
        expect(chat.tools.keys).to contain_exactly(:search_knowledge_base, :open_playbook, :exit_handoff)

        tool.execute(name: 'pausa')
        expect(chat.tools.keys).to contain_exactly(:search_knowledge_base, :open_playbook, :exit_handoff)
      end
    end

    context 'when nothing is pinned' do
      before do
        chat.with_instructions('INITIAL')
        baseline_tools.each { |t| chat.with_tool(tool_wrapper.call(t)) }
        chat.with_tool(tool)
      end

      it 'returns the full markdown body of the playbook' do
        result = tool.execute(name: 'duvida_comercial')
        expect(result).to eq({ body: duvida_comercial.body })
      end

      it 'takes over the turn for situational playbook without creating a conversation state row' do
        result = tool.execute(name: 'pausa')

        expect(result).to eq({ body: pausa.body })
        expect(chat.messages.first.content.to_s).to eq(baseline_instructions)
        expect(chat.tools.keys).to contain_exactly(:search_knowledge_base, :open_playbook, :exit_handoff)
        expect(ScoutConversationState.where(conversation_id: conversation.id)).to be_empty
      end

      it 'activates procedure playbook additively and persists trigger activation' do
        freeze_time do
          result = tool.execute(name: 'qualificacao')

          expect(result).to eq({ body: qualificacao.body })
          expect(chat.messages.first.content.to_s).to eq('INITIAL')
          expect(chat.tools.keys).to contain_exactly(:search_knowledge_base, :open_playbook, :manage_opportunity, :exit_handoff)

          state = ScoutConversationState.for_conversation(conversation)
          expect(state.active_playbook).to eq('qualificacao')
          expect(state.activation_reason).to eq('trigger')
          expect(state.activated_at).to eq(Time.current)
        end
      end

      it 'preserves Path B state activation when followed by Path A situational takeover, but replaces tools' do
        tool.execute(name: 'qualificacao')
        tool.execute(name: 'pausa')

        expect(chat.tools.keys).to contain_exactly(:search_knowledge_base, :open_playbook, :exit_handoff)
        state = ScoutConversationState.for_conversation(conversation)
        expect(state.active_playbook).to eq('qualificacao')
        expect(state.activation_reason).to eq('trigger')
      end

      it 'allows Path B procedure activation after Path A situational takeover, persisting trigger activation and adding tools additively' do
        tool.execute(name: 'pausa')
        tool.execute(name: 'qualificacao')

        expect(chat.tools.keys).to contain_exactly(:search_knowledge_base, :open_playbook, :manage_opportunity, :exit_handoff)
        state = ScoutConversationState.for_conversation(conversation)
        expect(state.active_playbook).to eq('qualificacao')
        expect(state.activation_reason).to eq('trigger')
      end

      it 'returns error hash when playbook name is unknown without mutating state, tools, or instructions' do
        result = tool.execute(name: 'inexistente')

        expect(result[:error]).to include('Playbook desconhecida: inexistente')
        expect(result[:error]).to include('Disponíveis: pausa, duvida_comercial, qualificacao')
        expect(chat.tools.keys).to contain_exactly(:search_knowledge_base, :open_playbook, :exit_handoff)
        expect(chat.messages.first.content.to_s).to eq('INITIAL')
        state = ScoutConversationState.for_conversation(conversation)
        expect(state.active_playbook).to be_nil
        expect(state.activation_reason).to be_nil
      end
    end
  end
end
