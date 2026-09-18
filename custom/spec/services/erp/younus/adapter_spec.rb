# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Erp::Younus::Adapter do
  subject(:adapter) { described_class.new(hook) }

  let(:hook) do
    instance_double(
      Integrations::Hook,
      app_id: 'younus',
      settings: { 'token' => 'my-token', 'id_empresa' => '42' }
    )
  end

  describe '.erp_name' do
    it 'returns Younus (U18)' do
      expect(described_class.erp_name).to eq('Younus')
    end
  end

  describe '#test_connection' do
    let(:client) { instance_double(Erp::Younus::Client) }

    before do
      allow(Erp::Younus::Client).to receive(:new)
        .with(token: 'my-token', id_empresa: '42')
        .and_return(client)
    end

    it 'calls client.search_by_phone("0") and returns true on success (U19)' do
      allow(client).to receive(:search_by_phone).with('0').and_return(nil)

      expect(adapter.test_connection).to be(true)
      expect(client).to have_received(:search_by_phone).with('0')
    end

    it 'returns true even when record is found (U19)' do
      allow(client).to receive(:search_by_phone).with('0').and_return({ 'nm_pessoa' => 'Found' })

      expect(adapter.test_connection).to be(true)
    end

    it 'propagates Erp::AuthenticationError raised by client (U20)' do
      allow(client).to receive(:search_by_phone).with('0')
                                                .and_raise(Erp::AuthenticationError, 'Invalid credentials')

      expect { adapter.test_connection }.to raise_error(Erp::AuthenticationError, 'Invalid credentials')
    end

    it 'propagates Erp::ApiError raised by client (U20)' do
      allow(client).to receive(:search_by_phone).with('0')
                                                .and_raise(Erp::ApiError, 'Could not connect to ERP')

      expect { adapter.test_connection }.to raise_error(Erp::ApiError, 'Could not connect to ERP')
    end
  end

  # rubocop:disable Rails/DynamicFindBy
  describe '#find_by_id' do
    let(:client) { instance_double(Erp::Younus::Client) }

    before do
      allow(Erp::Younus::Client).to receive(:new)
        .with(token: 'my-token', id_empresa: '42')
        .and_return(client)
    end

    it 'delegates find_by_id to client (U8)' do
      record = { 'cd_pessoa' => 123, 'nm_pessoa' => 'Maria Silva' }
      allow(client).to receive(:find_by_id).with('123').and_return(record)

      expect(adapter.find_by_id('123')).to eq(record)
      expect(client).to have_received(:find_by_id).with('123')
    end
  end

  describe '#search_by_phone' do
    let(:client) { instance_double(Erp::Younus::Client) }

    before do
      allow(Erp::Younus::Client).to receive(:new)
        .with(token: 'my-token', id_empresa: '42')
        .and_return(client)
    end

    it 'delegates search_by_phone to client (U9)' do
      expected = { record: { 'cd_pessoa' => 123 }, multiple_matches: false }
      allow(client).to receive(:search_by_phone).with('11987654321').and_return(expected)

      expect(adapter.search_by_phone('11987654321')).to eq(expected)
      expect(client).to have_received(:search_by_phone).with('11987654321')
    end
  end

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
      expect(adapter.external_id_from({})).to be_nil
    end
  end
  # rubocop:enable Rails/DynamicFindBy
end
