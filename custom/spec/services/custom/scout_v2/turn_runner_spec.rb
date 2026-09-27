# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

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
          indices = [
            instructions.index('[Identity]'),
            instructions.index('[Communication]'),
            instructions.index('[Memory]'),
            instructions.index('[Safety]'),
            instructions.index('[Playbook Index]'),
            instructions.index('## Passos')
          ]

          expect(indices).to all(be_a(Integer))
          expect(indices).to eq(indices.sort)
          expect(instructions).to include(
            'Pergunte pelos dados de qualificação pendentes',
            'Campos pendentes para esta oportunidade',
            'Orçamento (chave: orcamento)'
          )
        end
      end

      it 'composes bracketed block headers strictly as Identity, Communication, Memory, Safety, Playbook Index' do
        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Olá',
          message_history: []
        )

        runner.perform

        expect(fake_chat).to have_received(:with_instructions) do |instructions|
          headers = instructions.scan(/^\[([^\]]+)\]$/).flatten
          expect(headers).to eq(['Identity', 'Communication', 'Memory', 'Safety', 'Playbook Index'])
        end
      end

      it 'composes the tool catalog with declared tools plus search_knowledge_base and no undeclared registry tools' do
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
        expect(tool_names).to include('search_knowledge_base', 'manage_opportunity')
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

    context 'when no playbook matches (always-on instructions and index)' do
      it 'assembles prompt with Instructions and Playbook Index blocks and removes fallback instructions' do
        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Dúvida geral',
          message_history: []
        )

        runner.perform

        expect(fake_chat).to have_received(:with_instructions) do |instructions|
          expect(instructions).to include('[Identity]', '[Communication]', '[Memory]', '[Safety]', '[Playbook Index]')
          expect(instructions).not_to include(
            'Nenhum procedimento específico está ativo para esta conversa',
            'use a base de conhecimento quando for útil'
          )
        end

        expect(ScoutConversationState.for_conversation(conversation).active_playbook).to be_nil
      end

      it 'includes every loaded catalog playbook under [Playbook Index]' do
        catalog = Custom::ScoutV2::Playbook::Loader.load_all
        expect(catalog.playbooks).not_to be_empty

        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Dúvida geral',
          message_history: []
        )

        runner.perform

        expect(fake_chat).to have_received(:with_instructions) do |instructions|
          index_block = instructions[/\[Playbook Index\].*/m]
          expect(index_block).to be_present
          catalog.playbooks.each do |pb|
            expect(index_block).to include("- #{pb.name}: #{pb.trigger.squish}")
          end
        end
      end

      it 'dynamically reflects newly added playbooks in [Playbook Index] across subsequent turns' do
        captured_instructions = []
        allow(fake_chat).to receive(:with_instructions) do |instructions|
          captured_instructions << instructions
          fake_chat
        end

        Dir.mktmpdir('scout_v2_turn_runner_dynamic_spec') do |tmp_dir|
          FileUtils.cp(Rails.root.join('custom/playbooks/qualificacao.md'), File.join(tmp_dir, 'qualificacao.md'))

          with_modified_env SCOUT_V2_PLAYBOOKS_DIR: tmp_dir do
            first_runner = described_class.new(
              scout: scout,
              conversation: conversation,
              message: 'Dúvida geral',
              message_history: []
            )

            first_runner.perform

            first_index_block = captured_instructions.first[/\[Playbook Index\].*/m]
            expect(first_index_block).to be_present
            first_entries = first_index_block.strip.lines[1..]
            expect(first_entries.size).to eq(1)
            expect(first_entries.first).to include('- qualificacao:')
            expect(first_index_block).not_to include('- duvida_comercial:')

            File.write(File.join(tmp_dir, 'duvida_comercial.md'), <<~MD)
              ---
              name: duvida_comercial
              title: Dúvidas Comerciais
              priority: 20
              trigger: O cliente tem dúvidas sobre preços, planos ou serviços comerciais.
              ---

              ## Passos
              1. Esclareça as dúvidas comerciais do cliente.
            MD

            second_runner = described_class.new(
              scout: scout,
              conversation: conversation,
              message: 'Nova dúvida geral',
              message_history: []
            )

            second_runner.perform

            second_index_block = captured_instructions.last[/\[Playbook Index\].*/m]
            expect(second_index_block).to be_present
            second_entries = second_index_block.strip.lines[1..]
            expect(second_entries.size).to eq(2)
            expect(second_index_block).to include(
              '- qualificacao:',
              '- duvida_comercial: O cliente tem dúvidas sobre preços, planos ou serviços comerciais.'
            )
          end
        end
      end

      it 'reflects scout tone, response_length, and greeting updates in the composed instructions' do
        scout.update!(tone: :humorous, response_length: :thorough, greeting: 'E aí, tudo certo?')

        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Dúvida geral',
          message_history: []
        )

        runner.perform

        builder = Custom::ScoutV2::Instructions::CommunicationBuilder
        expect(fake_chat).to have_received(:with_instructions) do |instructions|
          expect(instructions).to include(
            builder::TONE_DIRECTIVES['humorous'],
            builder::RESPONSE_LENGTH_DIRECTIVES['thorough'],
            '"E aí, tudo certo?"'
          )
          expect(instructions).not_to include(builder::TONE_DIRECTIVES['friendly'], builder::RESPONSE_LENGTH_DIRECTIVES['concise'])
        end
      end

      it 'composes bracketed block headers strictly as Identity, Communication, Memory, Safety, Playbook Index' do
        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Dúvida geral',
          message_history: []
        )

        runner.perform

        expect(fake_chat).to have_received(:with_instructions) do |instructions|
          headers = instructions.scan(/^\[([^\]]+)\]$/).flatten
          expect(headers).to eq(['Identity', 'Communication', 'Memory', 'Safety', 'Playbook Index'])
        end
      end

      it 'offers open_playbook tool alongside search_knowledge_base when no playbook is forced' do
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

        tool_names = passed_tools.map(&:name)
        expect(tool_names).to contain_exactly('search_knowledge_base', 'open_playbook')
      end

      it 'executes open_playbook during the turn, registering declared tools on live chat, returning body, and persisting trigger activation' do
        captured_tools = []
        allow(fake_chat).to receive(:with_tool) do |tool|
          captured_tools << tool
          fake_chat
        end

        open_pb_tool_result = nil
        allow(fake_chat).to receive(:ask) do
          open_pb_tool = captured_tools.find { |t| t.name == 'open_playbook' }
          open_pb_tool_result = open_pb_tool.execute(name: 'qualificacao')
          fake_response
        end

        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Quero qualificar meu lead',
          message_history: []
        )

        result = runner.perform

        registered_tool_names = captured_tools.map(&:name)
        expect(registered_tool_names).to include('manage_opportunity')

        qualificacao_body = Custom::ScoutV2::Playbook::Loader.load_all['qualificacao'].body
        expect(open_pb_tool_result).to eq(body: qualificacao_body)

        open_pb_call = result[:tool_calls].find { |c| c[:tool_name] == 'open_playbook' }
        expect(open_pb_call[:result]).to eq(body: qualificacao_body)

        state = ScoutConversationState.for_conversation(conversation)
        expect(state.active_playbook).to eq('qualificacao')
        expect(state.activation_reason).to eq('trigger')
      end

      it 'records tool calls with parity when open_playbook injects a tool executed in the same turn' do
        captured_tools = []
        allow(fake_chat).to receive(:with_tool) do |tool|
          captured_tools << tool
          fake_chat
        end

        allow(fake_chat).to receive(:ask) do
          open_pb_tool = captured_tools.find { |t| t.name == 'open_playbook' }
          open_pb_tool.execute(name: 'qualificacao')

          manage_opp_tool = captured_tools.find { |t| t.name == 'manage_opportunity' }
          manage_opp_tool.execute(action: 'create', title: 'Oportunidade Mid-Turn')

          fake_response
        end

        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Quero qualificar meu lead e criar oportunidade',
          message_history: []
        )

        result = runner.perform

        manage_opp_call = result[:tool_calls].find { |c| c[:tool_name] == 'manage_opportunity' }
        expect(manage_opp_call).to be_present
        expect(manage_opp_call[:arguments]).to eq(action: 'create', title: 'Oportunidade Mid-Turn')
        expect(manage_opp_call[:simulated]).to be(false)
        expect(manage_opp_call[:result]).to be_present
      end

      it 'handles open_playbook with an unknown name gracefully, returning error in tool result and continuing turn without failure' do
        captured_tools = []
        allow(fake_chat).to receive(:with_tool) do |tool|
          captured_tools << tool
          fake_chat
        end

        allow(fake_chat).to receive(:ask) do
          open_pb_tool = captured_tools.find { |t| t.name == 'open_playbook' }
          open_pb_tool.execute(name: 'non_existent_playbook')
          fake_response
        end

        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Quero algo inexistente',
          message_history: []
        )

        result = runner.perform

        expect(result[:reply]).to eq(fake_response.content)

        open_pb_call = result[:tool_calls].find { |c| c[:tool_name] == 'open_playbook' }
        expect(open_pb_call).to be_present
        expect(open_pb_call[:result]).to be_a(Hash)
        expect(open_pb_call[:result][:error]).to include('Playbook desconhecida: non_existent_playbook')

        registered_tool_names = captured_tools.map(&:name)
        expect(registered_tool_names).not_to include('manage_opportunity')

        state = ScoutConversationState.for_conversation(conversation)
        expect(state.active_playbook).to be_nil
        expect(state.activation_reason).to be_nil
      end

      it 'populates turn metadata with trigger activation_reason when conversation was trigger-activated' do
        state = ScoutConversationState.for_conversation(conversation)
        state.record_trigger_activation!('qualificacao')

        allow(fake_chat).to receive(:ask).and_return(fake_response)

        allow(ChatwootApp).to receive(:otel_enabled?).and_return(true)
        mock_span = instance_double(OpenTelemetry::Trace::Span)
        allow(mock_span).to receive(:set_attribute)
        mock_tracer = instance_double(OpenTelemetry::Trace::Tracer)
        allow(OpentelemetryConfig).to receive(:tracer).and_return(mock_tracer)
        allow(mock_tracer).to receive(:in_span).and_yield(mock_span)

        runner = described_class.new(
          scout: scout,
          conversation: conversation,
          message: 'Continuando com a playbook aberta',
          message_history: []
        )

        runner.perform

        expect(mock_span).to have_received(:set_attribute).with('langfuse.trace.metadata.activation_reason', 'trigger').at_least(:once)
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
