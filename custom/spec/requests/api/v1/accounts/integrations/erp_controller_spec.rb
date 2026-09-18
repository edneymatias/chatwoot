# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Integrations::Erp', type: :request do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511987654321') }
  let(:url) { "/api/v1/accounts/#{account.id}/integrations/erp/data" }

  before do
    account.enable_features!('erp_integration')
    stub_request(:get, %r{https://wfh\.ichatr\.com\.br/webhook/pessoas\?idEmpresa=42&nrTelcelpessoa=0})
      .to_return(status: 200, body: { sucesso: true, dados: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'GET /api/v1/accounts/{account.id}/integrations/erp/data' do
    context 'when it is an unauthenticated user' do
      it 'returns 401 for unauthenticated request (U28)' do
        get url, params: { contact_id: contact.id }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:user) { create(:user, account: account, role: :agent) }

      it 'returns 404 when erp integration is not enabled (U29)' do
        get url,
            headers: user.create_new_auth_token,
            params: { contact_id: contact.id }

        expect(response).to have_http_status(:not_found)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('ERP integration not found or not enabled')
      end

      it 'returns 404 when contact is not found (U30)' do
        create(:integrations_hook, account: account, app_id: 'younus', status: :enabled, settings: { 'token' => 'valid-token', 'id_empresa' => '42' })

        get url,
            headers: user.create_new_auth_token,
            params: { contact_id: 999_999 }

        expect(response).to have_http_status(:not_found)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('Contact not found')
      end

      it 'delegates resolution to adapter and returns payload (U31)' do
        hook = create(:integrations_hook, account: account, app_id: 'younus', status: :enabled,
                                          settings: { 'token' => 'valid-token', 'id_empresa' => '42' })
        adapter = instance_double(Erp::Younus::Adapter)
        allow(Erp::AdapterFactory).to receive(:build).with(hook).and_return(adapter)
        expected_payload = {
          'status' => 'found',
          'data' => { 'cd_pessoa' => 123, 'nm_pessoa' => 'Maria Silva' },
          'multiple_matches' => false
        }
        allow(adapter).to receive(:fetch_data).with(contact).and_return(expected_payload)

        get url,
            headers: user.create_new_auth_token,
            params: { contact_id: contact.id }

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)).to eq(expected_payload)
      end

      it 'rescues erp errors, captures exception, and returns 503 (U32)' do
        hook = create(:integrations_hook, account: account, app_id: 'younus', status: :enabled,
                                          settings: { 'token' => 'valid-token', 'id_empresa' => '42' })
        adapter = instance_double(Erp::Younus::Adapter)
        allow(Erp::AdapterFactory).to receive(:build).with(hook).and_return(adapter)
        allow(adapter).to receive(:fetch_data).with(contact).and_raise(Erp::ApiError, 'ERP service error: 500')

        tracker = instance_double(ChatwootExceptionTracker)
        allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
        allow(tracker).to receive(:capture_exception)

        get url,
            headers: user.create_new_auth_token,
            params: { contact_id: contact.id }

        expect(response).to have_http_status(:service_unavailable)
        expect(JSON.parse(response.body)['error']).to eq('ERP service error: 500')
        expect(tracker).to have_received(:capture_exception)
      end
    end
  end
end
