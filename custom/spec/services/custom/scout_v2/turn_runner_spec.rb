# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::TurnRunner do
  let(:account) { create(:account) }
  let(:stage) { PipelineStage.create!(account: account, name: 'Lead', position: 0) }
  let(:scout) do
    q_stage = PipelineStage.create!(account: account, name: 'Qualificado', position: 1)
    unq_stage = PipelineStage.create!(account: account, name: 'Desqualificado', position: 2)
    Scout.create!(
      account: account,
      name: 'V2 Qualification Scout',
      default_pipeline_stage: stage,
      qualified_stage: q_stage,
      unqualified_stage: unq_stage
    )
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

  let(:fake_response) { OpenStruct.new(content: 'Qual o seu orçamento disponível?') }
  let(:fake_chat) do
    instance_double(
      RubyLLM::Chat,
      with_instructions: nil,
      with_tool: nil,
      add_message: nil,
      ask: fake_response
    )
  end

  before do
    account.enable_features!('scout', 'scout_v2', 'opportunities')
    ScoutInbox.create!(scout: scout, inbox: inbox)
    ScoutAccountConfig.create!(account_id: account.id, api_key: 'test-key', model_name: 'gemini-2.0-flash')
    allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
    allow(fake_chat).to receive(:with_tool).and_return(fake_chat)
    allow(fake_chat).to receive(:add_message).and_return(fake_chat)
    allow(scout).to receive(:llm_chat).and_return(fake_chat)
  end

  describe '#perform' do
    context 'when an open opportunity has pending required fields (qualificacao matches)' do
      let!(:field) do
        CustomAttributeDefinition.create!(
          account: account,
          attribute_display_name: 'Orçamento',
          attribute_key: 'orcamento',
          attribute_model: :opportunity_attribute,
          attribute_display_type: :text
        )
      end

      before do
        scout.sync_required_attribute_ids!([field.id])
        Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: stage,
          origin_conversation: conversation,
          active_conversation: conversation,
          title: 'Deal 1',
          status: :open
        )
      end

      it 'makes exactly one top-level LLM call per turn attempt' do
        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Olá, gostaria de saber mais',
          message_history: []
        )

        result = runner.perform

        expect(fake_chat).to have_received(:ask).once.with('Olá, gostaria de saber mais')
        expect(result[:reply]).to eq('Qual o seu orçamento disponível?')
        expect(result[:tool_calls]).to be_an(Array)
      end

      it 'assembles the prompt with active playbook body and pending fields' do
        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Olá',
          message_history: []
        )

        runner.perform

        expect(fake_chat).to have_received(:with_instructions) do |instructions|
          expect(instructions).to include('## Passos')
          expect(instructions).to include('Pergunte pelos dados de qualificação pendentes')
          expect(instructions).to include('Campos pendentes para esta oportunidade')
          expect(instructions).to include('Orçamento (chave: orcamento)')
        end
      end

      it 'excludes v1 guardrails and funnel guidelines from prompt' do
        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Olá',
          message_history: []
        )

        runner.perform

        expect(fake_chat).to have_received(:with_instructions) do |instructions|
          expect(instructions).not_to include('DIRETRIZES DE ESTÁGIO E FUNIL')
          expect(instructions).not_to include('DIRETRIZES FUNDAMENTAIS DE COMPORTAMENTO')
          expect(instructions).not_to include('Nunca diga frases como "não tenho acesso"')
        end
      end

      it 'composes the tool catalog with only declared tools plus search_knowledge_base' do
        passed_tools = []
        allow(fake_chat).to receive(:with_tool) do |tool|
          passed_tools << tool
          fake_chat
        end

        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Olá',
          message_history: []
        )

        runner.perform

        tool_names = passed_tools.map(&:name)
        expect(tool_names).to contain_exactly('search_knowledge_base', 'manage_opportunity')
        expect(tool_names).not_to include('move_opportunity_stage', 'handover_to_human', 'call_custom_api')
      end

      it 'persists active_playbook and activation_reason before returning' do
        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Olá',
          message_history: []
        )

        runner.perform

        state = ScoutConversationState.for_conversation(conversation)
        expect(state.active_playbook).to eq('qualificacao')
        expect(state.activation_reason).to eq('state')
        expect(state.activated_at).to be_present
      end
    end

    context 'when no playbook matches (fallback instructions)' do
      it 'uses fallback instructions and provides only search_knowledge_base tool' do
        passed_tools = []
        allow(fake_chat).to receive(:with_tool) do |tool|
          passed_tools << tool
          fake_chat
        end

        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Dúvida geral',
          message_history: []
        )

        runner.perform

        expect(fake_chat).to have_received(:with_instructions) do |instructions|
          expect(instructions).to include('Nenhum procedimento específico está ativo para esta conversa')
          expect(instructions).to include('Responda à mensagem do cliente da melhor forma possível')
        end

        expect(passed_tools.map(&:name)).to contain_exactly('search_knowledge_base')
        expect(ScoutConversationState.for_conversation(conversation).active_playbook).to be_nil
      end
    end

    context 'when infra checks fail (missing API key or quota exhausted)' do
      before do
        ScoutAccountConfig.where(account_id: account.id).destroy_all
      end

      it 'returns error hash in playground mode without making any LLM call' do
        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'oi',
          message_history: []
        )

        result = runner.perform

        expect(fake_chat).not_to have_received(:ask)
        expect(result[:reply]).to include('Erro ao executar simulação')
        expect(result[:error]).to be_present
      end

      it 'triggers HandoffService and makes no LLM call in inbox mode' do
        handoff_service = instance_double(Custom::Scout::HandoffService, perform: true)
        allow(Custom::Scout::HandoffService).to receive(:new).and_return(handoff_service)

        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'oi',
          message_history: nil
        )

        result = runner.perform

        expect(fake_chat).not_to have_received(:ask)
        expect(handoff_service).to have_received(:perform)
        expect(result[:reply]).to be_blank
      end
    end

    describe 'observability and instrumentation (US2)' do
      let!(:field) do
        CustomAttributeDefinition.create!(
          account: account,
          attribute_display_name: 'Orçamento',
          attribute_key: 'orcamento',
          attribute_model: :opportunity_attribute,
          attribute_display_type: :text
        )
      end

      before do
        scout.sync_required_attribute_ids!([field.id])
        Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: stage,
          origin_conversation: conversation,
          active_conversation: conversation,
          title: 'Observability Deal',
          status: :open
        )
      end

      it 'wraps the LLM call with instrument_agent_session and instrument_llm_call carrying metadata' do
        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Olá',
          message_history: []
        )

        expected_params = hash_including(
          span_name: 'llm.scout_v2.turn_runner',
          feature_name: 'scout_v2_turn_runner',
          account_id: account.id,
          conversation_id: conversation.id,
          metadata: hash_including(
            scout_id: scout.id,
            playbook: 'qualificacao',
            activation_reason: 'state',
            unsatisfied_flags: hash_including(pending_fields: ['orcamento'], unmet_requires: [])
          )
        )

        expect(runner).to receive(:instrument_agent_session).with(expected_params).and_call_original
        expect(runner).to receive(:instrument_llm_call).with(expected_params).and_call_original

        runner.perform
      end

      it 'produces individual instrumented records for executed tools via CallRecorder' do
        captured_tools = []
        allow(fake_chat).to receive(:with_tool) do |tool|
          captured_tools << tool
          fake_chat
        end

        allow(fake_chat).to receive(:ask) do
          tool = captured_tools.find { |t| t.name == 'manage_opportunity' }
          tool.execute(action: 'update', custom_attributes: { 'orcamento' => '5000' })
          fake_response
        end

        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Meu orçamento é 5000',
          message_history: []
        )

        result = runner.perform

        recorded_call = result[:tool_calls].find { |c| c[:tool_name] == 'manage_opportunity' }
        expect(recorded_call).to be_present
        expect(recorded_call[:arguments]).to eq(action: 'update', custom_attributes: { 'orcamento' => '5000' })
        expect(recorded_call[:simulated]).to be(false)
        expect(recorded_call[:result]).to be_present
      end

      it 'records each invocation distinctly when the active playbook declared tool is invoked more than once in the same turn' do
        captured_tools = []
        allow(fake_chat).to receive(:with_tool) do |tool|
          captured_tools << tool
          fake_chat
        end

        allow(fake_chat).to receive(:ask) do
          tool = captured_tools.find { |t| t.name == 'manage_opportunity' }
          tool.execute(action: 'update', custom_attributes: { 'orcamento' => '5000' })
          tool.execute(action: 'update', custom_attributes: { 'orcamento' => '6000' })
          fake_response
        end

        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Meu orçamento é 6000',
          message_history: []
        )

        result = runner.perform

        opportunity_calls = result[:tool_calls].select { |c| c[:tool_name] == 'manage_opportunity' }
        expect(opportunity_calls.size).to eq(2)
        expect(opportunity_calls[0][:arguments]).to eq(action: 'update', custom_attributes: { 'orcamento' => '5000' })
        expect(opportunity_calls[1][:arguments]).to eq(action: 'update', custom_attributes: { 'orcamento' => '6000' })
        expect(opportunity_calls).to all(include(simulated: false, result: be_present))
      end
    end

    describe 'multi-turn qualification dialogue and router continuity (US3)' do
      let(:sandbox_conv) { Custom::ScoutV2::PlaygroundConversation.for(scout) }
      let!(:field) do
        CustomAttributeDefinition.create!(
          account: account,
          attribute_display_name: 'Orçamento',
          attribute_key: 'orcamento',
          attribute_model: :opportunity_attribute,
          attribute_display_type: :text
        )
      end
      let!(:opportunity) do
        Opportunity.create!(
          account: account,
          contact: sandbox_conv.contact,
          pipeline_stage: stage,
          origin_conversation: sandbox_conv,
          active_conversation: sandbox_conv,
          title: 'Playground Lead',
          status: :open
        )
      end

      before do
        scout.sync_required_attribute_ids!([field.id])
      end

      it 'updates opportunity fields and persists state on initial qualification turn' do
        captured_tools = []
        allow(fake_chat).to receive(:with_tool) do |tool|
          captured_tools << tool
          fake_chat
        end

        allow(fake_chat).to receive(:ask) do
          tool = captured_tools.find { |t| t.name == 'manage_opportunity' }
          tool.execute(action: 'update', opportunity_id: opportunity.id, custom_attributes: { 'orcamento' => '10000' })
          OpenStruct.new(content: 'Orçamento registrado! Algo mais?')
        end

        turn1 = described_class.new(
          scout: scout,
          conversation: sandbox_conv,
          message: 'Meu orçamento é 10000',
          message_history: []
        )

        turn1_result = turn1.perform

        expect(turn1_result[:reply]).to eq('Orçamento registrado! Algo mais?')
        expect(opportunity.reload.custom_attributes['orcamento']).to eq('10000')

        state = ScoutConversationState.for_conversation(sandbox_conv)
        expect(state.active_playbook).to eq('qualificacao')
        expect(state.activation_reason).to eq('state')
        expect(state.activated_at).to be_present
      end

      it 'preserves state on subsequent turn without redundant activation writes or message leakage' do
        state = ScoutConversationState.for_conversation(sandbox_conv).record_state_activation!('qualificacao')
        initial_activated_at = state.activated_at
        opportunity.update!(custom_attributes: { 'orcamento' => '10000' })

        captured_instructions_turn2 = nil
        allow(fake_chat).to receive(:with_instructions) do |instructions|
          captured_instructions_turn2 = instructions
          fake_chat
        end

        allow(fake_chat).to receive(:ask) do
          OpenStruct.new(content: 'Perfeito, tudo certo.')
        end

        state_record = ScoutConversationState.for_conversation(sandbox_conv)
        allow(ScoutConversationState).to receive(:for_conversation).with(sandbox_conv).and_return(state_record)
        expect(state_record).not_to receive(:record_state_activation!)

        sandbox_conv.reload
        turn2 = described_class.new(
          scout: scout,
          conversation: sandbox_conv,
          message: 'Tudo certo',
          message_history: [
            { role: 'user', content: 'Meu orçamento é 10000' },
            { role: 'assistant', content: 'Orçamento registrado! Algo mais?' }
          ]
        )

        turn2_result = turn2.perform

        expect(turn2_result[:reply]).to eq('Perfeito, tudo certo.')
        expect(state_record.reload.active_playbook).to eq('qualificacao')
        expect(state_record.activated_at.to_i).to eq(initial_activated_at.to_i)
        expect(captured_instructions_turn2).not_to include('Campos pendentes para esta oportunidade')
        expect(sandbox_conv.messages.count).to eq(0)
      end
    end
  end
end
