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
  let(:account_config) do
    ScoutAccountConfig.create!(
      account: account,
      provider: :gemini,
      model_name: 'gemini-2.0-flash',
      api_key: 'test-api-key'
    )
  end
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :pending) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Runner Scout',
      responses_quota: 10,
      responses_consumed: 0,
      enabled: true,
      feature_memory: false
    )
  end
  let(:runner) { described_class.new(scout: scout, conversation: conversation) }

  describe '#perform' do
    let(:fake_chat) { instance_double(RubyLLM::Chat, messages: []) }
    let(:valid_json_content) { { reasoning: 'Lead perguntou sobre planos.', response: 'Olá! Como posso ajudar você hoje?' }.to_json }
    let(:fake_response) { instance_double(RubyLLM::Message, content: valid_json_content) }

    before do
      account_config
      allow(scout).to receive(:llm_chat).and_return(fake_chat)
      allow(fake_chat).to receive(:with_schema).and_return(fake_chat)
      allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
      allow(fake_chat).to receive(:with_tool).and_return(fake_chat)
      allow(fake_chat).to receive(:add_message).and_return(fake_chat)
      allow(fake_chat).to receive(:ask).and_return(fake_response)
    end

    context 'when qualifying conversation executes normally with structured JSON response' do
      before do
        conversation.messages.create!(
          account: account,
          inbox: inbox,
          sender: contact,
          message_type: :incoming,
          content: 'Quero conhecer os planos'
        )
      end

      it 'parses response, dispatches only the clean response text and increments responses_consumed' do
        expect do
          runner.perform
        end.to change { scout.reload.responses_consumed }.by(1)

        outgoing = conversation.messages.where(private: false, message_type: :outgoing).last
        expect(outgoing).to be_present
        expect(outgoing.content).to eq('Olá! Como posso ajudar você hoje?')
        expect(outgoing.content).not_to include('reasoning')
        expect(outgoing.content).not_to include('{')
        expect(conversation.reload.status).to eq('pending')
      end

      it 'delegates prompt construction to Custom::Scout::SystemPromptsService' do
        expect(Custom::Scout::SystemPromptsService).to receive(:build).with(
          scout: scout,
          contact: contact,
          inbox: inbox,
          catalog_instructions: nil,
          knowledge_available: false
        ).and_call_original

        runner.perform
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

      it 'registers SearchKnowledgeBase tool and includes prompt guidance when ready sources exist' do
        scout.scout_knowledge_sources.create!(
          account: account,
          kind: :faq,
          question: 'Hours?',
          answer: '9am to 5pm',
          status: :ready
        )

        expect(fake_chat).to receive(:with_tool).with(an_instance_of(Custom::Scout::Tools::SearchKnowledgeBase)).at_least(:once)
        expect(fake_chat).to receive(:with_instructions) do |instructions|
          expect(instructions).to include('search_knowledge_base')
          expect(instructions).not_to include('9am to 5pm')
          fake_chat
        end

        runner.perform
      end

      it 'sanitizes markdown code fences around JSON before parsing' do
        fenced_content = "```json\n#{valid_json_content}\n```"
        allow(fake_response).to receive(:content).and_return(fenced_content)

        runner.perform

        outgoing = conversation.messages.where(private: false, message_type: :outgoing).last
        expect(outgoing.content).to eq('Olá! Como posso ajudar você hoje?')
      end

      it 'configures LLM chat with Custom::Scout::ResponseSchema' do
        expect(fake_chat).to receive(:with_schema).with(Custom::Scout::ResponseSchema).and_return(fake_chat)

        runner.perform
      end

      it 'extracts response and reasoning when RubyLLM returns an already-parsed Hash (schema mode)' do
        allow(fake_response).to receive(:content).and_return(
          { 'reasoning' => 'Lead quer saber preços', 'response' => 'Nossos planos começam em R$ 99.' }
        )

        expect do
          runner.perform
        end.to change { scout.reload.responses_consumed }.by(1)

        outgoing = conversation.messages.where(private: false, message_type: :outgoing).last
        expect(outgoing).to be_present
        expect(outgoing.content).to eq('Nossos planos começam em R$ 99.')
        expect(outgoing.content).not_to include('reasoning')
        expect(conversation.reload.status).to eq('pending')
      end

      it 'registers schema alongside tool configuration during conversation execution' do
        expect(fake_chat).to receive(:with_schema).with(Custom::Scout::ResponseSchema).and_return(fake_chat)
        expect(fake_chat).to receive(:with_tool).with(an_instance_of(Custom::Scout::Tools::ManageOpportunity)).and_return(fake_chat)

        runner.perform
      end

      it 'discards the model drafted reply and only triggers the qualification handoff when handoff_needed is flagged' do
        captured_manage_opportunity = nil
        allow(fake_chat).to receive(:with_tool) do |tool|
          captured_manage_opportunity = tool if tool.is_a?(Custom::Scout::Tools::ManageOpportunity)
          fake_chat
        end
        # Simulates manage_opportunity having qualified the opportunity mid-turn
        # (Custom::Scout::OpportunityStageTransitionService flags this, it does not
        # trigger the handoff itself — see research.md for the race this avoids).
        allow(fake_chat).to receive(:ask) do
          allow(captured_manage_opportunity).to receive(:handoff_needed).and_return(true)
          fake_response
        end

        handoff_service = instance_double(Custom::Scout::HandoffService)
        allow(Custom::Scout::HandoffService).to receive(:new).with(scout: scout, conversation: conversation).and_return(handoff_service)
        allow(handoff_service).to receive(:perform) do |**|
          expect(conversation.messages.where(private: false, message_type: :outgoing).count).to eq(0)
          'Conversation transferred to human queue successfully.'
        end

        expect do
          runner.perform
        end.not_to(change { scout.reload.responses_consumed })

        expect(conversation.messages.where(private: false, message_type: :outgoing, content: 'Olá! Como posso ajudar você hoje?')).not_to exist
        expect(handoff_service).to have_received(:perform).with(reason: 'Oportunidade movida para o estágio qualificado').once
      end

      it 'does not trigger a qualification handoff when no tool flags handoff_needed' do
        expect(Custom::Scout::HandoffService).not_to receive(:new)

        runner.perform
      end
    end

    context 'when model returns unparseable or invalid structured output (fail-closed)' do
      before do
        conversation.messages.create!(
          account: account,
          inbox: inbox,
          sender: contact,
          message_type: :incoming,
          content: 'Quero saber mais'
        )
      end

      it 'fails closed on plain text without JSON syntax and sends public handoff notice' do
        allow(fake_response).to receive(:content).and_return('Texto simples sem JSON')

        runner.perform

        expect(conversation.reload.status).to eq('open')
        expect(conversation.messages.where(private: false, message_type: :outgoing).last.content).to eq(I18n.t('conversations.scout.handoff'))
        expect(conversation.messages.where(private: true).last.content).to include('⚠️ [IA Pausada]')
      end

      it 'fails closed when json response field is blank and sends public handoff notice' do
        allow(fake_response).to receive(:content).and_return({ reasoning: 'justificativa', response: '' }.to_json)

        runner.perform

        expect(conversation.reload.status).to eq('open')
        expect(conversation.messages.where(private: false, message_type: :outgoing).last.content).to eq(I18n.t('conversations.scout.handoff'))
        expect(conversation.messages.where(private: true).last.content).to include('⚠️ [IA Pausada]')
      end

      it 'fails closed when content is nil and sends public handoff notice' do
        allow(fake_response).to receive(:content).and_return(nil)

        runner.perform

        expect(conversation.reload.status).to eq('open')
        expect(conversation.messages.where(private: false, message_type: :outgoing).last.content).to eq(I18n.t('conversations.scout.handoff'))
        expect(conversation.messages.where(private: true).last.content).to include('⚠️ [IA Pausada]')
      end

      it 'fails closed when parsed Hash is missing response key and sends public handoff notice' do
        allow(fake_response).to receive(:content).and_return({ 'reasoning' => 'Sem resposta' })

        runner.perform

        expect(conversation.reload.status).to eq('open')
        expect(conversation.messages.where(private: false, message_type: :outgoing).last.content).to eq(I18n.t('conversations.scout.handoff'))
        expect(conversation.messages.where(private: true).last.content).to include('⚠️ [IA Pausada]')
      end

      it 'fails closed when parsed Hash response is blank and sends public handoff notice' do
        allow(fake_response).to receive(:content).and_return({ 'reasoning' => 'Sem resposta', 'response' => '   ' })

        runner.perform

        expect(conversation.reload.status).to eq('open')
        expect(conversation.messages.where(private: false, message_type: :outgoing).last.content).to eq(I18n.t('conversations.scout.handoff'))
        expect(conversation.messages.where(private: true).last.content).to include('⚠️ [IA Pausada]')
      end
    end

    context 'when fail-safe pre-call check fails (quota exhausted)' do
      before do
        scout.update!(responses_quota: 0)
      end

      it 'hands over conversation to human with alert note and public handoff notice without calling LLM' do
        runner.perform

        expect(conversation.reload.status).to eq('open')
        expect(conversation.messages.where(private: false, message_type: :outgoing).last.content).to eq(I18n.t('conversations.scout.handoff'))
        expect(conversation.messages.where(private: true).last.content).to include('⚠️ [IA Pausada]')
        expect(fake_chat).not_to have_received(:ask)
      end

      it 'creates public transfer message before bot_handoff! is called' do
        allow(conversation).to receive(:bot_handoff!).and_wrap_original do |original_method, *args|
          expect(conversation.messages.where(private: false, message_type: :outgoing).last&.content).to eq(I18n.t('conversations.scout.handoff'))
          original_method.call(*args)
        end

        runner.perform
        expect(conversation.reload.status).to eq('open')
      end

      it 'sends the public handoff notice in the conversation language when set, over the account locale' do
        conversation.update!(additional_attributes: { 'conversation_language' => 'pt_BR' })
        account.update!(locale: :en)

        runner.perform

        expect(conversation.messages.where(private: false, message_type: :outgoing).last.content)
          .to eq(I18n.t('conversations.scout.handoff', locale: 'pt_BR'))
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

      it 'rescues error, triggers fail-safe handoff, public notice and alert note' do
        runner.perform

        expect(conversation.reload.status).to eq('open')
        expect(conversation.messages.where(private: false, message_type: :outgoing).last.content).to eq(I18n.t('conversations.scout.handoff'))
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

    context 'when observability / OpenTelemetry is configured' do
      before do
        conversation.messages.create!(
          account: account,
          inbox: inbox,
          sender: contact,
          message_type: :incoming,
          content: 'Quero conhecer os planos'
        )
      end

      context 'when otel is enabled' do
        before do
          allow(ChatwootApp).to receive(:otel_enabled?).and_return(true)
        end

        it 'wraps LLM chat execution in instrument_agent_session and instrument_llm_call' do
          expect(runner).to receive(:instrument_agent_session).with(
            hash_including(
              span_name: 'llm.scout.agent_runner',
              account_id: account.id,
              conversation_id: conversation.id,
              feature_name: 'scout_agent_runner'
            )
          ).and_call_original

          expect(runner).to receive(:instrument_llm_call).with(
            hash_including(
              span_name: 'llm.scout.agent_runner',
              account_id: account.id,
              conversation_id: conversation.id,
              feature_name: 'scout_agent_runner'
            )
          ).and_call_original

          mock_span = instance_double(OpenTelemetry::Trace::Span)
          allow(mock_span).to receive(:set_attribute)
          mock_tracer = instance_double(OpenTelemetry::Trace::Tracer)
          allow(runner).to receive(:tracer).and_return(mock_tracer)
          allow(mock_tracer).to receive(:in_span).and_yield(mock_span)

          runner.perform

          outgoing = conversation.messages.where(private: false, message_type: :outgoing).last
          expect(outgoing.content).to eq('Olá! Como posso ajudar você hoje?')
        end

        it 'completes conversation and dispatches reply normally even if tracing raises error mid-conversation' do
          mock_tracer = instance_double(OpenTelemetry::Trace::Tracer)
          allow(runner).to receive(:tracer).and_return(mock_tracer)
          allow(mock_tracer).to receive(:in_span).and_raise(StandardError.new('Langfuse unreachable'))

          runner.perform

          outgoing = conversation.messages.where(private: false, message_type: :outgoing).last
          expect(outgoing).to be_present
          expect(outgoing.content).to eq('Olá! Como posso ajudar você hoje?')
          expect(conversation.reload.status).to eq('pending')
        end
      end

      context 'when otel is disabled' do
        before do
          allow(ChatwootApp).to receive(:otel_enabled?).and_return(false)
        end

        it 'behaves identically without invoking tracing tracer or crashing' do
          expect(runner).not_to receive(:tracer)

          runner.perform

          outgoing = conversation.messages.where(private: false, message_type: :outgoing).last
          expect(outgoing.content).to eq('Olá! Como posso ajudar você hoje?')
        end
      end
    end

    context 'when response auditor feature flag is enabled vs disabled (US1)' do
      let(:false_claim_content) do
        { reasoning: 'Atualizando oportunidade.', response: 'Já atualizei sua oportunidade para Ganho com sucesso!' }.to_json
      end
      let(:false_claim_response) { instance_double(RubyLLM::Message, content: false_claim_content) }

      before do
        conversation.messages.create!(
          account: account,
          inbox: inbox,
          sender: contact,
          message_type: :incoming,
          content: 'Pode atualizar meu negócio para Ganho?'
        )
        allow(fake_chat).to receive(:ask).and_return(false_claim_response)
      end

      context 'when feature_response_auditor is false (default)' do
        before do
          scout.update!(feature_response_auditor: false)
        end

        it 'delivers reply unchanged without instantiating ResponseAuditor or calling extra LLM checks' do
          expect(Custom::Scout::ResponseAuditor).not_to receive(:new)

          expect do
            runner.perform
          end.to change { scout.reload.responses_consumed }.by(1)

          outgoing = conversation.messages.where(private: false, message_type: :outgoing).last
          expect(outgoing.content).to eq('Já atualizei sua oportunidade para Ganho com sucesso!')
        end
      end

      context 'when feature_response_auditor is true' do
        let(:auditor_double) { instance_double(Custom::Scout::ResponseAuditor) }

        before do
          scout.update!(feature_response_auditor: true)
          allow(Custom::Scout::ResponseAuditor).to receive(:new).with(scout: scout, conversation: conversation).and_return(auditor_double)
        end

        it 'replaces reply with repaired reply when auditor corrects it' do
          allow(auditor_double).to receive(:audit).and_return({ action: :proceed, reply: 'Ainda não atualizei, vou verificar.' })

          expect do
            runner.perform
          end.to change { scout.reload.responses_consumed }.by(1)

          outgoing = conversation.messages.where(private: false, message_type: :outgoing).last
          expect(outgoing.content).to eq('Ainda não atualizei, vou verificar.')
        end

        it 'escalates to fail-safe handoff when auditor returns escalate' do
          allow(auditor_double).to receive(:audit).and_return({ action: :escalate, reason: 'Resposta inconsistente com as ações executadas.' })

          expect do
            runner.perform
          end.not_to(change { scout.reload.responses_consumed })

          expect(conversation.reload.status).to eq('open')
          handoff_msg = conversation.messages.where(private: false, message_type: :outgoing).last
          expect(handoff_msg.content).to eq(I18n.t('conversations.scout.handoff', locale: 'en'))
          alert_msg = conversation.messages.where(private: true).last
          expect(alert_msg.content).to include('⚠️ [IA Pausada]')
          expect(alert_msg.content).to include('Resposta inconsistente com as ações executadas.')
        end

        it 'excludes the system instructions message from the message_history passed to the auditor' do
          system_message = instance_double(
            RubyLLM::Message, role: :system, content: '[Identidade e Escopo]\nFallback para humano: utilize handover_to_human'
          )
          user_message = instance_double(RubyLLM::Message, role: :user, content: 'fachada.')
          assistant_message = instance_double(RubyLLM::Message, role: :assistant, content: 'Perfeito, obrigado!')
          allow(fake_chat).to receive(:messages).and_return([system_message, user_message, assistant_message])

          allow(auditor_double).to receive(:audit) do |**kwargs|
            expect(kwargs[:message_history]).not_to include(a_hash_including(role: 'system'))
            expect(kwargs[:message_history]).to eq([{ role: 'user', content: 'fachada.' }, { role: 'assistant', content: 'Perfeito, obrigado!' }])
            { action: :proceed, reply: 'Perfeito, obrigado!' }
          end

          runner.perform
        end
      end
    end

    context 'when handoff and broken promise handling executes (US2)' do
      let(:auditor_double) { instance_double(Custom::Scout::ResponseAuditor) }

      before do
        conversation.messages.create!(
          account: account,
          inbox: inbox,
          sender: contact,
          message_type: :incoming,
          content: 'Quero falar com uma pessoa real.'
        )
      end

      context 'when feature_response_auditor is true' do
        before do
          scout.update!(feature_response_auditor: true)
          allow(Custom::Scout::ResponseAuditor).to receive(:new).with(scout: scout, conversation: conversation).and_return(auditor_double)
        end

        it 'handles explicit handoff returned by auditor without dispatching extra reply' do
          allow(auditor_double).to receive(:audit).and_return({ action: :handoff })

          expect do
            runner.perform
          end.not_to(change { scout.reload.responses_consumed })

          expect(conversation.messages.where(private: false, message_type: :outgoing)).to be_empty
        end

        it 'handles broken future promise escalation' do
          allow(auditor_double).to receive(:audit).and_return({ action: :escalate, reason: 'Promessa de ação futura não cumprida.' })

          runner.perform

          expect(conversation.reload.status).to eq('open')
          alert_msg = conversation.messages.where(private: true).last
          expect(alert_msg.content).to include('Promessa de ação futura não cumprida.')
        end
      end

      context 'when feature_response_auditor is false' do
        before do
          scout.update!(feature_response_auditor: false)
        end

        it 'does not trigger proactive handoff via ResponseAuditor' do
          expect(Custom::Scout::ResponseAuditor).not_to receive(:new)

          runner.perform
        end
      end
    end

    context 'when evaluating operator safety net flag (US3)' do
      let(:plain_reply_content) { { reasoning: 'Ajuda comum.', response: 'Como posso ajudar?' }.to_json }
      let(:plain_response) { instance_double(RubyLLM::Message, content: plain_reply_content) }

      before do
        allow(fake_chat).to receive(:ask).and_return(plain_response)
        conversation.messages.create!(
          account: account,
          inbox: inbox,
          sender: contact,
          message_type: :incoming,
          content: 'Olá, bom dia!'
        )
      end

      it 'never instantiates ResponseAuditor or calls classifiers when feature_response_auditor is false' do
        scout.update!(feature_response_auditor: false)
        expect(Custom::Scout::ResponseAuditor).not_to receive(:new)
        expect(Custom::Scout::ActionClassifierService).not_to receive(:new)
        expect(Custom::Scout::ClaimConsistencyService).not_to receive(:new)

        expect do
          runner.perform
        end.to change { scout.reload.responses_consumed }.by(1)

        outgoing = conversation.messages.where(private: false, message_type: :outgoing).last
        expect(outgoing.content).to eq('Como posso ajudar?')
      end

      it 'delivers original reply unchanged and increments responses_consumed by exactly 1 on a safe turn when flag is true' do
        scout.update!(feature_response_auditor: true)
        action_service = instance_double(Custom::Scout::ActionClassifierService, classify: { 'action' => 'continue', 'action_reason' => nil })
        claim_service = instance_double(Custom::Scout::ClaimConsistencyService, check: { 'decision' => 'safe', 'reason' => 'Safe conversation' })
        allow(Custom::Scout::ActionClassifierService).to receive(:new).and_return(action_service)
        allow(Custom::Scout::ClaimConsistencyService).to receive(:new).and_return(claim_service)

        expect do
          runner.perform
        end.to change { scout.reload.responses_consumed }.by(1)

        expect(conversation.reload.status).to eq('pending')
        outgoing = conversation.messages.where(private: false, message_type: :outgoing).last
        expect(outgoing.content).to eq('Como posso ajudar?')
        expect(conversation.messages.where(private: false, message_type: :outgoing).count).to eq(1)
      end
    end
  end
end
