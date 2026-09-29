# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Exits::ExitTool do
  subject(:tool) { described_class.new(scout, conversation, declaration: declaration, scope: scope) }

  let(:account) { create(:account) }
  let(:handover_team) { create(:team, account: account, name: 'Suporte') }
  let(:scout) { Scout.create!(account: account, name: 'Qualifier', handover_team_id: handover_team.id) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :pending).reload }
  let(:chat) { scout.llm_chat }
  let(:catalog) { Custom::ScoutV2::Playbook::Catalog.new([]) }
  let(:tool_wrapper) { ->(t) { Object.new.extend(Custom::Scout::Tools::CallRecorder).wrap_tool(t, simulated: false) } }
  let(:scope) do
    Custom::ScoutV2::TurnScope.new(
      chat: chat,
      catalog: catalog,
      baseline_instructions: 'BASELINE',
      tool_wrapper: tool_wrapper,
      playground: false
    )
  end
  let(:declaration) { Custom::ScoutV2::Playbook::ExitDeclaration::HANDOFF }

  before do
    account.enable_features!('scout', 'scout_v2', 'opportunities')
    ScoutAccountConfig.create!(account_id: account.id, api_key: 'test-key', model_name: 'gemini-2.0-flash')
    ctx = Custom::ScoutV2::RoutingSnapshot::Builder.call(conversation: conversation, catalog: catalog)
    decision = Custom::ScoutV2::Router.call(ctx, catalog)
    scope.setup_initial_tools!(
      decision: decision,
      ctx: ctx,
      scout: scout,
      conversation: conversation,
      openable: []
    )
  end

  describe '#name' do
    it 'returns exit_handoff for the built-in exit' do
      expect(tool.name).to eq('exit_handoff')
    end
  end

  describe '#description' do
    it 'returns the built-in exit description' do
      expect(tool.description).to eq('Transfere a conversa para atendimento humano. Informe o motivo da transferência.')
    end
  end

  describe '#params_schema' do
    it 'returns parameters object with reason required' do
      expect(tool.params_schema).to eq(
        type: 'object',
        properties: { 'reason' => { type: 'string' } },
        required: ['reason']
      )
    end
  end

  describe '#execute' do
    context 'with invalid payload' do
      it 'returns an error hash and writes no records when reason is blank' do
        result = tool.execute(reason: '   ')

        expect(result[:error]).to include("Dados inválidos para exit_handoff: campo 'reason' deve ser string")
        expect(conversation.reload.status).to eq('pending')
        expect(conversation.messages.where(private: true)).to be_empty
        expect(ScoutConversationState.where(conversation_id: conversation.id)).to be_empty
        expect(scope.ended?).to be false
        expect(scope.escalated?).to be false
      end

      it 'returns an error hash and writes no records when reason is missing' do
        result = tool.execute

        expect(result[:error]).to include("Dados inválidos para exit_handoff: campo 'reason' ausente")
        expect(conversation.reload.status).to eq('pending')
        expect(scope.ended?).to be false
      end
    end

    context 'with valid payload on inbox' do
      it 'transfers under row lock, creates private note, records terminal exit and ends turn', :aggregate_failures do
        result = tool.execute(reason: 'Cliente solicitou atendente humano')

        closing_instruction = 'Escreva agora sua resposta final ao cliente: uma mensagem natural de encerramento, ' \
                              'sem perguntas, informando que um atendente humano dará continuidade ao atendimento.'
        expect(result).to include('Transferência para atendimento humano realizada.')
        expect(result).to include(closing_instruction)
        expect(result.scan(closing_instruction).count).to eq(1)

        expect(conversation.reload.status).to eq('open')
        expect(conversation.team_id).to eq(handover_team.id)

        note = conversation.messages.where(private: true).last
        expect(note).to be_present
        expect(note.content).to include('📋 Transferência para atendimento humano: Cliente solicitou atendente humano')

        state = ScoutConversationState.for_conversation(conversation)
        expect(state.last_exit).to eq('handoff')
        expect(state.active_playbook).to be_nil

        expect(scope.ended?).to be true
        expect(scope.escalated?).to be true
      end
    end

    context 'when conversation is not pending' do
      it 'refuses escalation and makes no writes' do
        conversation.update!(status: :open)

        result = tool.execute(reason: 'Cliente solicitou atendente')

        expect(result[:error]).to eq(
          'A transferência não aconteceu e o estágio não foi alterado: a conversa não está mais aos cuidados do assistente.'
        )
        expect(ScoutConversationState.where(conversation_id: conversation.id)).to be_empty
        expect(scope.ended?).to be false
        expect(scope.escalated?).to be false
      end
    end

    context 'with declared terminal exit' do
      let(:declaration) do
        Custom::ScoutV2::Playbook::ExitDeclaration.new(
          name: 'concluido',
          kind: 'terminal',
          fields: { 'resumo' => 'string' }
        )
      end

      it 'returns exit_concluido name and Portuguese description' do
        expect(tool.name).to eq('exit_concluido')
        expect(tool.description).to eq("Registra que o procedimento atual terminou com o desfecho 'concluido'.")
      end

      it 'returns nil for params_schema when no fields are declared' do
        empty_decl = Custom::ScoutV2::Playbook::ExitDeclaration.new(name: 'fim', kind: 'terminal', fields: {})
        empty_tool = described_class.new(scout, conversation, declaration: empty_decl, scope: scope)
        expect(empty_tool.params_schema).to be_nil
      end

      it 'records terminal exit, ends turn without escalation, and returns TERMINAL_RESULT without CLOSING_INSTRUCTION' do
        result = tool.execute(resumo: 'Atendimento finalizado com sucesso')

        expect(result).to eq("Desfecho 'concluido' registrado. Escreva agora sua resposta final ao cliente.")
        expect(result).not_to include('sem perguntas')
        expect(result).not_to include('encerramento')

        state = ScoutConversationState.for_conversation(conversation)
        expect(state.last_exit).to eq('concluido')
        expect(scope.ended?).to be true
        expect(scope.escalated?).to be false
      end
    end

    context 'with declared transition exit' do
      let(:target_playbook) do
        Custom::ScoutV2::Playbook.new(
          name: 'outro_procedimento',
          title: 'Outro Procedimento',
          priority: 30,
          trigger: 'Seguir para outro fluxo',
          body: "## Passos do outro\n1. Siga os passos.",
          file_path: '/path/outro.md'
        )
      end
      let(:catalog) { Custom::ScoutV2::Playbook::Catalog.new([target_playbook]) }
      let(:declaration) do
        Custom::ScoutV2::Playbook::ExitDeclaration.new(
          name: 'seguir_outro',
          kind: 'transition',
          target: 'outro_procedimento'
        )
      end

      it 'returns exit_seguir_outro name and transition description' do
        expect(tool.name).to eq('exit_seguir_outro')
        expect(tool.description).to eq("Encerra o procedimento atual e passa para o procedimento 'outro_procedimento'.")
      end

      it 'records transition, updates scope transitions, replaces tools with target, and returns target body without CLOSING_INSTRUCTION' do
        result = tool.execute

        expect(result).to eq("## Passos do outro\n1. Siga os passos.")
        expect(result).not_to include('sem perguntas')

        state = ScoutConversationState.for_conversation(conversation)
        expect(state.active_playbook).to eq('outro_procedimento')
        expect(state.transition_count).to eq(1)

        expect(scope.ended?).to be false
        expect(scope.transitions).to eq(1)
      end

      it 'returns TRANSITION_LIMIT_ERROR and sets handoff_limit_reached_at on the third transition' do
        scope.record_transition!
        scope.record_transition!

        result = tool.execute

        expect(result[:error]).to eq(
          "A transição para 'outro_procedimento' não aconteceu: limite de transições deste turno atingido. Responda ao cliente agora."
        )
        state = ScoutConversationState.for_conversation(conversation)
        expect(state.handoff_limit_reached_at).to be_present
        expect(scope.ended?).to be false
      end
    end

    context 'with declared escalation exit' do
      let(:declaration) do
        Custom::ScoutV2::Playbook::ExitDeclaration.new(
          name: 'qualificado',
          kind: 'escalation',
          fields: { 'motivo' => 'string', 'prazo' => 'datetime' }
        )
      end

      it 'returns description and params_schema with date-time format' do
        expect(tool.description).to eq("Transfere a conversa para atendimento humano (desfecho 'qualificado').")
        expect(tool.params_schema[:properties]['prazo']).to eq(type: 'string', format: 'date-time')
      end

      it 'transfers with note reason formatted in declaration order and sets last_exit' do
        result = tool.execute(prazo: '2026-10-01T10:00:00Z', motivo: 'Interesse confirmado')

        expect(result).to include('Transferência para atendimento humano realizada.')
        expect(result).to include('Escreva agora sua resposta final ao cliente')

        note = conversation.messages.where(private: true).last
        expected_note = '📋 Transferência para atendimento humano: ' \
                        'qualificado (motivo: Interesse confirmado; prazo: 2026-10-01T10:00:00Z)'
        expect(note.content).to include(expected_note)
        state = ScoutConversationState.for_conversation(conversation)
        expect(state.last_exit).to eq('qualificado')
        expect(scope.ended?).to be true
        expect(scope.escalated?).to be true
      end
    end
  end
end
