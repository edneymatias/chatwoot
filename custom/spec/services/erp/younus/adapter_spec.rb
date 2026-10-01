# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Erp::Younus::Adapter do
  subject(:adapter) { described_class.new(hook) }

  before do
    account.enable_features!('erp_integration')
    stub_request(:get, 'https://wfh.ichatr.com.br/webhook/pessoas')
      .with(query: { idEmpresa: 648, nrTelcelpessoa: '0' }, headers: { 'token' => 'secret-erp-token-999' })
      .to_return(status: 200, body: { sucesso: true, dados: [] }.to_json, headers: json_headers)
  end

  let(:account) { create(:account) }
  let!(:hook) do
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

  let(:fixtures_path) { Rails.root.join('custom/spec/fixtures/erp/younus') }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  describe '.erp_name' do
    it 'returns Younus (U18)' do
      expect(described_class.erp_name).to eq('Younus')
    end
  end

  describe '#test_connection' do
    it 'calls client.search_by_phone("0") and returns true on success (U19)' do
      stub_request(:get, 'https://wfh.ichatr.com.br/webhook/pessoas')
        .with(query: { idEmpresa: 648, nrTelcelpessoa: '0' }, headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 200, body: { sucesso: true, dados: [] }.to_json, headers: json_headers)

      expect(adapter.test_connection).to be(true)
    end

    it 'returns true even when record is found (U19)' do
      stub_request(:get, 'https://wfh.ichatr.com.br/webhook/pessoas')
        .with(query: { idEmpresa: 648, nrTelcelpessoa: '0' }, headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_found.json"), headers: json_headers)

      expect(adapter.test_connection).to be(true)
    end

    it 'propagates Erp::AuthenticationError raised by client on 401 (U20)' do
      stub_request(:get, 'https://wfh.ichatr.com.br/webhook/pessoas')
        .with(query: { idEmpresa: 648, nrTelcelpessoa: '0' }, headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 401, body: 'Unauthorized')

      expect { adapter.test_connection }.to raise_error(Erp::AuthenticationError)
    end

    it 'propagates Erp::ApiError raised by client on 5xx (U20)' do
      stub_request(:get, 'https://wfh.ichatr.com.br/webhook/pessoas')
        .with(query: { idEmpresa: 648, nrTelcelpessoa: '0' }, headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 500, body: 'Internal Server Error')

      expect { adapter.test_connection }.to raise_error(Erp::ApiError)
    end
  end

  # rubocop:disable Rails/DynamicFindBy
  describe '#find_by_id' do
    it 'delegates find_by_id to client (U8)' do
      body = {
        sucesso: true,
        dados: [{ json: { cd_pessoa: 123, nm_pessoa: 'Maria Silva' } }]
      }.to_json

      stub_request(:get, 'https://wfh.ichatr.com.br/webhook/pessoa')
        .with(query: { idEmpresa: 648, idPessoa: '123' }, headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 200, body: body, headers: json_headers)

      expect(adapter.find_by_id('123')).to eq({ 'cd_pessoa' => 123, 'nm_pessoa' => 'Maria Silva' })
    end
  end

  describe '#search_by_phone' do
    it 'delegates search_by_phone to client (U9)' do
      body = {
        sucesso: true,
        dados: [{ json: { cd_pessoa: 123, nm_pessoa: 'Maria Silva' } }]
      }.to_json

      stub_request(:get, 'https://wfh.ichatr.com.br/webhook/pessoas')
        .with(query: { idEmpresa: 648, nrTelcelpessoa: '11987654321' }, headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 200, body: body, headers: json_headers)

      expect(adapter.search_by_phone('11987654321')).to eq({
                                                             record: { 'cd_pessoa' => 123, 'nm_pessoa' => 'Maria Silva' },
                                                             multiple_matches: false
                                                           })
    end
  end
  # rubocop:enable Rails/DynamicFindBy

  describe '#phone_from' do
    it 'extracts phone from payload fields (U10)' do
      expect(adapter.phone_from({ 'nr_telcelpessoa' => '11999998888' })).to eq('11999998888')
      expect(adapter.phone_from({ 'nrTelcelpessoa' => '11999997777' })).to eq('11999997777')
      expect(adapter.phone_from({ 'telefone' => '11999996666' })).to eq('11999996666')
      expect(adapter.phone_from({})).to be_nil
    end
  end

  describe '#external_id_from' do
    it 'extracts external id from payload fields (U11)' do
      expect(adapter.external_id_from({ 'cd_pessoa' => 123 })).to eq('123')
      expect(adapter.external_id_from({ 'idPessoa' => '456' })).to eq('456')
      expect(adapter.external_id_from({ 'idPessoa' => '08' })).to eq('08')
      expect(adapter.external_id_from({ 'idPessoa' => 'abc' })).to be_nil
      expect(adapter.external_id_from({})).to be_nil
    end
  end

  describe 'capability provider methods' do
    describe '#find_person' do
      it 'normalizes single match to found status with person id and name' do
        stub_request(:get, 'https://wfh.ichatr.com.br/webhook/pesquisar-pessoa')
          .with(query: { idEmpresa: 648, nrTelcelpessoa: '5511999990648' }, headers: { 'token' => 'secret-erp-token-999' })
          .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_found.json"), headers: json_headers)

        result = adapter.find_person(phone: '5511999990648')
        expect(result).to eq({
                               status: :found,
                               person: { id: '784868', name: 'Teste Lead Scout' }
                             })
      end

      it 'normalizes multiple matches to ambiguous status without picking any person' do
        stub_request(:get, 'https://wfh.ichatr.com.br/webhook/pesquisar-pessoa')
          .with(query: { idEmpresa: 648, nrTelcelpessoa: '5511999990648' }, headers: { 'token' => 'secret-erp-token-999' })
          .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_multiple.json"), headers: json_headers)

        result = adapter.find_person(phone: '5511999990648')
        expect(result).to eq({
                               status: :ambiguous,
                               person: nil
                             })
      end

      it 'normalizes empty/declined search response to not_found status' do
        stub_request(:get, 'https://wfh.ichatr.com.br/webhook/pesquisar-pessoa')
          .with(query: { idEmpresa: 648, nrTelcelpessoa: '5511999990648' }, headers: { 'token' => 'secret-erp-token-999' })
          .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_none.json"), headers: json_headers)

        result = adapter.find_person(phone: '5511999990648')
        expect(result).to eq({
                               status: :not_found,
                               person: nil
                             })
      end

      it 'handles vendor omissions as nil without raising' do
        body = {
          sucesso: true,
          quantidade: 1,
          dados: [{ json: { pessoaTipo: 3 } }]
        }.to_json

        stub_request(:get, 'https://wfh.ichatr.com.br/webhook/pesquisar-pessoa')
          .with(query: { idEmpresa: 648, nrTelcelpessoa: '5511999990648' }, headers: { 'token' => 'secret-erp-token-999' })
          .to_return(status: 200, body: body, headers: json_headers)

        result = adapter.find_person(phone: '5511999990648')
        expect(result[:status]).to eq(:found)
        expect(result.dig(:person, :id)).to be_nil
        expect(result.dig(:person, :name)).to be_nil
      end

      it 'normalizes single match with non-numeric person id as nil without raising ArgumentError (T083)' do
        body = {
          sucesso: true,
          quantidade: 1,
          dados: [{ json: { idPessoa: 'not-a-number', nmPessoa: 'Invalid ID' } }]
        }.to_json

        stub_request(:get, 'https://wfh.ichatr.com.br/webhook/pesquisar-pessoa')
          .with(query: { idEmpresa: 648, nrTelcelpessoa: '5511999990648' }, headers: { 'token' => 'secret-erp-token-999' })
          .to_return(status: 200, body: body, headers: json_headers)

        result = adapter.find_person(phone: '5511999990648')
        expect(result[:status]).to eq(:found)
        expect(result.dig(:person, :id)).to be_nil
        expect(result.dig(:person, :name)).to eq('Invalid ID')
      end
    end

    describe '#create_person' do
      it 'normalizes created person to contract shape with id and name' do
        stub_request(:post, 'https://wfh.ichatr.com.br/webhook/incluir-cliente')
          .with(headers: { 'token' => 'secret-erp-token-999' })
          .to_return(status: 200, body: File.read("#{fixtures_path}/create_person.json"), headers: json_headers)

        result = adapter.create_person(name: 'Teste Lead Scout', phone: '5511999990648')
        expect(result).to eq({
                               id: '784868',
                               name: 'Teste Lead Scout'
                             })
      end

      it 'handles missing person id as nil without raising' do
        body = {
          sucesso: true,
          mensagem: 'OK',
          dados: { nmPessoa: 'João Santos' }
        }.to_json

        stub_request(:post, 'https://wfh.ichatr.com.br/webhook/incluir-cliente')
          .with(headers: { 'token' => 'secret-erp-token-999' })
          .to_return(status: 200, body: body, headers: json_headers)

        result = adapter.create_person(name: 'João Santos', phone: '5511999990000')
        expect(result).to eq({
                               id: nil,
                               name: 'João Santos'
                             })
      end

      it 'normalizes created person with non-numeric person id as nil without raising ArgumentError (T083)' do
        body = {
          sucesso: true,
          mensagem: 'OK',
          dados: { idPessoa: 'not-a-number', nmPessoa: 'Invalid ID' }
        }.to_json

        stub_request(:post, 'https://wfh.ichatr.com.br/webhook/incluir-cliente')
          .with(headers: { 'token' => 'secret-erp-token-999' })
          .to_return(status: 200, body: body, headers: json_headers)

        result = adapter.create_person(name: 'Invalid ID', phone: '5511999990000')
        expect(result).to eq({
                               id: nil,
                               name: 'Invalid ID'
                             })
      end
    end

    describe '#list_free_slots' do
      it 'normalizes slot strings to ISO 8601 with -03:00 offset sorted ascending' do
        stub_request(:get, 'https://wfh.ichatr.com.br/webhook/horarios-livres')
          .with(query: { data: '2026-10-15', idAgenda: 3, idEmpresa: 648, idServico: 1 }, headers: { 'token' => 'secret-erp-token-999' })
          .to_return(status: 200, body: File.read("#{fixtures_path}/free_slots.json"), headers: json_headers)

        result = adapter.list_free_slots(date: '2026-10-15')
        starts = result.map { |s| s[:starts_at] }
        expect(starts).to include('2026-10-15T08:00:00-03:00', '2026-10-15T08:40:00-03:00')
        expect(starts).to eq(starts.sort)
        expect(result.first[:slot_id]).to eq('2026-10-15T08:00:00-03:00')
      end

      it 'returns empty array when client returns empty' do
        stub_request(:get, 'https://wfh.ichatr.com.br/webhook/horarios-livres')
          .with(query: { data: '2026-10-15', idAgenda: 3, idEmpresa: 648, idServico: 1 }, headers: { 'token' => 'secret-erp-token-999' })
          .to_return(status: 200, body: File.read("#{fixtures_path}/free_slots_empty.json"), headers: json_headers)

        expect(adapter.list_free_slots(date: '2026-10-15')).to eq([])
      end
    end

    describe '#create_appointment' do
      it 'normalizes created appointment to contract shape' do
        stub_request(:post, 'https://wfh.ichatr.com.br/webhook/incluir-agendamento')
          .with(headers: { 'token' => 'secret-erp-token-999' })
          .to_return(status: 200, body: File.read("#{fixtures_path}/create_appointment.json"), headers: json_headers)

        result = adapter.create_appointment(
          person_id: '784868',
          person_name: 'Teste Lead Scout',
          starts_at: '2026-10-15T11:00:00-03:00',
          notes: 'urgente'
        )

        expect(result).to eq({
                               appointment_id: '4468657',
                               starts_at: '2026-10-15T11:00:00-03:00'
                             })
      end

      it 'maps missing appointment id to nil without raising' do
        body = {
          sucesso: true,
          mensagem: 'OK',
          dados: { nmTitulo: 'Teste Lead Scout', dtIniagenda: '2026-10-15T14:30:00Z' }
        }.to_json

        stub_request(:post, 'https://wfh.ichatr.com.br/webhook/incluir-agendamento')
          .with(headers: { 'token' => 'secret-erp-token-999' })
          .to_return(status: 200, body: body, headers: json_headers)

        result = adapter.create_appointment(
          person_id: '784868',
          person_name: 'Teste Lead Scout',
          starts_at: '2026-10-15T14:30:00-03:00',
          notes: nil
        )

        expect(result).to eq({
                               appointment_id: nil,
                               starts_at: '2026-10-15T14:30:00-03:00'
                             })
      end

      it 'does not report person identifier (idPessoa/cd_pessoa) as appointment_id' do
        body = {
          sucesso: true,
          mensagem: 'OK',
          dados: { idPessoa: 784_868, cd_pessoa: 784_868, nmTitulo: 'Teste Lead Scout' }
        }.to_json

        stub_request(:post, 'https://wfh.ichatr.com.br/webhook/incluir-agendamento')
          .with(headers: { 'token' => 'secret-erp-token-999' })
          .to_return(status: 200, body: body, headers: json_headers)

        result = adapter.create_appointment(
          person_id: '784868',
          person_name: 'Teste Lead Scout',
          starts_at: '2026-10-15T14:30:00-03:00',
          notes: nil
        )

        expect(result).to eq({
                               appointment_id: nil,
                               starts_at: '2026-10-15T14:30:00-03:00'
                             })
      end
    end

    describe '#client_kwargs' do
      it 'restricts settings to the seven identifier keys and excludes token' do
        kwargs = adapter.client_kwargs

        expect(kwargs[:token]).to eq('secret-erp-token-999')
        expect(kwargs[:id_empresa]).to eq('648')
        expect(kwargs[:settings]).to eq(
          'id_empresa' => '648',
          'id_usuario' => '172793',
          'id_convenio' => '1',
          'nr_convenio' => '12345',
          'id_origem_pessoa' => '11',
          'id_agenda' => '3',
          'id_servico' => '1'
        )
        expect(kwargs[:settings]).not_to have_key('token')
      end
    end

    describe '#operation_identifier_keys' do
      it 'returns the exact identifier keys for the four capability operations' do
        expect(adapter.operation_identifier_keys('find_by_phone')).to eq(%w[id_empresa])
        expect(adapter.operation_identifier_keys('create')).to eq(%w[id_empresa id_usuario id_convenio nr_convenio id_origem_pessoa])
        expect(adapter.operation_identifier_keys('list_slots')).to eq(%w[id_empresa id_agenda id_servico])
        expect(adapter.operation_identifier_keys('book')).to eq(%w[id_empresa id_agenda id_servico id_usuario id_convenio])
      end

      it 'returns empty array for unused alias keys' do
        expect(adapter.operation_identifier_keys('find_person')).to eq([])
        expect(adapter.operation_identifier_keys('create_person')).to eq([])
        expect(adapter.operation_identifier_keys('list_free_slots')).to eq([])
        expect(adapter.operation_identifier_keys('create_appointment')).to eq([])
      end
    end
  end
end
