# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Capabilities::OperationTool do
  subject(:tool) do
    described_class.new(
      scout,
      conversation,
      capability_instance: capability,
      operation: operation
    )
  end

  let(:account) { create(:account) }
  let(:hook) do
    create(
      :integrations_hook,
      account: account,
      app_id: 'younus',
      status: :enabled,
      settings: {
        'token' => 'secret-token-123',
        'id_empresa' => '648',
        'id_usuario' => '172793',
        'id_agenda' => '3',
        'id_servico' => '1',
        'id_convenio' => '1'
      }
    )
  end
  let(:adapter) { Erp::Younus::Adapter.new(hook) }
  let(:capability) { Custom::ScoutV2::Capabilities::Scheduling.new(provider: adapter, conversation: conversation) }
  let(:operation) { capability.class.operations['list_slots'] }
  let(:conversation) { create(:conversation, account: account) }
  let(:scout) { Scout.create!(account: account, name: 'Test Scout', enabled: true) }
  let(:scope) do
    Custom::ScoutV2::TurnScope.new(
      chat: nil,
      catalog: Custom::ScoutV2::Playbook::Catalog.new([]),
      baseline_instructions: '',
      tool_wrapper: ->(t) { t }
    )
  end
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
    account.enable_features!('erp_integration')
    stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/pessoas})
      .to_return(status: 200, body: { sucesso: true, dados: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#execute strict input validation' do
    it 'returns error and makes 0 requests when required input is missing' do
      result = tool.execute({})
      expect(result).to have_key(:error)
      expect(result[:error]).to include("campo 'date' ausente")
      expect(WebMock).not_to have_requested(:get, /horarios-livres/)
    end

    it 'returns error and makes 0 requests when date format is invalid' do
      result = tool.execute(date: 'not-a-date')
      expect(result).to have_key(:error)
      expect(result[:error]).to include("campo 'date' deve ser uma data no formato YYYY-MM-DD")
      expect(WebMock).not_to have_requested(:get, /horarios-livres/)
    end

    it 'proceeds when optional input is omitted' do
      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/horarios-livres})
        .to_return(
          status: 200,
          body: { sucesso: true, mensagem: 'OK', horarios: ['2026-10-15 08:00'] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = tool.execute(date: '2026-10-15')
      expect(result).to have_key(:slots)
      expect(WebMock).to have_requested(:get, /horarios-livres/)
    end
  end

  describe 'ERP error handling and no retry' do
    let(:slots_url) { %r{https://wfh.ichatr.com.br/webhook/horarios-livres} }

    it 'returns definitive refusal text on Erp::AuthenticationError without retrying' do
      stub_request(:get, slots_url).to_return(status: 401, body: 'Unauthorized')

      result = tool.execute(date: '2026-10-15')
      expect(result[:error]).to eq(
        'O sistema do cliente recusou as credenciais configuradas; nada foi registrado. ' \
        'Não prometa nem confirme o agendamento; chame exit_handoff neste mesmo turno.'
      )
      expect(WebMock).to have_requested(:get, slots_url).once
    end

    it 'returns unknown outcome warning on timeout/server error without retrying' do
      stub_request(:get, slots_url).to_timeout

      result = tool.execute(date: '2026-10-15')
      expect(result[:error]).to eq(
        'O sistema do cliente não respondeu ou recusou a operação. Se era um cadastro ou agendamento, ' \
        'o resultado é desconhecido e pode ter sido concluído: não repita. ' \
        'Não prometa nem confirme o agendamento; chame exit_handoff neste mesmo turno.'
      )
      expect(WebMock).to have_requested(:get, slots_url).once
    end

    it 'returns unknown outcome warning and remembers no offered slots when slot listing answers sucesso: false' do
      stub_request(:get, slots_url)
        .to_return(
          status: 200,
          body: { sucesso: false, mensagem: 'Erro ao buscar horários' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      state = ScoutConversationState.for_conversation(conversation).tap(&:save!)

      result = tool.execute(date: '2026-10-15')
      expect(result[:error]).to eq(
        'O sistema do cliente não respondeu ou recusou a operação. Se era um cadastro ou agendamento, ' \
        'o resultado é desconhecido e pode ter sido concluído: não repita. ' \
        'Não prometa nem confirme o agendamento; chame exit_handoff neste mesmo turno.'
      )
      expect(WebMock).to have_requested(:get, slots_url).once

      state.reload
      expect(state.capability_state['offered_slots']).to be_blank
    end

    context 'with a write operation' do
      let(:operation) { capability.class.operations['book'] }
      let(:state) { ScoutConversationState.for_conversation(conversation) }
      let(:book_url) { %r{https://wfh.ichatr.com.br/webhook/incluir-agendamento} }

      before do
        state.update!(capability_state: {
                        'customer' => { 'id' => '784868', 'name' => 'Teste Lead Scout' },
                        'offered_slots' => { '2026-10-15T08:00:00-03:00' => '2026-10-15T08:00:00-03:00' }
                      })
      end

      it 'returns unknown outcome warning on connection reset without retrying and without ending turn' do
        stub_request(:post, book_url).to_raise(Errno::ECONNRESET)

        result = tool.execute(slot_id: '2026-10-15T08:00:00-03:00')
        expect(result[:error]).to eq(
          'O sistema do cliente não respondeu ou recusou a operação. Se era um cadastro ou agendamento, ' \
          'o resultado é desconhecido e pode ter sido concluído: não repita. ' \
          'Não prometa nem confirme o agendamento; chame exit_handoff neste mesmo turno.'
        )
        expect(WebMock).to have_requested(:post, book_url).once
        expect(scope.ended?).to be false
      end
    end
  end

  describe 'soft output and deviations' do
    it 'returns data and records deviations when declared required output fields are missing' do
      stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/horarios-livres})
        .to_return(
          status: 200,
          body: { sucesso: true, mensagem: 'OK', horarios: [{ slot_id: '1' }] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = nil
      tracer = OpenTelemetry.tracer_provider.tracer('test')
      tracer.in_span('test_span') do
        result = tool.execute(date: '2026-10-15')
      end

      expect(result).to eq({ slots: [{ slot_id: '1', starts_at: nil }] })
      finished_span = exporter.finished_spans.find { |s| s.name == 'test_span' }
      recorded_json = finished_span.attributes['langfuse.observation.metadata.capability_call']
      expect(recorded_json).to be_present
      metadata = JSON.parse(recorded_json)
      expect(metadata['deviations']).to include("campo de saída 'starts_at' ausente no item 0")
    end
  end

  describe 'US2: hidden configuration and injected identifiers (US2-AS1..5, AS9)' do
    it 'ensures no operation input declaration contains identifiers, credentials, or phone (US2-AS1)' do
      forbidden_keys = %w[
        token id_empresa id_usuario id_convenio nr_convenio id_origem_pessoa id_agenda id_servico
        idEmpresa idUsuario idConvenio nrConvenio idOrigempessoa idAgenda idServico phone nrTelcelpessoa
      ]

      [Custom::ScoutV2::Capabilities::Scheduling, Custom::ScoutV2::Capabilities::CustomerRegistry].each do |cap_class|
        cap_class.operations.each_value do |op|
          declared_inputs = op.inputs.map(&:name)
          expect(declared_inputs & forbidden_keys).to be_empty
        end
      end
    end

    it 'records assistant service in span inputs while request carries configured id_servico only and never token (US2-AS2..5, AS9)' do
      contact = create(:contact, account: account, phone_number: '+5511999990648')
      conversation.update!(contact: contact)

      slots_url = %r{https://wfh.ichatr.com.br/webhook/horarios-livres}
      stub_request(:get, slots_url)
        .to_return(
          status: 200,
          body: { sucesso: true, mensagem: 'OK', horarios: ['2026-10-15 08:00'] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      tracer = OpenTelemetry.tracer_provider.tracer('test')
      tracer.in_span('test_span') do
        tool.execute(date: '2026-10-15', service: 'consulta especializada')
      end

      finished_span = exporter.finished_spans.find { |s| s.name == 'test_span' }
      recorded_json = finished_span.attributes['langfuse.observation.metadata.capability_call']

      expect(WebMock).to have_requested(:get, 'https://wfh.ichatr.com.br/webhook/horarios-livres')
        .with(query: { data: '2026-10-15', idAgenda: 3, idEmpresa: 648, idServico: 1 })

      expect(recorded_json).to be_present
      metadata = JSON.parse(recorded_json)
      expect(metadata['inputs']).to eq({ 'date' => '2026-10-15', 'service' => 'consulta especializada' })
      expect(metadata['injected']).to eq({ 'id_empresa' => 648, 'id_agenda' => 3, 'id_servico' => 1 })
      expect(recorded_json).not_to include('secret-token-123')
      expect(metadata['injected']).not_to have_key('token')
    end

    it 'records nr_convenio as a string preserving leading zeros in injected hash for customer_registry_create (FR-017)' do
      hook.update!(
        settings: hook.settings.merge(
          'id_convenio' => '1',
          'nr_convenio' => '000123',
          'id_origem_pessoa' => '11'
        )
      )

      contact = create(:contact, account: account, phone_number: '+5511999990648')
      conversation.update!(contact: contact)

      customer_capability = Custom::ScoutV2::Capabilities::CustomerRegistry.new(provider: adapter, conversation: conversation)
      create_operation = customer_capability.class.operations['create']
      create_tool = described_class.new(
        scout,
        conversation,
        capability_instance: customer_capability,
        operation: create_operation
      )

      stub_request(:post, %r{https://wfh\.ichatr\.com\.br/webhook/incluir-cliente})
        .to_return(
          status: 200,
          body: { sucesso: true, mensagem: 'OK', dados: { idPessoa: '784868', nmPessoa: 'João Silva' } }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      tracer = OpenTelemetry.tracer_provider.tracer('test')
      tracer.in_span('test_span') do
        create_tool.execute(name: 'João Silva')
      end

      finished_span = exporter.finished_spans.find { |s| s.name == 'test_span' }
      recorded_json = finished_span.attributes['langfuse.observation.metadata.capability_call']
      metadata = JSON.parse(recorded_json)

      expect(metadata['injected']['nr_convenio']).to eq('000123')
      expect(metadata['injected']['id_empresa']).to eq(648)
      expect(metadata['injected']['id_usuario']).to eq(172_793)
      expect(metadata['injected']['id_convenio']).to eq(1)
      expect(metadata['injected']['id_origem_pessoa']).to eq(11)
      expect(metadata['injected']['phone']).to eq('11999990648')
    end
  end
end
