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
      [SocketError, Errno::ECONNREFUSED].each do |err|
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
  # rubocop:enable Rails/DynamicFindBy
end
