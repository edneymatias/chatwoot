# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Playground Scheduling (US3)', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:lead_stage) { PipelineStage.create!(account: account, name: 'Lead', position: 0) }
  let(:qualified_stage) { PipelineStage.create!(account: account, name: 'Qualificado', position: 1) }
  let(:unqualified_stage) { PipelineStage.create!(account: account, name: 'Desqualificado', position: 2) }

  let(:scout) do
    Scout.create!(
      account: account,
      name: 'V2 Scheduling Scout',
      enabled: true,
      default_pipeline_stage: lead_stage,
      qualified_stage: qualified_stage,
      unqualified_stage: unqualified_stage
    )
  end

  let(:hook) do
    create(
      :integrations_hook,
      account: account,
      app_id: 'younus',
      status: :enabled,
      settings: {
        'token' => 'secret-erp-token-999',
        'id_empresa' => '648',
        'id_usuario' => '172793',
        'id_convenio' => '1',
        'nr_convenio' => 'Particular',
        'id_origem_pessoa' => '11',
        'id_agenda' => '3',
        'id_servico' => '1'
      }
    )
  end

  let(:sandbox_conversation) { Custom::ScoutV2::PlaygroundConversation.for(scout) }
  let(:contact) { sandbox_conversation.contact }
  let(:provider_requests) { [] }
  let(:fixtures_path) { Rails.root.join('custom/spec/fixtures/erp/younus') }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

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
    stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar\?.*nrTelcelpessoa=0})
      .to_return(status: 200, body: { sucesso: true, dados: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
    account.enable_features!('scout', 'scout_v2', 'opportunities', 'erp_integration')
    ScoutAccountConfig.create!(account_id: account.id, api_key: 'test-key', model_name: 'gemini-2.0-flash')
    hook # ensure hook exists
  end

  def post_message(text, history: [])
    provider_requests.clear
    post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
         params: { message: text, message_history: history },
         headers: agent.create_new_auth_token
  end

  def system_text
    provider_requests.first.dig('systemInstruction', 'parts', 0, 'text') ||
      provider_requests.first.dig('contents', 0, 'parts', 0, 'text')
  end

  def create_qualified_opportunity
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: qualified_stage,
      origin_conversation: sandbox_conversation,
      active_conversation: sandbox_conversation,
      title: 'Deal Qualificado',
      status: :open
    )
  end

  describe 'T037a [US3]: Success paths' do
    before do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999990648')
    end

    it 'verifies AS1: scripted qualification pins scheduling by transition in the same turn', :aggregate_failures do
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: lead_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal',
        status: :open,
        custom_attributes: {}
      )

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      state.record_state_activation!('qualificacao')

      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar})
        .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_found.json"), headers: { 'Content-Type' => 'application/json' })

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'exit_qualificado', args: {} } }]),
          gemini_step.call([{ functionCall: { name: 'customer_registry_find_by_phone', args: {} } }]),
          gemini_step.call([{ text: 'Qual dia prefere para o agendamento da consulta?' }])
        )

      post_message('Sim, tenho orçamento e interesse')
      expect(response).to have_http_status(:ok)

      state.reload
      expect(state.active_playbook).to eq('agendamento')
      expect(state.activation_reason).to eq('transition')
      expect(state.completed_playbooks).to include('qualificacao')
      expect(sandbox_conversation.active_opportunity.pipeline_stage).to eq(qualified_stage)

      tool_calls = response.parsed_body['tool_calls']
      expect(tool_calls.map { |tc| tc['tool_name'] }).to include('exit_qualificado', 'customer_registry_find_by_phone')
    end

    it 'verifies AS3: customer found (0 create requests) vs customer not found (customer_registry_create)', :aggregate_failures do
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: qualified_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal Qualificado',
        status: :open
      )

      # Part A: customer found -> 0 create requests
      find_body = File.read("#{fixtures_path}/find_person_found.json")
      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar})
        .to_return(status: 200, body: find_body, headers: json_headers)
      create_body = File.read("#{fixtures_path}/create_person.json")
      stub_create = stub_request(:post, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas})
                    .to_return(status: 200, body: create_body, headers: json_headers)

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'customer_registry_find_by_phone', args: {} } }]),
          gemini_step.call([{ text: 'Localizei seu cadastro. Qual dia deseja agendar?' }])
        )

      post_message('Olá, quero agendar')
      expect(response).to have_http_status(:ok)
      expect(a_request(:get, %r{wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar\?.*nrTelcelpessoa=[1-9]})).to have_been_made.once
      expect(stub_create).not_to have_been_requested

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.capability_state.dig('customer', 'id')).to eq('784868')

      # Part B: customer not found -> customer_registry_create
      state.update!(capability_state: {})
      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar})
        .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_none.json"), headers: { 'Content-Type' => 'application/json' })

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'customer_registry_find_by_phone', args: {} } }]),
          gemini_step.call([{ functionCall: { name: 'customer_registry_create', args: { name: 'Carlos Silva' } } }]),
          gemini_step.call([{ text: 'Cadastro criado com sucesso! Para quando deseja agendar?' }])
        )

      post_message('Meu nome é Carlos Silva')
      expect(response).to have_http_status(:ok)
      expect(stub_create).to have_been_requested
      state.reload
      expect(state.capability_state.dig('customer', 'id')).to eq('784868')
    end

    it 'verifies AS5 and FR-022: happy path to exit_agendado carrying booked start and reference', :aggregate_failures do
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: qualified_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal Qualificado',
        status: :open
      )

      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar})
        .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_found.json"), headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/horarios-livres})
        .to_return(status: 200, body: File.read("#{fixtures_path}/free_slots.json"), headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/agendamentos})
        .to_return(status: 200, body: File.read("#{fixtures_path}/create_appointment.json"), headers: { 'Content-Type' => 'application/json' })

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'customer_registry_find_by_phone', args: {} } }]),
          gemini_step.call([{ functionCall: { name: 'scheduling_list_slots', args: { date: '2026-10-15' } } }]),
          gemini_step.call([{ functionCall: { name: 'scheduling_book', args: { slot_id: '2026-10-15T08:00:00-03:00' } } }]),
          gemini_step.call([{ functionCall: { name: 'exit_agendado', args: {} } }]),
          gemini_step.call([{ text: 'Sua consulta foi agendada para 15/10/2026 às 08:00!' }])
        )

      post_message('Gostaria de agendar para 15/10 às 08:00')
      expect(response).to have_http_status(:ok)

      tool_calls = response.parsed_body['tool_calls']
      agendado_call = tool_calls.find { |tc| tc['tool_name'] == 'exit_agendado' }
      expect(agendado_call).to be_present
      result_text = agendado_call['result'].to_s
      expect(result_text).to include('4468657')
      expect(result_text).to include('2026-10-15')

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.completed_playbooks).to include('agendamento')
      expect(state.capability_state.dig('booking', 'appointment_id')).to eq('4468657')
      expect(state.capability_state.dig('booking', 'starts_at')).to eq('2026-10-15T08:00:00-03:00')

      # Hand-back after exit_agendado: flip to pending, follow-up message receives no scheduling tools or ERP calls (T084, US3/AC10, SC-007)
      sandbox_conversation.update!(status: :pending)
      WebMock.reset_executed_requests!
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Olá novamente! Como posso te ajudar hoje?' }]))

      post_message('Oi de novo')
      expect(response).to have_http_status(:ok)

      state.reload
      expect(state.active_playbook).not_to eq('agendamento')
      tools = provider_requests.first.dig('tools', 0, 'functionDeclarations').map { |f| f['name'] }
      expect(tools).not_to include('scheduling_list_slots', 'scheduling_book', 'exit_agendado')
      expect(WebMock).not_to have_requested(:any, %r{https://wfh\.ichatr\.com\.br/webhook/.*})
    end

    it 'verifies AS6: nearest-date path over at most three following days', :aggregate_failures do
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: qualified_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal Qualificado',
        status: :open
      )

      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar})
        .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_found.json"), headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/horarios-livres\?.*data=2026-10-15})
        .to_return(status: 200, body: File.read("#{fixtures_path}/free_slots_empty.json"), headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/horarios-livres\?.*data=2026-10-16})
        .to_return(
          status: 200,
          body: { sucesso: true, mensagem: 'OK', dados: ['2026-10-16 08:00', '2026-10-16 08:40'] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
      stub_request(:post, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/agendamentos})
        .to_return(status: 200, body: File.read("#{fixtures_path}/create_appointment.json"), headers: { 'Content-Type' => 'application/json' })

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'customer_registry_find_by_phone', args: {} } }]),
          gemini_step.call([{ functionCall: { name: 'scheduling_list_slots', args: { date: '2026-10-15' } } }]),
          gemini_step.call([{ functionCall: { name: 'scheduling_list_slots', args: { date: '2026-10-16' } } }]),
          gemini_step.call([{ functionCall: { name: 'scheduling_book', args: { slot_id: '2026-10-16T08:00:00-03:00' } } }]),
          gemini_step.call([{ functionCall: { name: 'exit_agendado', args: {} } }]),
          gemini_step.call([{ text: 'Agendado para o dia 16/10 às 08:00!' }])
        )

      post_message('Gostaria de agendar para 15/10')
      expect(response).to have_http_status(:ok)

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.completed_playbooks).to include('agendamento')
      expect(state.capability_state['booking']).to be_present
      expect(state.capability_state['booking']['starts_at']).to eq('2026-10-16T08:00:00-03:00')
      expect(state.capability_state['booking']['appointment_id']).to eq('4468657')
      expect(a_request(:get, %r{wfh\.ichatr\.com\.br/webhook/.*/horarios-livres\?.*data=2026-10-19})).not_to have_been_made
    end

    it 'verifies AS7: no-slot path triggering exit_sem_horario with motivo', :aggregate_failures do
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: qualified_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal Qualificado',
        status: :open
      )

      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar})
        .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_found.json"), headers: { 'Content-Type' => 'application/json' })
      slot_req = stub_request(:get, %r{https://wfh\.ichatr\.com\.br/webhook/api/v1/empresas/agendas/horarios-livres})
                 .to_return(status: 200, body: File.read("#{fixtures_path}/free_slots_empty.json"),
                            headers: { 'Content-Type' => 'application/json' })

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'scheduling_list_slots', args: { date: '2026-10-15' } } }]),
          gemini_step.call([{ functionCall: { name: 'scheduling_list_slots', args: { date: '2026-10-16' } } }]),
          gemini_step.call([{ functionCall: { name: 'scheduling_list_slots', args: { date: '2026-10-17' } } }]),
          gemini_step.call([{ functionCall: { name: 'scheduling_list_slots', args: { date: '2026-10-18' } } }]),
          gemini_step.call([{ functionCall: { name: 'exit_sem_horario', args: { motivo: 'sem disponibilidade nos próximos dias' } } }]),
          gemini_step.call([{ text: 'Infelizmente não temos horários disponíveis no momento.' }])
        )

      post_message('Tem vaga dia 15/10?')
      expect(response).to have_http_status(:ok)

      tool_calls = response.parsed_body['tool_calls']
      sem_horario_call = tool_calls.find { |tc| tc['tool_name'] == 'exit_sem_horario' }
      expect(sem_horario_call).to be_present
      expect(sem_horario_call['arguments']).to eq({ 'motivo' => 'sem disponibilidade nos próximos dias' })

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.last_exit).to eq('sem_horario')
      expect(state.completed_playbooks).to include('agendamento')

      # Probed the requested date plus at most three following days (4 calls total, none beyond 2026-10-18)
      expect(slot_req).to have_been_requested.times(4)
      expect(a_request(:get, %r{wfh\.ichatr\.com\.br/webhook/.*/horarios-livres\?.*data=2026-10-19})).not_to have_been_made

      # Hand-back after exit_sem_horario: flip to pending, follow-up message receives no scheduling tools or ERP calls (T084, US3/AC10, SC-007)
      sandbox_conversation.update!(status: :pending)
      WebMock.reset_executed_requests!
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Olá! Como posso ajudar você agora?' }]))

      post_message('Tem vaga agora?')
      expect(response).to have_http_status(:ok)

      state.reload
      expect(state.active_playbook).not_to eq('agendamento')
      tools = provider_requests.first.dig('tools', 0, 'functionDeclarations').map { |f| f['name'] }
      expect(tools).not_to include('scheduling_list_slots', 'scheduling_book', 'exit_agendado')
      expect(WebMock).not_to have_requested(:any, %r{https://wfh\.ichatr\.com\.br/webhook/.*})
    end

    it 'verifies SC-004: booking within four lead messages', :aggregate_failures do
      create_qualified_opportunity
      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar})
        .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_found.json"), headers: json_headers)
      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/horarios-livres})
        .to_return(status: 200, body: File.read("#{fixtures_path}/free_slots.json"), headers: json_headers)
      stub_request(:post, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/agendamentos})
        .to_return(status: 200, body: File.read("#{fixtures_path}/create_appointment.json"), headers: json_headers)

      lead_messages_count = 0
      send_step = lambda do |text, history, *steps|
        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .with { |req| provider_requests << JSON.parse(req.body) }.to_return(*steps)
        post_message(text, history: history)
        expect(response).to have_http_status(:ok)
        lead_messages_count += 1
      end

      send_step.call('Olá, gostaria de agendar', [],
                     gemini_step.call([{ functionCall: { name: 'customer_registry_find_by_phone', args: {} } }]),
                     gemini_step.call([{ text: 'Olá Carlos! Qual dia prefere para sua consulta?' }]))

      history = [{ role: 'user', content: 'Olá, gostaria de agendar' }, { role: 'assistant', content: 'Olá Carlos!' }]
      send_step.call('Dia 15/10 por favor', history,
                     gemini_step.call([{ functionCall: { name: 'scheduling_list_slots', args: { date: '2026-10-15' } } }]),
                     gemini_step.call([{ text: 'Temos os horários 08:00, 08:40 e 09:20. Qual prefere?' }]))

      history = [{ role: 'user', content: 'Dia 15/10' }, { role: 'assistant', content: 'Temos 08:00' }]
      send_step.call('Pode ser às 08:00', history,
                     gemini_step.call([{ functionCall: { name: 'scheduling_book', args: { slot_id: '2026-10-15T08:00:00-03:00' } } }]),
                     gemini_step.call([{ functionCall: { name: 'exit_agendado', args: {} } }]),
                     gemini_step.call([{ text: 'Perfeito! Sua consulta está confirmada para 15/10 às 08:00.' }]))

      expect(lead_messages_count).to be <= 4

      tool_calls = response.parsed_body['tool_calls']
      agendado_call = tool_calls.find { |tc| tc['tool_name'] == 'exit_agendado' }
      expect(agendado_call).to be_present
      result_text = agendado_call['result'].to_s
      expect(result_text).to include('2026-10-15T08:00:00-03:00')
      expect(result_text).to include('4468657')
      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.completed_playbooks).to include('agendamento')
      expect(state.capability_state['booking']['starts_at']).to eq('2026-10-15T08:00:00-03:00')
      expect(state.capability_state['booking']['appointment_id']).to eq('4468657')
    end
  end

  describe 'T037b [US3]: Handoff and rejection paths' do
    before do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999990648')
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: qualified_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal Qualificado',
        status: :open
      )
    end

    it 'verifies AS8: transfers on human request, clinical urgency, or two ambiguous lookups', :aggregate_failures do
      # Part A: Human request
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Cliente solicitou atendente humano' } } }]),
          gemini_step.call([{ text: 'Estou transferindo para nossa equipe humana.' }])
        )

      post_message('Quero falar com uma pessoa')
      expect(response).to have_http_status(:ok)

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.last_exit).to eq('handoff')
      expect(state.completed_playbooks).to include('agendamento')
      handoff_call = response.parsed_body['tool_calls'].find { |tc| tc['tool_name'] == 'exit_handoff' }
      expect(handoff_call).to be_present
      expect(handoff_call['result']).to include('Transferência para atendimento humano realizada')

      # Part B: Clinical urgency
      state.update!(completed_playbooks: [], last_exit: nil)
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Urgência clínica informada pelo cliente' } } }]),
          gemini_step.call([{ text: 'Estou transferindo imediatamente devido à urgência informada.' }])
        )

      post_message('Estou sentindo uma dor aguda e falta de ar')
      expect(response).to have_http_status(:ok)

      state.reload
      expect(state.last_exit).to eq('handoff')
      expect(state.completed_playbooks).to include('agendamento')
      urgency_call = response.parsed_body['tool_calls'].find { |tc| tc['tool_name'] == 'exit_handoff' }
      expect(urgency_call).to be_present
      expect(urgency_call['result']).to include('Transferência para atendimento humano realizada')

      # Part C: Two ambiguous lookups
      state.update!(completed_playbooks: [], last_exit: nil)
      stub_request(:get, %r{https://wfh\.ichatr\.com\.br/webhook/api/v1/empresas/pessoas/pesquisar})
        .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_multiple.json"),
                   headers: { 'Content-Type' => 'application/json' })

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'customer_registry_find_by_phone', args: {} } }]),
          gemini_step.call([{ functionCall: { name: 'customer_registry_find_by_phone', args: {} } }]),
          gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Duas tentativas com cadastro ambíguo' } } }]),
          gemini_step.call([{ text: 'Vou transferir seu atendimento para um atendente.' }])
        )

      post_message('Oi, quero agendar')
      expect(response).to have_http_status(:ok)

      state.reload
      expect(state.last_exit).to eq('handoff')
      expect(state.completed_playbooks).to include('agendamento')
      ambiguous_call = response.parsed_body['tool_calls'].find { |tc| tc['tool_name'] == 'exit_handoff' }
      expect(ambiguous_call).to be_present
      expect(ambiguous_call['result']).to include('Transferência para atendimento humano realizada')
      expect(a_request(:get, %r{wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar\?.*nrTelcelpessoa=[1-9]})).to have_been_made.twice
    end

    it 'verifies hand-back after transfer exit_handoff (T084, US3/AC10, SC-007)', :aggregate_failures do
      state = ScoutConversationState.for_conversation(sandbox_conversation)
      state.record_terminal_exit!('handoff', completed: 'agendamento')

      # Hand-back after exit_handoff: flip to pending, follow-up message receives no scheduling tools or ERP calls
      sandbox_conversation.update!(status: :pending)
      WebMock.reset_executed_requests!
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Olá! A equipe devolveu o atendimento, como posso ajudar?' }]))

      post_message('Oi de novo')
      expect(response).to have_http_status(:ok)

      state.reload
      expect(state.active_playbook).not_to eq('agendamento')
      tools = provider_requests.first.dig('tools', 0, 'functionDeclarations').map { |f| f['name'] }
      expect(tools).not_to include('scheduling_list_slots', 'scheduling_book', 'exit_agendado')
      expect(WebMock).not_to have_requested(:any, %r{https://wfh\.ichatr\.com\.br/webhook/.*})
    end

    it 'verifies AS9: scheduled exit without booking is rejected with state unchanged', :aggregate_failures do
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'exit_agendado', args: {} } }]),
          gemini_step.call([{ text: 'Não pude concluir o agendamento ainda.' }])
        )

      post_message('Pode marcar aí')
      expect(response).to have_http_status(:ok)

      tool_calls = response.parsed_body['tool_calls']
      agendado_call = tool_calls.find { |tc| tc['tool_name'] == 'exit_agendado' }
      expect(agendado_call).to be_present
      expect(agendado_call['result']['error']).to include('Você ainda não realizou nenhum agendamento nesta conversa')

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.completed_playbooks).not_to include('agendamento')
      expect(state.capability_state['booking']).to be_nil
    end

    it 'verifies AS11: no-phone lead triggers exit_handoff stating phone is missing with 0 ERP requests', :aggregate_failures do
      contact.update!(phone_number: nil)

      Opportunity.where(active_conversation: sandbox_conversation).destroy_all
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: lead_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal',
        status: :open
      )

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      state.update!(completed_playbooks: ['identificacao'])
      state.record_state_activation!('qualificacao')

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'exit_qualificado', args: {} } }]),
          gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Contato sem telefone registrado' } } }]),
          gemini_step.call([{ text: 'Transferindo para atendimento humano pois não há telefone registrado.' }])
        )

      WebMock.reset_executed_requests!
      post_message('Tudo qualificado')
      expect(response).to have_http_status(:ok)

      tool_calls = response.parsed_body['tool_calls']
      expect(tool_calls.map { |tc| tc['tool_name'] }).to include('exit_qualificado', 'exit_handoff')

      # Check transition result contains PHONE_MISSING_NOTICE
      qual_call = tool_calls.find { |tc| tc['tool_name'] == 'exit_qualificado' }
      expect(qual_call['result'].to_s).to include('O contato não tem telefone registrado')

      expect(WebMock).not_to have_requested(:any, %r{https://wfh.ichatr.com.br/webhook/.*})

      state.reload
      expect(state.completed_playbooks).to include('agendamento')
    end

    it 'verifies AS12 and SC-009: ERP timeout / credential rejection transfers in same turn with no booking promise', :aggregate_failures do
      # Credential failure 401
      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar})
        .to_return(status: 401, body: File.read("#{fixtures_path}/error_unauthorized.txt"))

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'customer_registry_find_by_phone', args: {} } }]),
          gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Falha de integração ERP' } } }]),
          gemini_step.call([{ text: 'Não foi possível acessar o sistema. Vou transferir para um atendente.' }])
        )

      post_message('Quero agendar consulta')
      expect(response).to have_http_status(:ok)

      tool_calls = response.parsed_body['tool_calls']
      find_call = tool_calls.find { |tc| tc['tool_name'] == 'customer_registry_find_by_phone' }
      expect(find_call['result']['error']).to include('O sistema do cliente recusou as credenciais configuradas')

      handoff_call = tool_calls.find { |tc| tc['tool_name'] == 'exit_handoff' }
      expect(handoff_call).to be_present

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      expect(state.completed_playbooks).to include('agendamento')
      expect(state.capability_state['booking']).to be_nil
    end
  end

  describe 'T037c [US3]: State paths' do
    before do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999990648')
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: qualified_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal Qualificado',
        status: :open
      )
    end

    it 'verifies AS10 and SC-007: no re-pinning after scheduled, no-slot or transfer', :aggregate_failures do
      state = ScoutConversationState.for_conversation(sandbox_conversation)
      state.update!(completed_playbooks: ['agendamento'])

      WebMock.reset_executed_requests!

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Olá! Como posso ajudar?' }]))

      post_message('Oi de novo')
      expect(response).to have_http_status(:ok)

      state.reload
      expect(state.active_playbook).not_to eq('agendamento')
      tools = provider_requests.first.dig('tools', 0, 'functionDeclarations').map { |f| f['name'] }
      expect(tools).not_to include('scheduling_list_slots', 'scheduling_book', 'exit_agendado')
      expect(WebMock).not_to have_requested(:any, %r{https://wfh\.ichatr\.com\.br/webhook/.*})
    end

    it 'verifies AS13 and SC-003: degraded account keeps Brief 06 behavior with 0 ERP requests and unsatisfied items', :aggregate_failures do
      # Degrade account: remove agenda and service from hook
      hook.update!(settings: { 'token' => 'abc', 'id_empresa' => '648' })

      WebMock.reset_executed_requests!

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Olá, em breve atendemos você.' }]))

      post_message('Oi')
      expect(response).to have_http_status(:ok)

      expect(system_text).to include('(PENDENTE — indisponível: scheduling)')
      expect(WebMock).not_to have_requested(:any, %r{https://wfh.ichatr.com.br/webhook/.*})

      tools = provider_requests.first.dig('tools', 0, 'functionDeclarations').map { |f| f['name'] }
      expect(tools).not_to include('scheduling_list_slots', 'scheduling_book', 'exit_agendado')

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      unsatisfied = state.unsatisfied_flags
      expect(unsatisfied['unmet_requires']).to include('scheduling')
      expect(unsatisfied['unmet_needs']).to eq([])
    end

    it 'verifies AS2 and SC-011: satisfied account shows no pending step and empty unsatisfied items', :aggregate_failures do
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(gemini_step.call([{ text: 'Olá, vamos agendar.' }]))

      post_message('Oi')
      expect(response).to have_http_status(:ok)

      expect(system_text).not_to include('PENDENTE')
      tools = provider_requests.first.dig('tools', 0, 'functionDeclarations').map { |f| f['name'] }
      expect(tools).to include('customer_registry_find_by_phone', 'scheduling_list_slots', 'exit_agendado', 'exit_sem_horario')

      state = ScoutConversationState.for_conversation(sandbox_conversation)
      unsatisfied = state.unsatisfied_flags
      expect(unsatisfied['unmet_requires']).to eq([])
      expect(unsatisfied['unmet_needs']).to eq([])
    end
  end

  describe 'T037d [US1]: Contract-criterion (Principle VI)' do
    let(:exporter) { OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new }

    around do |example|
      InstallationConfig.where(name: %w[OTEL_PROVIDER LANGFUSE_BASE_URL LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY]).destroy_all
      InstallationConfig.create!(name: 'OTEL_PROVIDER', value: 'langfuse')
      InstallationConfig.create!(name: 'LANGFUSE_BASE_URL', value: 'https://cloud.langfuse.com')
      InstallationConfig.create!(name: 'LANGFUSE_PUBLIC_KEY', value: 'pk-lf-test')
      InstallationConfig.create!(name: 'LANGFUSE_SECRET_KEY', value: 'sk-lf-test')
      stub_request(:post, %r{https://cloud.langfuse.com/api/public/otel/v1/traces}).to_return(status: 200)

      OpentelemetryConfig.reset!
      OpentelemetryConfig.initialize!
      processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
      OpenTelemetry.tracer_provider.add_span_processor(processor)

      example.run

      begin
        OpenTelemetry.tracer_provider.shutdown
      rescue StandardError
        nil
      end
      OpentelemetryConfig.reset!
      InstallationConfig.where(name: %w[OTEL_PROVIDER LANGFUSE_BASE_URL LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY]).destroy_all
    end

    before do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999990648')
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: qualified_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal Qualificado',
        status: :open
      )
    end

    it 'verifies AS1-3 and SC-001: mistyped input gets { error: } with 0 requests and in-turn correction succeeds', :aggregate_failures do
      slots_stub = stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/horarios-livres})
                   .to_return(status: 200, body: File.read("#{fixtures_path}/free_slots.json"), headers: { 'Content-Type' => 'application/json' })

      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'scheduling_list_slots', args: { date: 'data-invalida' } } }]),
          gemini_step.call([{ functionCall: { name: 'scheduling_list_slots', args: { date: '2026-10-15' } } }]),
          gemini_step.call([{ text: 'Horários encontrados com sucesso!' }])
        )

      post_message('Quais os horários?')
      expect(response).to have_http_status(:ok)

      tool_calls = response.parsed_body['tool_calls']
      expect(tool_calls.size).to eq(2)
      expect(tool_calls.first['result']['error']).to include("campo 'date' deve ser uma data no formato YYYY-MM-DD")
      expect(tool_calls.second['result']['slots']).to be_an(Array)
      expect(slots_stub).to have_been_requested.once
    end

    it 'verifies AS4 and SC-008: ERP answer missing declared output field completes normally with deviation in trace', :aggregate_failures do
      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/horarios-livres})
        .to_return(
          status: 200,
          body: { sucesso: true, mensagem: 'OK', dados: [{ slot_id: 'slot-1' }] }.to_json,
          headers: json_headers
        )
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'scheduling_list_slots', args: { date: '2026-10-15' } } }]),
          gemini_step.call([{ text: 'Temos opções disponíveis!' }])
        )

      post_message('Tem vaga dia 15?')
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['reply']).to eq('Temos opções disponíveis!')

      tool_calls = response.parsed_body['tool_calls']
      slots_call = tool_calls.find { |tc| tc['tool_name'] == 'scheduling_list_slots' }
      expect(slots_call).to be_present
      expect(slots_call['result']['slots']).to eq([{ 'slot_id' => 'slot-1', 'starts_at' => nil }])

      cap_spans = exporter.finished_spans.select do |s|
        s.attributes['langfuse.observation.metadata.capability_call'].present?
      end
      slots_span = cap_spans.find do |s|
        JSON.parse(s.attributes['langfuse.observation.metadata.capability_call'])['operation'] == 'list_slots'
      end
      expect(slots_span).to be_present
      call_data = JSON.parse(slots_span.attributes['langfuse.observation.metadata.capability_call'])
      expect(call_data['deviations']).to include("campo de saída 'starts_at' ausente no item 0")
    end
  end

  describe 'T037e [US2]: Contract-criterion (Principle VI)' do
    let(:exporter) { OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new }

    around do |example|
      InstallationConfig.where(name: %w[OTEL_PROVIDER LANGFUSE_BASE_URL LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY]).destroy_all
      InstallationConfig.create!(name: 'OTEL_PROVIDER', value: 'langfuse')
      InstallationConfig.create!(name: 'LANGFUSE_BASE_URL', value: 'https://cloud.langfuse.com')
      InstallationConfig.create!(name: 'LANGFUSE_PUBLIC_KEY', value: 'pk-lf-test')
      InstallationConfig.create!(name: 'LANGFUSE_SECRET_KEY', value: 'sk-lf-test')
      stub_request(:post, %r{https://cloud.langfuse.com/api/public/otel/v1/traces}).to_return(status: 200)

      OpentelemetryConfig.reset!
      OpentelemetryConfig.initialize!
      processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
      OpenTelemetry.tracer_provider.add_span_processor(processor)

      example.run

      begin
        OpenTelemetry.tracer_provider.shutdown
      rescue StandardError
        nil
      end
      OpentelemetryConfig.reset!
      InstallationConfig.where(name: %w[OTEL_PROVIDER LANGFUSE_BASE_URL LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY]).destroy_all
    end

    before do
      contact.update!(name: 'Carlos Silva', phone_number: '+5511999990648')
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: qualified_stage,
        origin_conversation: sandbox_conversation,
        active_conversation: sandbox_conversation,
        title: 'Deal Qualificado',
        status: :open
      )
    end

    it 'verifies AS2-5, AS9, SC-002: ERP requests carry hook identifiers and contact phone, spans record injected, no token', :aggregate_failures do
      find_body = File.read("#{fixtures_path}/find_person_found.json")
      stub_find = stub_request(:get, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar')
                  .with(query: { idEmpresa: 648, nrTelcelpessoa: '11999990648' }, headers: { 'token' => 'secret-erp-token-999' })
                  .to_return(status: 200, body: find_body, headers: json_headers)

      slots_body = File.read("#{fixtures_path}/free_slots.json")
      stub_slots = stub_request(:get, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/horarios-livres')
                   .with(query: { data: '2026-10-15', idAgenda: 3, idEmpresa: 648, idServico: 1 }, headers: { 'token' => 'secret-erp-token-999' })
                   .to_return(status: 200, body: slots_body, headers: json_headers)

      app_payload = {
        idAgenda: 3, idPessoa: 784_868, nmTitulo: 'Teste Lead Scout', idEmpresa: 648, idServico: 1,
        idUsuario: 172_793, idConvenio: 1, dtIniAgenda: '2026-10-15T08:00:00-03:00', observacoes: 'Agendado por Scout'
      }
      stub_app = stub_request(:post, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/agendamentos')
                 .with(body: app_payload.to_json, headers: { 'token' => 'secret-erp-token-999' })
                 .to_return(status: 200, body: File.read("#{fixtures_path}/create_appointment.json"), headers: json_headers)
      stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
        .with { |req| provider_requests << JSON.parse(req.body) }
        .to_return(
          gemini_step.call([{ functionCall: { name: 'customer_registry_find_by_phone', args: {} } }]),
          gemini_step.call([{ functionCall: { name: 'scheduling_list_slots', args: { date: '2026-10-15', service: 'consulta-geral' } } }]),
          gemini_step.call([{ functionCall: { name: 'scheduling_book', args: { slot_id: '2026-10-15T08:00:00-03:00' } } }]),
          gemini_step.call([{ functionCall: { name: 'exit_agendado', args: {} } }]),
          gemini_step.call([{ text: 'Agendamento finalizado com sucesso!' }])
        )

      post_message('Quero agendar')
      expect(response).to have_http_status(:ok)

      expect(stub_find).to have_been_requested
      expect(stub_slots).to have_been_requested
      expect(stub_app).to have_been_requested

      # Spans verification: find finished spans with capability_call metadata
      cap_spans = exporter.finished_spans.select do |s|
        s.attributes['langfuse.observation.metadata.capability_call'].present?
      end

      expect(cap_spans).not_to be_empty
      injected_by_op = {}
      cap_spans.each do |s|
        raw_json = s.attributes['langfuse.observation.metadata.capability_call']
        expect(raw_json).not_to include('secret-erp-token-999')
        data = JSON.parse(raw_json)
        injected_by_op[data['operation']] = data['injected']
      end

      expect(injected_by_op['find_by_phone']).to eq({ 'id_empresa' => 648, 'phone' => '11999990648' })
      expect(injected_by_op['list_slots']).to eq({ 'id_agenda' => 3, 'id_empresa' => 648, 'id_servico' => 1 })
      expected_book_injected = {
        'id_agenda' => 3, 'id_convenio' => 1, 'id_empresa' => 648,
        'id_servico' => 1, 'id_usuario' => 172_793, 'person_id' => '784868'
      }
      expect(injected_by_op['book']).to eq(expected_book_injected)
    end
  end
end
