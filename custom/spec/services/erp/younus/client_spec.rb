# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Erp::Younus::Client do
  subject(:client) { described_class.new(token: token, id_empresa: id_empresa) }

  let(:token) { 'valid-secret-token' }
  let(:id_empresa) { '42' }
  let(:base_url) { 'https://wfh.ichatr.com.br/webhook/pessoas' }

  describe '#search_by_phone' do
    let(:phone) { '11987654321' }

    it 'issues GET request with correct token header and query parameters (U9)' do
      stub = stub_request(:get, base_url)
             .with(
               query: { idEmpresa: id_empresa, nrTelcelpessoa: phone },
               headers: { 'token' => token }
             )
             .to_return(
               status: 200,
               body: { sucesso: false, dados: [] }.to_json,
               headers: { 'Content-Type' => 'application/json' }
             )

      client.search_by_phone(phone)
      expect(stub).to have_been_requested
    end

    it 'rescues request timeout when remote connection times out (U10)' do
      stub_request(:get, base_url)
        .with(query: { idEmpresa: id_empresa, nrTelcelpessoa: phone })
        .to_timeout

      expect { client.search_by_phone(phone) }
        .to raise_error(Erp::ApiError, 'Connection timed out')
    end

    it 'returns record and multiple_matches false for single match (U5)' do
      record = { 'cd_pessoa' => 123, 'nm_pessoa' => 'Maria Silva' }
      stub_request(:get, base_url)
        .with(query: { idEmpresa: id_empresa, nrTelcelpessoa: phone })
        .to_return(
          status: 200,
          body: { sucesso: true, mensagem: 'OK', dados: [{ 'json' => record }] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.search_by_phone(phone)
      expect(result).to eq({ record: record, multiple_matches: false })
    end

    it 'returns first record and multiple_matches true for multiple matches (U6)' do
      record1 = { 'cd_pessoa' => 123, 'nm_pessoa' => 'Maria Silva' }
      record2 = { 'cd_pessoa' => 456, 'nm_pessoa' => 'Maria Silva Secondary' }
      stub_request(:get, base_url)
        .with(query: { idEmpresa: id_empresa, nrTelcelpessoa: phone })
        .to_return(
          status: 200,
          body: { sucesso: true, mensagem: 'OK', dados: [{ 'json' => record1 }, { 'json' => record2 }] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.search_by_phone(phone)
      expect(result).to eq({ record: record1, multiple_matches: true })
    end

    it 'handles responses wrapped in an array from n8n' do
      record = { 'cd_pessoa' => 123, 'nm_pessoa' => 'Maria Silva' }
      payload = [{ sucesso: true, mensagem: 'OK', dados: [{ 'json' => record }] }]

      stub_request(:get, base_url)
        .with(query: { idEmpresa: id_empresa, nrTelcelpessoa: phone })
        .to_return(
          status: 200,
          body: payload.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = client.search_by_phone(phone)
      expect(result).to eq({ record: record, multiple_matches: false })
    end

    it 'returns nil when no pessoa matches phone (U7)' do
      stub_request(:get, base_url)
        .with(query: { idEmpresa: id_empresa, nrTelcelpessoa: phone })
        .to_return(
          status: 200,
          body: { sucesso: false, mensagem: 'Not found', dados: [] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      expect(client.search_by_phone(phone)).to be_nil

      stub_request(:get, base_url)
        .with(query: { idEmpresa: id_empresa, nrTelcelpessoa: phone })
        .to_return(
          status: 200,
          body: { sucesso: true, mensagem: 'OK', dados: [] }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      expect(client.search_by_phone(phone)).to be_nil
    end

    it 'raises Erp::AuthenticationError on 401 and 403 (U13)' do
      [401, 403].each do |code|
        stub_request(:get, base_url)
          .with(query: { idEmpresa: id_empresa, nrTelcelpessoa: phone })
          .to_return(status: code, body: { error: 'Unauthorized' }.to_json)

        expect { client.search_by_phone(phone) }.to raise_error(Erp::AuthenticationError, 'Invalid credentials')
      end
    end

    it 'raises Erp::ApiError on 5xx server error (U14)' do
      stub_request(:get, base_url)
        .with(query: { idEmpresa: id_empresa, nrTelcelpessoa: phone })
        .to_return(status: 503, body: 'Service Unavailable')

      expect { client.search_by_phone(phone) }.to raise_error(Erp::ApiError, /503/)
    end

    it 'rescues timeouts and raises Erp::ApiError (U15)' do
      [Net::OpenTimeout, Net::ReadTimeout, Timeout::Error].each do |err|
        stub_request(:get, base_url)
          .with(query: { idEmpresa: id_empresa, nrTelcelpessoa: phone })
          .to_raise(err)

        expect { client.search_by_phone(phone) }.to raise_error(Erp::ApiError, 'Connection timed out')
      end
    end

    it 'rescues connection errors and raises Erp::ApiError (U16)' do
      [SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, EOFError, OpenSSL::SSL::SSLError].each do |err|
        stub_request(:get, base_url)
          .with(query: { idEmpresa: id_empresa, nrTelcelpessoa: phone })
          .to_raise(err)

        expect { client.search_by_phone(phone) }.to raise_error(Erp::ApiError, 'Network error')
      end
    end

    it 'rescues json parse error on malformed body and raises Erp::ApiError (U17)' do
      stub_request(:get, base_url)
        .with(query: { idEmpresa: id_empresa, nrTelcelpessoa: phone })
        .to_return(status: 200, body: 'not-valid-json{')

      expect { client.search_by_phone(phone) }.to raise_error(Erp::ApiError, 'Malformed response from ERP')
    end
  end

  # rubocop:disable Rails/DynamicFindBy
  describe '#find_by_id' do
    let(:external_id) { '123' }
    let(:pessoa_url) { 'https://wfh.ichatr.com.br/webhook/pessoa' }

    it 'issues GET to webhook pessoa with correct headers and query (U1)' do
      stub = stub_request(:get, pessoa_url)
             .with(
               query: { idEmpresa: id_empresa, idPessoa: external_id },
               headers: {
                 'token' => token,
                 'Content-Type' => 'application/json'
               }
             )
             .to_return(status: 200, body: { sucesso: true, dados: [{ json: { 'cd_pessoa' => 123 } }] }.to_json)

      client.find_by_id(external_id)

      expect(stub).to have_been_requested
    end

    it 'returns person record hash on sucesso true (U2)' do
      record = { 'cd_pessoa' => 123, 'nm_pessoa' => 'Maria Silva' }
      stub_request(:get, pessoa_url)
        .with(query: { idEmpresa: id_empresa, idPessoa: external_id })
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: { sucesso: true, dados: [{ json: record }] }.to_json
        )

      result = client.find_by_id(external_id)

      expect(result).to eq(record)
    end

    it 'returns nil on pessoa sucesso false (U3)' do
      stub_request(:get, pessoa_url)
        .with(query: { idEmpresa: id_empresa, idPessoa: external_id })
        .to_return(
          status: 200,
          headers: { 'Content-Type' => 'application/json' },
          body: { sucesso: false, dados: [] }.to_json
        )

      result = client.find_by_id(external_id)

      expect(result).to be_nil
    end

    it 'raises mapped error on pessoa failure (U4)' do
      stub_request(:get, pessoa_url)
        .with(query: { idEmpresa: id_empresa, idPessoa: external_id })
        .to_return(status: 401, body: 'Unauthorized')

      expect { client.find_by_id(external_id) }.to raise_error(Erp::AuthenticationError, 'Invalid credentials')

      stub_request(:get, pessoa_url)
        .with(query: { idEmpresa: id_empresa, idPessoa: external_id })
        .to_return(status: 500, body: 'Server Error')

      expect { client.find_by_id(external_id) }.to raise_error(Erp::ApiError, 'ERP service error: 500')
    end
  end

  describe 'new capability endpoints with settings injection' do
    subject(:configured_client) do
      described_class.new(
        token: 'distinct-token-xyz',
        id_empresa: '648',
        settings: {
          'id_empresa' => '648',
          'id_usuario' => '172793',
          'id_convenio' => '1',
          'nr_convenio' => 'CARD-12345',
          'id_origem_pessoa' => '11',
          'id_agenda' => '3',
          'id_servico' => '1'
        }
      )
    end

    let(:fixtures_path) { Rails.root.join('custom/spec/fixtures/erp/younus') }

    describe '#find_person' do
      let(:phone) { '5511999990000' }
      let(:url) { 'https://wfh.ichatr.com.br/webhook/pesquisar-pessoa' }

      it 'issues GET with distinctive configured settings as integer and phone' do
        stub_request(:get, url)
          .with(
            query: { idEmpresa: 648, nrTelcelpessoa: phone },
            headers: { 'token' => 'distinct-token-xyz', 'Content-Type' => 'application/json' }
          )
          .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_found.json"), headers: { 'Content-Type' => 'application/json' })

        result = configured_client.find_person(phone)

        expect(WebMock).to have_requested(:get, url)
          .with(query: { idEmpresa: 648, nrTelcelpessoa: phone })
        expect(result[:record]['idPessoa']).to eq(784_868)
        expect(result[:multiple_matches]).to be(false)
      end

      it 'handles multiple matches using find_person_multiple fixture' do
        stub_request(:get, /#{url}/)
          .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_multiple.json"), headers: { 'Content-Type' => 'application/json' })

        result = configured_client.find_person(phone)
        expect(result[:multiple_matches]).to be(true)
      end

      it 'handles no match using find_person_none fixture returning nil' do
        stub_request(:get, /#{url}/)
          .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_none.json"), headers: { 'Content-Type' => 'application/json' })

        result = configured_client.find_person(phone)
        expect(result).to be_nil
      end
    end

    describe '#create_person' do
      let(:url) { 'https://wfh.ichatr.com.br/webhook/incluir-cliente' }

      it 'issues POST with configured identifiers as integers and nrConvenio as string' do
        stub = stub_request(:post, url)
               .with(
                 headers: { 'token' => 'distinct-token-xyz', 'Content-Type' => 'application/json' },
                 body: {
                   nmPessoa: 'João Santos',
                   idEmpresa: 648,
                   idUsuario: 172_793,
                   idConvenio: 1,
                   nrConvenio: 'CARD-12345',
                   idOrigempessoa: 11,
                   nrTelcelpessoa: '5511988880000'
                 }.to_json
               )
               .to_return(status: 200, body: File.read("#{fixtures_path}/create_person.json"), headers: { 'Content-Type' => 'application/json' })

        result = configured_client.create_person('João Santos', '5511988880000')

        expect(stub).to have_been_requested
        expect(result['idPessoa']).to eq(784_868)
      end

      it 'raises Erp::ApiError on sucesso: false response' do
        stub_request(:post, url)
          .to_return(status: 200, body: File.read("#{fixtures_path}/error_declined.json"), headers: { 'Content-Type' => 'application/json' })

        expect { configured_client.create_person('Fail', '123') }
          .to raise_error(Erp::ApiError, 'Não foi possível cadastrar o agendamento.')
      end
    end

    describe '#free_slots' do
      let(:url) { 'https://wfh.ichatr.com.br/webhook/horarios-livres' }

      it 'issues GET with date, idAgenda, idEmpresa, and idServico' do
        stub = stub_request(:get, url)
               .with(
                 query: { data: '2026-10-15', idAgenda: 3, idEmpresa: 648, idServico: 1 },
                 headers: { 'token' => 'distinct-token-xyz', 'Content-Type' => 'application/json' }
               )
               .to_return(status: 200, body: File.read("#{fixtures_path}/free_slots.json"), headers: { 'Content-Type' => 'application/json' })

        result = configured_client.free_slots('2026-10-15')

        expect(stub).to have_been_requested
        expect(result).to include('2026-10-15 08:00')
      end

      it 'returns empty array when no slots available' do
        stub_request(:get, /#{url}/)
          .to_return(status: 200, body: File.read("#{fixtures_path}/free_slots_empty.json"), headers: { 'Content-Type' => 'application/json' })

        result = configured_client.free_slots('2026-10-15')
        expect(result).to eq([])
      end

      it 'raises Erp::ApiError when response is sucesso: false' do
        stub_request(:get, /#{url}/)
          .to_return(
            status: 200,
            body: { sucesso: false, mensagem: 'Agenda não encontrada' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        expect { configured_client.free_slots('2026-10-15') }
          .to raise_error(Erp::ApiError, 'Agenda não encontrada')
      end
    end

    describe '#create_appointment' do
      let(:url) { 'https://wfh.ichatr.com.br/webhook/incluir-agendamento' }

      it 'issues POST with configured identifiers and appointment parameters' do
        stub = stub_request(:post, url)
               .with(
                 headers: { 'token' => 'distinct-token-xyz', 'Content-Type' => 'application/json' },
                 body: {
                   idAgenda: 3,
                   idPessoa: 784_868,
                   nmTitulo: 'Teste Lead Scout',
                   idEmpresa: 648,
                   idServico: 1,
                   idUsuario: 172_793,
                   idConvenio: 1,
                   dtIniAgenda: '2026-10-15T14:30:00-03:00',
                   observacoes: 'Agendado por Scout: prefere tarde'
                 }.to_json
               )
               .to_return(status: 200, body: File.read("#{fixtures_path}/create_appointment.json"), headers: { 'Content-Type' => 'application/json' })

        result = configured_client.create_appointment(
          person_id: '784868',
          title: 'Teste Lead Scout',
          starts_at: '2026-10-15T14:30:00-03:00',
          notes: 'prefere tarde'
        )

        expect(stub).to have_been_requested
        expect(result['idMvtoagenda']).to eq(4_468_657)
      end

      it 'raises Erp::ApiError on declined appointment' do
        stub_request(:post, url)
          .to_return(status: 200, body: File.read("#{fixtures_path}/error_declined.json"), headers: { 'Content-Type' => 'application/json' })

        expect do
          configured_client.create_appointment(
            person_id: '123',
            title: 'Test',
            starts_at: '2026-10-15T14:30:00-03:00',
            notes: nil
          )
        end.to raise_error(Erp::ApiError, 'Não foi possível cadastrar o agendamento.')
      end

      it 'rescues transport failures (reset, unreachable, eof, ssl, timed out, net unreachable, httparty) and raises Erp::ApiError' do
        failures = [Errno::ECONNRESET, Errno::EHOSTUNREACH, EOFError, OpenSSL::SSL::SSLError,
                    Errno::ETIMEDOUT, Errno::ENETUNREACH, HTTParty::Error]
        failures.each do |err|
          stub_request(:post, url).to_raise(err)

          expect do
            configured_client.create_appointment(
              person_id: '123',
              title: 'Test',
              starts_at: '2026-10-15T14:30:00-03:00',
              notes: nil
            )
          end.to raise_error(Erp::ApiError, 'Network error')
        end
      end
    end

    context 'with leading-zero identifiers in settings (T083)' do
      let(:leading_zero_client) do
        described_class.new(
          token: 'distinct-token-xyz',
          id_empresa: '08',
          settings: {
            'id_empresa' => '08',
            'id_usuario' => '09',
            'id_convenio' => '01',
            'nr_convenio' => '00123',
            'id_origem_pessoa' => '05',
            'id_agenda' => '03',
            'id_servico' => '07'
          }
        )
      end

      it 'parses identifiers with base 10 without raising ArgumentError and sends base 10 integers' do
        stub_request(:get, 'https://wfh.ichatr.com.br/webhook/horarios-livres')
          .with(query: { data: '2026-10-15', idAgenda: 3, idEmpresa: 8, idServico: 7 })
          .to_return(status: 200, body: File.read("#{fixtures_path}/free_slots.json"), headers: { 'Content-Type' => 'application/json' })

        expect { leading_zero_client.free_slots('2026-10-15') }.not_to raise_error

        stub_request(:post, 'https://wfh.ichatr.com.br/webhook/incluir-agendamento')
          .with(body: hash_including({ 'idAgenda' => 3, 'idPessoa' => 8, 'idEmpresa' => 8, 'idServico' => 7, 'idUsuario' => 9, 'idConvenio' => 1 }))
          .to_return(status: 200, body: File.read("#{fixtures_path}/create_appointment.json"), headers: { 'Content-Type' => 'application/json' })

        expect do
          leading_zero_client.create_appointment(
            person_id: '08',
            title: 'Test',
            starts_at: '2026-10-15T14:30:00-03:00',
            notes: nil
          )
        end.not_to raise_error
      end
    end
  end
  # rubocop:enable Rails/DynamicFindBy
end
