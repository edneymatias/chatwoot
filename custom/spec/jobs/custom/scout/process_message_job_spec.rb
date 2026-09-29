# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::ProcessMessageJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :pending) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Debounce Scout',
      debounce_delay_seconds: 4,
      enabled: true
    )
  end

  before do
    ScoutInbox.create!(scout: scout, inbox: inbox)
    Redis::Alfred.delete(format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id))
    Redis::Alfred.delete(format(described_class::ENQUEUED_KEY, conversation_id: conversation.id))
  end

  describe '.enqueue_debounced' do
    it 'sets last_message_at and enqueues job on first message' do
      expect do
        described_class.enqueue_debounced(conversation, scout)
      end.to have_enqueued_job(described_class).with(conversation.id)

      last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
      enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)

      expect(Redis::Alfred.get(last_msg_key)).to be_present
      expect(Redis::Alfred.get(enqueued_key)).to be_present
    end

    it 'does not enqueue duplicate jobs for subsequent messages in the same burst' do
      described_class.enqueue_debounced(conversation, scout)

      expect do
        described_class.enqueue_debounced(conversation, scout)
      end.not_to have_enqueued_job(described_class)
    end
  end

  describe '#perform' do
    let(:runner_instance) { instance_double(Custom::Scout::AgentRunner, perform: true) }

    before do
      allow(Custom::Scout::AgentRunner).to receive(:new).and_return(runner_instance)
    end

    it 'triggers runner and cleans up Redis keys when delay has elapsed' do
      last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
      enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)

      # Simulate message arrived 5 seconds ago (delay is 4 seconds)
      Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
      Redis::Alfred.set(enqueued_key, true)

      described_class.new.perform(conversation.id)

      expect(Custom::Scout::AgentRunner).to have_received(:new).with(scout: scout, conversation: conversation)
      expect(runner_instance).to have_received(:perform)
      expect(Redis::Alfred.get(last_msg_key)).to be_nil
      expect(Redis::Alfred.get(enqueued_key)).to be_nil
    end

    it 'reschedules job when delay has not yet elapsed (sliding window reset)' do
      last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
      enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)

      # Simulate message arrived 2 seconds ago (delay is 4 seconds)
      Redis::Alfred.set(last_msg_key, Time.current.to_f - 2.0)
      Redis::Alfred.set(enqueued_key, true)

      expect do
        described_class.new.perform(conversation.id)
      end.to have_enqueued_job(described_class).with(conversation.id)

      expect(Custom::Scout::AgentRunner).not_to have_received(:new)
    end

    context 'when Scout has audience configured' do
      before do
        scout.update!(
          audience: [
            {
              'attribute_key' => 'labels',
              'filter_operator' => 'equal_to',
              'values' => ['vip']
            }
          ]
        )
      end

      it 'opens conversation and does not run AgentRunner when contact does not match audience' do
        contact.update_labels(['other'])
        last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
        enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)
        Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key, true)

        described_class.new.perform(conversation.id)

        expect(Custom::Scout::AgentRunner).not_to have_received(:new)
        expect(conversation.reload.status).to eq('open')
        expect(Redis::Alfred.get(last_msg_key)).to be_nil
        expect(Redis::Alfred.get(enqueued_key)).to be_nil
      end
    end

    context 'when scout_v2 feature flag is enabled' do
      let(:cad_orcamento) do
        CustomAttributeDefinition.create!(
          account: account,
          attribute_display_name: 'Orçamento',
          attribute_key: 'orcamento',
          attribute_model: :opportunity_attribute,
          attribute_display_type: :text
        )
      end

      let(:gemini_step) do
        lambda do |parts|
          {
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: { candidates: [{ content: { role: 'model', parts: parts } }] }.to_json
          }
        end
      end

      before do
        account.enable_features!('scout_v2', 'opportunities')
        scout.update!(
          default_pipeline_stage: PipelineStage.create!(account: account, name: 'Lead', position: 0),
          qualified_stage: PipelineStage.create!(account: account, name: 'Qualificado', position: 1),
          unqualified_stage: PipelineStage.create!(account: account, name: 'Desqualificado', position: 2)
        )
        scout.sync_required_attribute_ids!([cad_orcamento.id])
        ScoutAccountConfig.create!(account_id: account.id, api_key: 'test-key', model_name: 'gemini-2.0-flash')
      end

      it 'dispatches via real TurnRunner, creates an outgoing Message, and increments responses_consumed' do
        last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
        enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)
        Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key, true)

        provider_requests = []
        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .with { |req| provider_requests << JSON.parse(req.body) }
          .to_return(
            gemini_step.call([{ text: 'Olá! Como posso ajudar?' }])
          )

        expect do
          described_class.new.perform(conversation.id)
        end.to change { conversation.messages.where(message_type: :outgoing).count }.by(1)

        expect(scout.reload.responses_consumed).to eq(1)
        expect(conversation.messages.where(message_type: :outgoing).last.content).to include('Olá')
      end

      it 'verifies T081: chained exits (exit_qualificado → exit_handoff) record state transitions properly' do
        # Setup: Opportunity and complete contact identity for qualificacao
        contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
        lead_stage = PipelineStage.find_by(account: account, name: 'Lead')
        Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: lead_stage,
          origin_conversation: conversation,
          active_conversation: conversation,
          title: 'Test Deal',
          status: :open,
          custom_attributes: { 'orcamento' => '50000' }
        )

        # Pin qualificacao by state
        state = ScoutConversationState.for_conversation(conversation)
        state.record_state_activation!('qualificacao')

        # Stub Gemini API with chained tool calls
        provider_requests = []
        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .with { |req| provider_requests << JSON.parse(req.body) }
          .to_return(
            gemini_step.call([{ functionCall: { name: 'exit_qualificado', args: {} } }]),
            gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Cliente transferido' } } }]),
            gemini_step.call([{ text: 'Transferindo para um atendente.' }])
          )

        last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
        enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)
        Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key, true)

        expect do
          described_class.new.perform(conversation.id)
        end.to change { conversation.messages.where(message_type: :outgoing).count }.by(2)

        # Verify state shows both playbooks completed and handoff exit recorded
        state.reload
        expect(state.completed_playbooks).to include('qualificacao')
        expect(state.completed_playbooks).to include('agendamento')
        expect(state.last_exit).to eq('handoff')

        # Verify unsatisfied_flags attributes three items to agendamento
        unsatisfied = state.unsatisfied_flags || {}
        expect(unsatisfied['procedure']).to eq('agendamento')
        expect(unsatisfied['unmet_requires']).to match_array(%w[scheduling customer_registry])
      end

      it 'verifies US1-AS7: a new conversation for the same incomplete contact pins identificacao again, independently', :aggregate_failures do
        contact.update!(name: 'lindo-peixe-123', phone_number: nil)

        provider_requests = []
        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .with { |req| provider_requests << JSON.parse(req.body) }
          .to_return(
            gemini_step.call([{ functionCall: { name: 'update_contact', args: { name: 'Carlos Silva' } } }]),
            gemini_step.call([{ functionCall: { name: 'exit_identificado', args: {} } }]),
            gemini_step.call([{ text: 'Obrigado, Carlos!' }])
          )

        last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
        enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)
        Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key, true)

        described_class.new.perform(conversation.id)

        state_a = ScoutConversationState.for_conversation(conversation).reload
        expect(state_a.completed_playbooks).to include('identificacao')

        conversation_b = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :pending)

        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .with { |req| provider_requests << JSON.parse(req.body) }
          .to_return(gemini_step.call([{ text: 'Olá! Como posso te chamar?' }]))

        last_msg_key_b = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation_b.id)
        enqueued_key_b = format(described_class::ENQUEUED_KEY, conversation_id: conversation_b.id)
        Redis::Alfred.set(last_msg_key_b, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key_b, true)

        described_class.new.perform(conversation_b.id)

        state_b = ScoutConversationState.for_conversation(conversation_b).reload
        expect(state_b.active_playbook).to eq('identificacao')
        expect(state_b.activation_reason).to eq('state')
        expect(state_b.completed_playbooks).to eq([])
        expect(state_a.reload.completed_playbooks).to include('identificacao')
      end

      it 'verifies US1-AS12: qualificacao pinned by state and exit_handoff transfers with qualificacao completed', :aggregate_failures do
        contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
        state = ScoutConversationState.for_conversation(conversation)
        state.record_state_activation!('qualificacao')

        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .to_return(
            gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Cliente pediu atendimento humano' } } }]),
            gemini_step.call([{ text: 'Transferindo para um atendente.' }])
          )

        last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
        enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)
        Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key, true)

        described_class.new.perform(conversation.id)

        expect(conversation.reload.status).to eq('open')
        state.reload
        expect(state.last_exit).to eq('handoff')
        expect(state.completed_playbooks).to include('qualificacao')
      end

      it 'verifies FR-026: escalation with nothing in effect adds nothing to completed_playbooks', :aggregate_failures do
        contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
        lead_stage = PipelineStage.find_by(account: account, name: 'Lead')
        Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: lead_stage,
          origin_conversation: conversation,
          active_conversation: conversation,
          title: 'Deal sem pendências',
          status: :open,
          custom_attributes: { 'orcamento' => '50000' }
        )

        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .to_return(
            gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Cliente pediu atendimento humano' } } }]),
            gemini_step.call([{ text: 'Transferindo para um atendente.' }])
          )

        last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
        enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)
        Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key, true)

        described_class.new.perform(conversation.id)

        state = ScoutConversationState.for_conversation(conversation).reload
        expect(state.active_playbook).to be_nil
        expect(state.last_exit).to eq('handoff')
        expect(state.completed_playbooks).to eq([])
      end

      it 'verifies US2-AS1: opening fora_de_prospeccao mid-turn with identificacao pinned ends transferred with identificacao completed',
         :aggregate_failures do
        contact.update!(name: 'lindo-peixe-123', phone_number: nil)
        state = ScoutConversationState.for_conversation(conversation)
        state.record_state_activation!('identificacao')

        provider_requests = []
        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .with { |req| provider_requests << JSON.parse(req.body) }
          .to_return(
            gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'fora_de_prospeccao' } } }]),
            gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Fora do escopo de prospecção' } } }]),
            gemini_step.call([{ text: 'Transferindo para um atendente.' }])
          )

        last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
        enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)
        Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key, true)

        described_class.new.perform(conversation.id)

        tools_after_open = provider_requests[1].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
        expect(tools_after_open).to contain_exactly('search_knowledge_base', 'exit_handoff', 'open_playbook')

        state.reload
        expect(state.last_exit).to eq('handoff')
        expect(state.completed_playbooks).to include('identificacao')
      end

      it 'verifies US2-AS1: opening fora_de_prospeccao mid-turn with qualificacao pinned ends transferred with qualificacao completed',
         :aggregate_failures do
        contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
        state = ScoutConversationState.for_conversation(conversation)
        state.record_state_activation!('qualificacao')

        provider_requests = []
        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .with { |req| provider_requests << JSON.parse(req.body) }
          .to_return(
            gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'fora_de_prospeccao' } } }]),
            gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Fora do escopo de prospecção' } } }]),
            gemini_step.call([{ text: 'Transferindo para um atendente.' }])
          )

        last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
        enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)
        Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key, true)

        described_class.new.perform(conversation.id)

        tools_after_open = provider_requests[1].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
        expect(tools_after_open).to contain_exactly('search_knowledge_base', 'exit_handoff', 'open_playbook')

        state.reload
        expect(state.last_exit).to eq('handoff')
        expect(state.completed_playbooks).to include('qualificacao')
      end

      it 'verifies US2-AS1 (agendamento variant): opening fora_de_prospeccao with agendamento pinned leaves no PENDENTE text after the opening',
         :aggregate_failures do
        contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
        qualified_stage = PipelineStage.find_by(account: account, name: 'Qualificado')
        Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: qualified_stage,
          origin_conversation: conversation,
          active_conversation: conversation,
          title: 'Deal Qualificado',
          status: :open,
          custom_attributes: {}
        )
        state = ScoutConversationState.for_conversation(conversation)
        state.record_state_activation!('agendamento')

        provider_requests = []
        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .with { |req| provider_requests << JSON.parse(req.body) }
          .to_return(
            gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'fora_de_prospeccao' } } }]),
            gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Fora do escopo de prospecção' } } }]),
            gemini_step.call([{ text: 'Transferindo para um atendente.' }])
          )

        last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
        enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)
        Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key, true)

        described_class.new.perform(conversation.id)

        request_after_open = provider_requests[1].dig('contents', 0, 'parts', 0, 'text') ||
                             provider_requests[1].dig('systemInstruction', 'parts', 0, 'text')
        expect(request_after_open).not_to include('PENDENTE')

        state.reload
        expect(state.completed_playbooks).to include('agendamento')
      end

      it 'verifies US3-AS9/SC-010: qualified lead transferred with agendamento in effect, hand-back leaves nothing pinned',
         :aggregate_failures do
        contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
        qualified_stage = PipelineStage.find_by(account: account, name: 'Qualificado')
        Opportunity.create!(
          account: account,
          contact: contact,
          pipeline_stage: qualified_stage,
          origin_conversation: conversation,
          active_conversation: conversation,
          title: 'Deal Qualificado',
          status: :open,
          custom_attributes: { 'orcamento' => '50000' }
        )
        state = ScoutConversationState.for_conversation(conversation)
        state.record_state_activation!('agendamento')

        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .to_return(
            gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Sem horários disponíveis no momento' } } }]),
            gemini_step.call([{ text: 'Transferindo para um atendente.' }])
          )

        last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
        enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)
        Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key, true)

        described_class.new.perform(conversation.id)

        state.reload
        expect(state.last_exit).to eq('handoff')
        expect(state.completed_playbooks).to include('agendamento')
        transfer_notes_before = conversation.messages.where(private: true).count

        conversation.reload.update!(status: :pending)

        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .to_return(gemini_step.call([{ text: 'Por nada!' }]))

        last_msg_key2 = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
        enqueued_key2 = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)
        Redis::Alfred.set(last_msg_key2, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key2, true)

        described_class.new.perform(conversation.id)

        state.reload
        expect(state.active_playbook).to be_nil
        expect(state.last_exit).to eq('handoff')
        expect(conversation.reload.status).to eq('pending')
        expect(conversation.messages.where(private: true).count).to eq(transfer_notes_before)
      end

      it 'verifies fail-safe edge: empty final output with qualificacao pinned transfers without marking anything completed', :aggregate_failures do
        contact.update!(name: 'Carlos Silva', phone_number: '+5511999999999')
        state = ScoutConversationState.for_conversation(conversation)
        state.record_state_activation!('qualificacao')

        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .to_return(gemini_step.call([{ text: '' }]))

        last_msg_key = format(described_class::LAST_MESSAGE_KEY, conversation_id: conversation.id)
        enqueued_key = format(described_class::ENQUEUED_KEY, conversation_id: conversation.id)
        Redis::Alfred.set(last_msg_key, Time.current.to_f - 5.0)
        Redis::Alfred.set(enqueued_key, true)

        described_class.new.perform(conversation.id)

        expect(conversation.reload.status).to eq('open')
        state.reload
        expect(state.completed_playbooks).to eq([])
        expect(state.active_playbook).to eq('qualificacao')
        expect(state.unsatisfied_flags['procedure']).to eq('qualificacao')
      end
    end
  end
end
