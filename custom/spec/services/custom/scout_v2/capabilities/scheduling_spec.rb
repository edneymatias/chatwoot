# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Capabilities::Scheduling do
  subject(:scheduling) { described_class.new(provider: provider, conversation: conversation) }

  let(:account) { create(:account) }
  let(:hook) do
    create(
      :integrations_hook,
      account: account,
      app_id: 'younus',
      settings: {
        'token' => 'secret-erp-token-999',
        'id_empresa' => '648',
        'id_usuario' => '172793',
        'id_convenio' => '1',
        'nr_convenio' => '12345',
        'id_origem_pessoa' => '11',
        'id_agenda' => '3',
        'id_servico' => '1'
      }
    )
  end
  let(:provider) { Erp::Younus::Adapter.new(hook) }
  let(:conversation) { create(:conversation, account: account) }
  let(:fixtures_path) { Rails.root.join('custom/spec/fixtures/erp/younus') }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  before do
    account.enable_features!('erp_integration')
    stub_request(:get, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar')
      .with(query: { idEmpresa: 648, nrTelcelpessoa: '0' }, headers: { 'token' => 'secret-erp-token-999' })
      .to_return(status: 200, body: { sucesso: true, dados: [] }.to_json, headers: json_headers)
  end

  describe '#check_preconditions_for_book' do
    let(:state) { ScoutConversationState.for_conversation(conversation) }

    it 'rejects when an earlier booking already exists before any request (FR-028, US2-AS11)' do
      state.update!(capability_state: {
                      'booking' => { 'appointment_id' => '999', 'starts_at' => '2026-10-15T08:00:00-03:00' },
                      'customer' => { 'id' => '123' },
                      'offered_slots' => { '2026-10-15T09:00:00-03:00' => '2026-10-15T09:00:00-03:00' }
                    })

      error = scheduling.check_preconditions_for_book(slot_id: '2026-10-15T09:00:00-03:00')
      expect(error).to eq(
        'Já existe um agendamento confirmado nesta conversa. Não agende novamente; encerre com exit_agendado.'
      )
      expect(WebMock).not_to have_requested(:any, %r{wfh\.ichatr\.com\.br/webhook/api/v1/empresas/agendas/agendamentos})
    end

    it 'rejects when customer is not resolved in this conversation before any request (FR-013)' do
      state.update!(capability_state: {
                      'offered_slots' => { '2026-10-15T09:00:00-03:00' => '2026-10-15T09:00:00-03:00' }
                    })

      error = scheduling.check_preconditions_for_book(slot_id: '2026-10-15T09:00:00-03:00')
      expect(error).to eq(
        'Nenhum cliente foi localizado ou cadastrado nesta conversa. ' \
        'Use customer_registry_find_by_phone (ou customer_registry_create) antes de agendar.'
      )
      expect(WebMock).not_to have_requested(:any, %r{wfh\.ichatr\.com\.br/webhook/api/v1/empresas/agendas/agendamentos})
    end

    it 'rejects when slot_id was never offered in this conversation before any request (FR-014)' do
      state.update!(capability_state: {
                      'customer' => { 'id' => '123' },
                      'offered_slots' => { '2026-10-15T09:00:00-03:00' => '2026-10-15T09:00:00-03:00' }
                    })

      error = scheduling.check_preconditions_for_book(slot_id: '2026-10-15T14:00:00-03:00')
      expect(error).to eq(
        "O horário '2026-10-15T14:00:00-03:00' não foi oferecido nesta conversa. " \
        'Liste os horários com scheduling_list_slots e escolha um dos retornados.'
      )
      expect(WebMock).not_to have_requested(:any, %r{wfh\.ichatr\.com\.br/webhook/api/v1/empresas/agendas/agendamentos})
    end

    it 'returns nil when all preconditions are satisfied' do
      state.update!(capability_state: {
                      'customer' => { 'id' => '123' },
                      'offered_slots' => { '2026-10-15T09:00:00-03:00' => '2026-10-15T09:00:00-03:00' }
                    })

      error = scheduling.check_preconditions_for_book(slot_id: '2026-10-15T09:00:00-03:00')
      expect(error).to be_nil
    end
  end

  describe '#book' do
    let(:state) { ScoutConversationState.for_conversation(conversation) }

    before do
      state.update!(capability_state: {
                      'customer' => { 'id' => '784868', 'name' => 'Teste Lead Scout' },
                      'offered_slots' => {
                        '2026-10-15T08:00:00-03:00' => '2026-10-15T08:00:00-03:00',
                        '2026-10-16T09:00:00-03:00' => '2026-10-16T09:00:00-03:00'
                      }
                    })
    end

    it 'books an offered slot, calls provider with customer and slot start, and remembers booking' do
      stub_request(:post, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/agendamentos')
        .with(headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 200, body: File.read("#{fixtures_path}/create_appointment.json"), headers: json_headers)

      result = scheduling.book(slot_id: '2026-10-15T08:00:00-03:00', notes: 'manhã')

      expect(result).to eq({
                             appointment_id: '4468657',
                             starts_at: '2026-10-15T08:00:00-03:00'
                           })
      expect(WebMock).to have_requested(:post, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/agendamentos')
        .with(body: hash_including({
                                     'idAgenda' => 3,
                                     'idPessoa' => 784_868,
                                     'nmTitulo' => 'Teste Lead Scout',
                                     'dtIniAgenda' => '2026-10-15T08:00:00-03:00'
                                   }))

      state.reload
      expect(state.capability_state['booking']).to eq({
                                                        'appointment_id' => '4468657',
                                                        'starts_at' => '2026-10-15T08:00:00-03:00'
                                                      })
    end

    it 'allows booking an earlier offered slot even after listing slots for another day' do
      stub_request(:get, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/horarios-livres')
        .with(query: { data: '2026-10-17', idAgenda: 3, idEmpresa: 648, idServico: 1 }, headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 200, body: { sucesso: true, dados: ['2026-10-17 14:00'] }.to_json, headers: json_headers)

      stub_request(:post, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/agendamentos')
        .with(headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 200, body: File.read("#{fixtures_path}/create_appointment.json"), headers: json_headers)

      scheduling.list_slots(date: '2026-10-17')

      result = scheduling.book(slot_id: '2026-10-15T08:00:00-03:00')
      expect(result[:appointment_id]).to eq('4468657')
    end

    it 'returns failure result and does not remember booking when response has no appointment_id (FR-028)' do
      body = {
        sucesso: true,
        mensagem: 'OK',
        dados: { nmTitulo: 'Teste Lead Scout' }
      }.to_json

      stub_request(:post, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/agendamentos')
        .with(headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 200, body: body, headers: json_headers)

      result = scheduling.book(slot_id: '2026-10-15T08:00:00-03:00')

      expect(result[:error]).to eq(
        'O sistema do cliente não confirmou o agendamento (resposta sem identificador); ' \
        'ele pode ter sido criado. Não repita a operação, não prometa nem confirme o agendamento; ' \
        'chame exit_handoff neste mesmo turno.'
      )

      state.reload
      expect(state.capability_state['booking']).to be_nil
    end

    it 'returns failure result and does not remember booking when response echoes idPessoa without appointment key' do
      body = {
        sucesso: true,
        mensagem: 'OK',
        dados: { idPessoa: 784_868, cd_pessoa: 784_868, nmTitulo: 'Teste Lead Scout' }
      }.to_json

      stub_request(:post, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/agendas/agendamentos')
        .with(headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 200, body: body, headers: json_headers)

      result = scheduling.book(slot_id: '2026-10-15T08:00:00-03:00')

      expect(result[:error]).to eq(
        'O sistema do cliente não confirmou o agendamento (resposta sem identificador); ' \
        'ele pode ter sido criado. Não repita a operação, não prometa nem confirme o agendamento; ' \
        'chame exit_handoff neste mesmo turno.'
      )

      state.reload
      expect(state.capability_state['booking']).to be_nil
    end
  end
end
