# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Capabilities::CustomerRegistry do
  subject(:registry) { described_class.new(provider: provider, conversation: conversation) }

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
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990648') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:fixtures_path) { Rails.root.join('custom/spec/fixtures/erp/younus') }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  before do
    account.enable_features!('erp_integration')
    stub_request(:get, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar')
      .with(query: { idEmpresa: 648, nrTelcelpessoa: '0' }, headers: { 'token' => 'secret-erp-token-999' })
      .to_return(status: 200, body: { sucesso: true, dados: [] }.to_json, headers: json_headers)
  end

  describe 'phone precondition' do
    context 'when contact has no phone number' do
      before { contact.update!(phone_number: nil) }

      it 'returns error before any provider request on find_by_phone' do
        error = registry.check_preconditions_for_find_by_phone
        expect(error).to eq(
          'O contato não tem telefone registrado. Não peça o telefone ao cliente; ' \
          'chame exit_handoff neste mesmo turno informando que o telefone está ausente.'
        )
        expect(WebMock).not_to have_requested(:get, %r{wfh\.ichatr\.com\.br/webhook/api/v1/empresas/pessoas/pesquisar\?.*nrTelcelpessoa=[1-9]})
      end

      it 'returns error before any provider request on create' do
        error = registry.check_preconditions_for_create(name: 'Maria')
        expect(error).to eq(
          'O contato não tem telefone registrado. Não peça o telefone ao cliente; ' \
          'chame exit_handoff neste mesmo turno informando que o telefone está ausente.'
        )
        expect(WebMock).not_to have_requested(:post, %r{wfh\.ichatr\.com\.br/webhook/api/v1/empresas/pessoas})
      end
    end
  end

  describe '#find_by_phone' do
    it 'remembers customer and returns found status on single match' do
      stub_request(:get, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar')
        .with(query: { idEmpresa: 648, nrTelcelpessoa: '11999990648' }, headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_found.json"), headers: json_headers)

      result = registry.find_by_phone

      expect(result).to eq({ status: 'found', name: 'Teste Lead Scout' })
      expect(WebMock).to have_requested(:get, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar')
        .with(query: { idEmpresa: 648, nrTelcelpessoa: '11999990648' })

      state = ScoutConversationState.for_conversation(conversation)
      expect(state.capability_state['customer']).to eq({ 'id' => '784868', 'name' => 'Teste Lead Scout' })
    end

    it 'returns ambiguous status and remembers no customer on multiple matches (FR-016)' do
      stub_request(:get, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar')
        .with(query: { idEmpresa: 648, nrTelcelpessoa: '11999990648' }, headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_multiple.json"), headers: json_headers)

      result = registry.find_by_phone

      expect(result).to eq({ status: 'ambiguous' })
      state = ScoutConversationState.for_conversation(conversation)
      expect(state.capability_state['customer']).to be_nil
    end

    it 'returns not_found status and remembers no customer when no person is found' do
      stub_request(:get, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar')
        .with(query: { idEmpresa: 648, nrTelcelpessoa: '11999990648' }, headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 200, body: File.read("#{fixtures_path}/find_person_none.json"), headers: json_headers)

      result = registry.find_by_phone

      expect(result).to eq({ status: 'not_found' })
      state = ScoutConversationState.for_conversation(conversation)
      expect(state.capability_state['customer']).to be_nil
    end

    it 'returns failure result and remembers no customer when single match lacks readable id (FR-029)' do
      body = {
        sucesso: true,
        quantidade: 1,
        dados: [{ json: { nmPessoa: 'Sem ID' } }]
      }.to_json

      stub_request(:get, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar')
        .with(query: { idEmpresa: 648, nrTelcelpessoa: '11999990648' }, headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 200, body: body, headers: json_headers)

      result = registry.find_by_phone

      expect(result[:error]).to eq(
        'O sistema do cliente encontrou um cadastro, mas não foi possível identificá-lo. ' \
        'Não cadastre novamente; chame exit_handoff neste mesmo turno.'
      )
      state = ScoutConversationState.for_conversation(conversation)
      expect(state.capability_state['customer']).to be_nil
    end
  end

  describe '#create' do
    it 'sends given name with contact phone, remembers customer, and returns created status' do
      stub_request(:post, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas')
        .with(headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 200, body: File.read("#{fixtures_path}/create_person.json"), headers: json_headers)

      result = registry.create(name: 'Teste Lead Scout')

      expect(result).to eq({ status: 'created', name: 'Teste Lead Scout' })
      expect(WebMock).to have_requested(:post, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas')
        .with(body: hash_including({ 'nmPessoa' => 'Teste Lead Scout', 'nrTelcelpessoa' => '11999990648' }))

      state = ScoutConversationState.for_conversation(conversation)
      expect(state.capability_state['customer']).to eq({ 'id' => '784868', 'name' => 'Teste Lead Scout' })
    end

    it 'returns failure result and remembers no customer when response lacks person id (FR-029)' do
      body = {
        sucesso: true,
        mensagem: 'OK',
        dados: { nmPessoa: 'Maria Silva' }
      }.to_json

      stub_request(:post, 'https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas')
        .with(headers: { 'token' => 'secret-erp-token-999' })
        .to_return(status: 200, body: body, headers: json_headers)

      result = registry.create(name: 'Maria Silva')

      expect(result[:error]).to eq(
        'O sistema do cliente não confirmou o cadastro (resposta sem identificador); ' \
        'ele pode ter sido criado. Não repita a operação; chame exit_handoff neste mesmo turno.'
      )
      state = ScoutConversationState.for_conversation(conversation)
      expect(state.capability_state['customer']).to be_nil
    end
  end
end
